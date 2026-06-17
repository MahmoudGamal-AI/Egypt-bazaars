"""
🚀 AWS Lambda WebSocket Handler
المدخل الرئيسي لـ AWS API Gateway WebSockets
"""
import json
import time
import asyncio
import logging
import boto3
from graph.state import build_initial_state
from graph.workflow import get_workflow
from memory.aws_memory import save_connection, remove_connection
from memory.working_memory import commit_session

logger = logging.getLogger(__name__)

# ============================================================
# AWS Global Scope (Cold Start Optimization)
# ============================================================
# بناء الجرّاف مرة واحدة وتهيئة المتغيرات على مستوى الحاوية.
# سيوفر هذا أكثر من ثانية إلى ثانيتين مع كل طلب في Lambda.
apigw_client = None
global_graph = get_workflow()


def get_apigw_client(event):
    """الحصول على عميل API Gateway Management — يُعاد استخدامه بين الطلبات."""
    global apigw_client
    if not apigw_client:
        domain = event.get('requestContext', {}).get('domainName')
        stage = event.get('requestContext', {}).get('stage')
        endpoint_url = f"https://{domain}/{stage}"
        apigw_client = boto3.client('apigatewaymanagementapi', endpoint_url=endpoint_url)
    return apigw_client


def send_to_connection(connection_id, data, event):
    """إرسال رسالة باك عبر الـ WebSocket للمستخدم."""
    client = get_apigw_client(event)
    try:
        client.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(data, ensure_ascii=False).encode('utf-8')
        )
    except Exception as e:
        logger.warning(f"Failed to send message to {connection_id}: {e}")


async def process_chat_message(connection_id: str, payload: dict, event: dict):
    """ربط الجراف وإرسال النتائج — مع كل حقول الـ State اللازمة."""
    message = payload.get("message", "")
    session_id = payload.get("session_id", "default_session")
    user_id = payload.get("user_id", "")

    # 1. تحديث الاتصال في DynamoDB
    save_connection(connection_id, user_id)

    # === Image Search Override ===
    if message.startswith("[IMAGE_SEARCH]"):
        image_url = message.replace("[IMAGE_SEARCH]", "").strip()
        send_to_connection(connection_id, {"type": "status", "agent": "commerce_agent", "status": "جاري تحليل الصورة والبحث عن المنتجات... 🔍"}, event)
        
        from services.gemini_multimodal_service import hybrid_image_search
        from core.aws_memory import search_products_hybrid
        
        text_embedding, image_embedding = await hybrid_image_search(image_url)
        if not text_embedding and not image_embedding:
            send_to_connection(connection_id, {"type": "error", "message": "حدث خطأ أثناء تحليل الصورة، تأكد من وضوح الصورة وجرب مرة أخرى."}, event)
            return
            
        matched_products = await asyncio.to_thread(search_products_hybrid, text_embedding, image_embedding, 3)
        
        cards = []
        for p in matched_products:
            cards.append({
                "type": "product",
                "data": {
                    "id": p["id"],
                    "nameAr": p["nameAr"],
                    "descriptionAr": p["descriptionAr"],
                    "price": p["price"],
                    "imageUrl": p["imageUrl"],
                    "bazaarId": p["bazaarId"],
                    "bazaarName": p["bazaarName"]
                },
                "actions": [
                    {"label": "🛒 أضف للسلة", "action": "add_to_cart", "params": {"product_id": p["id"], "name": p["nameAr"]}}
                ]
            })
            
        send_to_connection(connection_id, {
            "type": "done",
            "agent": "commerce_agent",
            "cards": cards,
            "quick_actions": [],
            "sources": [],
            "sentiment": "positive",
        }, event)
        
        # Async background commit
        asyncio.create_task(asyncio.to_thread(commit_session, session_id))
        return

    langfuse_handler = None
    try:
        # 2. إشعار المستخدم بأن النظام "يفكر"
        send_to_connection(connection_id, {
            "type": "status",
            "agent": "supervisor",
            "status": "جاري التفكير..."
        }, event)

        # 3. إعداد الـ Callbacks لـ Langfuse
        from core.langfuse_config import get_langfuse_handler
        from langchain_core.runnables.config import RunnableConfig
        langfuse_handler = get_langfuse_handler()
        config: RunnableConfig = {"callbacks": [langfuse_handler]} if langfuse_handler else {}

        # 4. HIGH-07: Use factory for consistent state initialization
        initial_state = build_initial_state(
            user_message=message,
            session_id=session_id,
            user_id=user_id,
        )

        final_result = None
        is_done_sent = False
        in_thought = False
        buffer = ""
        current_agent = "assistant"
        current_sentiment = "neutral"

        # Use astream_events to send chunks immediately, preventing 29s timeout hanging
        async for event_data in global_graph.astream_events(initial_state, version="v2", config=config):
            if event_data["event"] == "on_chat_model_stream":
                chunk = event_data["data"]["chunk"].content
                if isinstance(chunk, str) and chunk:
                    buffer += chunk
                    
                    if not in_thought:
                        if "<think>" in buffer:
                            parts = buffer.split("<think>", 1)
                            if parts[0]:
                                send_to_connection(connection_id, {"type": "chunk", "content": parts[0]}, event)
                            in_thought = True
                            buffer = parts[1]
                        else:
                            idx = buffer.rfind("<")
                            if idx != -1 and "<think>".startswith(buffer[idx:]):
                                if idx > 0:
                                    send_to_connection(connection_id, {"type": "chunk", "content": buffer[:idx]}, event)
                                buffer = buffer[idx:]
                            else:
                                send_to_connection(connection_id, {"type": "chunk", "content": buffer}, event)
                                buffer = ""
                                
                    if in_thought:
                        if "</think>" in buffer:
                            parts = buffer.split("</think>", 1)
                            in_thought = False
                            buffer = parts[1]
                        else:
                            idx = buffer.rfind("<")
                            if idx != -1 and "</think>".startswith(buffer[idx:]):
                                buffer = buffer[idx:]
                            else:
                                buffer = ""
            elif event_data["event"] == "on_tool_start":
                tool_name = event_data["name"]
                send_to_connection(connection_id, {
                    "type": "tool_status",
                    "status": f"جاري البحث في ({tool_name})..."
                }, event)
            elif event_data["event"] == "on_chain_end" and event_data["name"] == "build_response":
                # === السحر هنا: إرسال الانتهاء مبكراً قبل مهام الخلفية ===
                if not is_done_sent:
                    node_output = event_data["data"].get("output", {})
                    quick_actions_raw = node_output.get("quick_actions", [])
                    quick_actions_serialized = [
                        qa.__dict__ if hasattr(qa, '__dict__') else qa 
                        for qa in quick_actions_raw if isinstance(qa, dict) or hasattr(qa, '__dict__')
                    ]
                    
                    send_to_connection(connection_id, {
                        "type": "done",
                        "agent": current_agent,
                        "sentiment": current_sentiment,
                        "quick_actions": quick_actions_serialized,
                        "cached": False,
                        "cards": node_output.get("cards", []),
                        "sources": node_output.get("sources", []),
                    }, event)
                    is_done_sent = True
                    logger.info("Early 'done' event sent before background learning.")
            elif event_data["event"] == "on_chain_end" and event_data["name"] == "LangGraph":
                final_result = event_data["data"].get("output")
                if final_result:
                    current_agent = final_result.get("current_agent", current_agent)
                    current_sentiment = final_result.get("sentiment", current_sentiment)

        if not is_done_sent and final_result:
            agent_name = final_result.get("current_agent", current_agent)
            quick_actions_raw = final_result.get("quick_actions", [])
            quick_actions_serialized = [
                qa.__dict__ if hasattr(qa, '__dict__') else qa 
                for qa in quick_actions_raw if isinstance(qa, dict) or hasattr(qa, '__dict__')
            ]

            send_to_connection(connection_id, {
                "type": "done",
                "agent": agent_name,
                "sentiment": final_result.get("sentiment", current_sentiment),
                "quick_actions": quick_actions_serialized,
                "cached": False,
                "cards": final_result.get("cards", []),
                "sources": final_result.get("sources", []),
            }, event)
        elif not is_done_sent:
            raise Exception("Graph did not return a final explicit output.")

        # 5. حفظ الذاكرة
        commit_session(session_id)

    except asyncio.TimeoutError:
        logger.warning(f"Graph execution timeout for {connection_id}")
        send_to_connection(connection_id, {"type": "error", "message": "استغرق التفكير وقتاً طويلاً. حاول تاني."}, event)
    except Exception as e:
        logger.error(f"Error in graph execution for {connection_id}: {e}")
        send_to_connection(connection_id, {"type": "error", "message": "حدث خطأ غير متوقع بالخادم."}, event)
    finally:
        # Flush Langfuse gracefully inside Lambda
        try:
            if 'langfuse_handler' in locals() and langfuse_handler:
                if hasattr(langfuse_handler, 'flush'):
                    langfuse_handler.flush()
                elif hasattr(langfuse_handler, 'langfuse') and hasattr(langfuse_handler.langfuse, 'flush'):
                    langfuse_handler.langfuse.flush()
                logger.info("Langfuse traces flushed successfully.")
        except Exception as lf_err:
            logger.error(f"Failed to flush langfuse: {lf_err}")


def lambda_handler(event, context):
    """المعالج الرئيسي من AWS Lambda."""
    route_key = event.get('requestContext', {}).get('routeKey')
    connection_id = event.get('requestContext', {}).get('connectionId')

    if route_key == '$connect':
        logger.info(f"New connection: {connection_id}")
        return {'statusCode': 200}

    elif route_key == '$disconnect':
        logger.info(f"Disconnected: {connection_id}")
        remove_connection(connection_id)
        return {'statusCode': 200}

    elif route_key == '$default':
        try:
            body = json.loads(event.get('body', '{}'))
            # Handle Ping/Pong Heartbeat to keep AWS connection alive
            if body.get("action") == "ping":
                logger.info(f"Received ping from {connection_id}")
                return {'statusCode': 200}
                
            asyncio.run(process_chat_message(connection_id, body, event))
            return {'statusCode': 200}
        except Exception as e:
            logger.error(f"Error processing message: {e}")
            return {'statusCode': 500}

    return {'statusCode': 200}
