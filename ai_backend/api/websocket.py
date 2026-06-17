"""
🔌 WebSocket Handler — معالج اتصالات WebSocket
✅ HIGH-07: Uses build_initial_state() for consistent initialization
✅ HIGH-04: Uses commit_session_async (non-blocking)
"""
import asyncio
import logging
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from graph.state import build_initial_state
from graph.workflow import get_workflow
from memory.working_memory import (
    is_memory_loaded, mark_memory_loaded,
    set_long_term_context, commit_session_async,
)
from services.language_service import detect_language
import json

logger = logging.getLogger(__name__)

router = APIRouter(tags=["WebSocket"])


# ============================================================
# تحميل الذاكرة طويلة المدى
# ============================================================

async def _load_long_term_memory_ws(session_id: str, user_id: str):
    """تحميل episodic + semantic memory — مرة واحدة لكل جلسة."""
    if is_memory_loaded(session_id) or not user_id:
        return

    try:
        from memory.episodic_memory import get_episode_context
        from memory.semantic_memory import load_preferences, get_preferences_context

        episode_ctx, prefs = await asyncio.gather(
            get_episode_context(user_id),
            load_preferences(user_id),
            return_exceptions=True,
        )

        ep_text = episode_ctx if isinstance(episode_ctx, str) else ""
        prefs_text = ""
        if not isinstance(prefs, BaseException):
            prefs_text = get_preferences_context(prefs)

        set_long_term_context(session_id, ep_text, prefs_text)
        mark_memory_loaded(session_id)

        if ep_text or prefs_text:
            logger.info(f"🧠 [WS] ذاكرة طويلة المدى — {user_id[:8]}...")

    except Exception as e:
        logger.warning(f"⚠️ [WS] خطأ في تحميل الذاكرة: {e}")
        mark_memory_loaded(session_id)


@router.websocket("/ws/chat/{session_id}")
async def websocket_chat(websocket: WebSocket, session_id: str):
    """🔌 WebSocket endpoint — streaming responses مع ذاكرة ثلاثية."""
    await websocket.accept()
    logger.info(f"🔌 اتصال جديد: {session_id}")

    graph = get_workflow()

    try:
        while True:
            data = await websocket.receive_json()
            message = data.get("message", "")
            user_id = data.get("user_id", "")

            if not message:
                await websocket.send_json({"type": "error", "text": "الرسالة فارغة"})
                continue

            # === Image Search Override ===
            if message.startswith("[IMAGE_SEARCH]"):
                image_url = message.replace("[IMAGE_SEARCH]", "").strip()
                await websocket.send_json({"type": "status", "agent": "commerce_agent", "status": "جاري تحليل الصورة والبحث عن المنتجات... 🔍"})
                
                from services.gemini_multimodal_service import hybrid_image_search
                from core.aws_memory import search_products_hybrid
                
                text_embedding, image_embedding = await hybrid_image_search(image_url)
                if not text_embedding and not image_embedding:
                    await websocket.send_json({"type": "error", "text": "حدث خطأ أثناء تحليل الصورة، تأكد من وضوح الصورة وجرب مرة أخرى."})
                    continue
                
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
                
                await websocket.send_json({
                    "type": "done",
                    "agent": "commerce_agent",
                    "cards": cards,
                    "quick_actions": [],
                    "sources": [],
                    "sentiment": "positive",
                })
                # HIGH-04: Non-blocking async commit
                asyncio.create_task(commit_session_async(session_id))
                continue

            # === تحميل ذاكرة طويلة المدى (مرة واحدة) ===
            await _load_long_term_memory_ws(session_id, user_id)

            # === كشف اللغة ===
            user_language = detect_language(message)

            # حالة الكتابة والتفكير
            await websocket.send_json({"type": "typing", "agent": "supervisor"})

            # HIGH-07: Use factory function for consistent state
            initial_state = build_initial_state(
                user_message=message,
                session_id=session_id,
                user_id=user_id,
            )
            initial_state["user_language"] = user_language

            try:
                # 🌟 Real Streaming using `astream_events` 🌟
                from langchain_core.runnables import RunnableConfig
                from core.langfuse_config import get_langfuse_handler
                langfuse_handler = get_langfuse_handler()
                config: RunnableConfig | None = {"callbacks": [langfuse_handler]} if langfuse_handler else None
                
                final_result = None
                in_thought = False
                buffer = ""
                
                async for event in graph.astream_events(initial_state, version="v2", config=config):
                    # استقبال تدفق النصوص من الموديل الحي (LLM)
                    if event["event"] == "on_chat_model_stream":
                        chunk = event["data"]["chunk"].content
                        if isinstance(chunk, str) and chunk:
                            buffer += chunk
                            
                            if not in_thought:
                                if "<think>" in buffer:
                                    parts = buffer.split("<think>", 1)
                                    if parts[0]:
                                        await websocket.send_json({"type": "chunk", "content": parts[0]})
                                        await asyncio.sleep(0.01)
                                    in_thought = True
                                    buffer = parts[1]
                                else:
                                    idx = buffer.rfind("<")
                                    if idx != -1 and "<think>".startswith(buffer[idx:]):
                                        if idx > 0:
                                            await websocket.send_json({"type": "chunk", "content": buffer[:idx]})
                                            await asyncio.sleep(0.01)
                                        buffer = buffer[idx:]
                                    else:
                                        await websocket.send_json({"type": "chunk", "content": buffer})
                                        await asyncio.sleep(0.01)
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

                    # استقبال استدعاءات الأدوات
                    elif event["event"] == "on_tool_start":
                        tool_name = event["name"]
                        await websocket.send_json({
                            "type": "tool_status",
                            "status": f"جاري البحث في ({tool_name})..."
                        })
                        
                    # عند نهاية الجراف
                    elif event["event"] == "on_chain_end" and event["name"] == "LangGraph":
                        final_result = event["data"].get("output")
                        
                # بعد انتهاء الـ Streaming
                if final_result:
                    agent_used = final_result.get("current_agent", "")
                    
                    await websocket.send_json({
                        "type": "done",
                        "agent": agent_used,
                        "quick_actions": final_result.get("quick_actions", []),
                        "cards": final_result.get("cards", []),
                        "sources": final_result.get("sources", []),
                        "sentiment": final_result.get("sentiment", "neutral"),
                    })
                    
                    # HIGH-04: Non-blocking async commit
                    asyncio.create_task(commit_session_async(session_id))
                else:
                    raise ValueError("Graph did not return a final explicit output.")

            except Exception as e:
                logger.error(f"❌ خطأ في معالجة الرسالة للـ WebSocket: {e}")
                await websocket.send_json({
                    "type": "error",
                    "text": "عذراً، حدث خطأ أثناء معالجة طلبك. حاول مرة تانية.",
                })

    except WebSocketDisconnect:
        logger.info(f"🔌 تم قطع الاتصال: {session_id}")
    except Exception as e:
        logger.error(f"❌ خطأ WebSocket غريب: {e}")
