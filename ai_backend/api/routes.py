"""
🌐 API Routes — REST endpoints مع Smart Cache
✅ HIGH-07: Uses build_initial_state() for consistent initialization
✅ HIGH-04: Uses commit_session_async (non-blocking)
"""
import time
import asyncio
import logging
from fastapi import APIRouter, HTTPException, BackgroundTasks

from models.chat import ChatRequest, ChatResponse, QuickAction
from graph.state import build_initial_state
from graph.workflow import get_workflow
from memory.working_memory import get_session_summary, get_active_sessions_count, commit_session_async
from services.cache_service import get_cache

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["Chat"])

@router.post("/embeddings/sync-images")
async def sync_images_endpoint(background_tasks: BackgroundTasks):
    """🔄 تشغيل مزامنة البصمة البصرية للمنتجات الجديدة في الخلفية."""
    from scripts.sync_product_image_embeddings import sync_embeddings
    background_tasks.add_task(sync_embeddings)
    return {"message": "Image sync started in background", "status": "success"}



@router.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """💬 نقطة الدخول الرئيسية للمحادثة — مع Smart Cache."""
    start = time.time()

    # === Image Search Override ===
    if request.message.startswith("[IMAGE_SEARCH]"):
        image_url = request.message.replace("[IMAGE_SEARCH]", "").strip()
        
        from services.gemini_multimodal_service import hybrid_image_search
        from core.aws_memory import search_products_hybrid
        
        text_embedding, image_embedding = await hybrid_image_search(image_url)
        if not text_embedding and not image_embedding:
            raise HTTPException(status_code=500, detail="حدث خطأ أثناء تحليل الصورة، تأكد من وضوح الصورة وجرب مرة أخرى.")
            
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
            
        asyncio.create_task(commit_session_async(request.session_id))
        
        return ChatResponse(
            text="إليك المنتجات المطابقة لصورتك:",
            cards=cards,
            quick_actions=[],
            sources=[],
            agent_used="commerce_agent",
            sentiment="positive",
        )

    # === فحص الـ Cache أولاً ===
    cache = get_cache()
    cached = cache.get(request.message, user_id=request.user_id or "")
    if cached:
        elapsed = (time.time() - start) * 1000
        logger.info(f"⚡ Cache hit! ({elapsed:.0f}ms)")
        return ChatResponse(
            text=cached.get("text", ""),
            cards=cached.get("cards", []),
            quick_actions=[
                QuickAction(**qa) for qa in cached.get("quick_actions", [])
            ],
            sources=cached.get("sources", []),
            agent_used=cached.get("agent", ""),
            sentiment=cached.get("sentiment", "neutral"),
        )

    # === تشغيل الجراف ===
    try:
        graph = get_workflow()

        # HIGH-07: Use factory function for consistent state
        initial_state = build_initial_state(
            user_message=request.message,
            session_id=request.session_id,
            user_id=request.user_id or "",
            latitude=request.latitude,
            longitude=request.longitude,
        )

        result = await asyncio.wait_for(
            graph.ainvoke(initial_state),
            timeout=50.0
        )

        response_data = {
            "text": result.get("final_response", "عذراً، حدث خطأ."),
            "agent": result.get("current_agent", ""),
            "quick_actions": result.get("quick_actions", []),
            "sources": result.get("sources", []),
            "sentiment": result.get("sentiment", "neutral"),
            "cards": result.get("cards", []),
        }

        # === تخزين في الـ Cache ===
        cache.set(request.message, response_data, user_id=request.user_id or "")

        # HIGH-04: Non-blocking async commit
        asyncio.create_task(commit_session_async(request.session_id))

        elapsed = (time.time() - start) * 1000
        logger.info(f"✅ Response in {elapsed:.0f}ms | Agent: {response_data['agent']}")

        return ChatResponse(
            text=response_data["text"],
            cards=response_data["cards"],
            quick_actions=[
                QuickAction(**qa) for qa in response_data["quick_actions"]
            ],
            sources=response_data["sources"],
            agent_used=response_data["agent"],
            sentiment=response_data["sentiment"],
        )

    except Exception as e:
        logger.error(f"Chat error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/chat/history/{session_id}")
async def get_chat_history(session_id: str):
    """📋 الحصول على ملخص سجل الجلسة."""
    summary = get_session_summary(session_id)
    return {
        "session_id": session_id,
        "summary": summary,
    }


@router.get("/stats")
async def get_stats():
    """📊 إحصائيات النظام مع الـ Cache."""
    cache = get_cache()
    return {
        "active_sessions": get_active_sessions_count(),
        "cache": cache.stats,
        "status": "running",
    }


@router.delete("/cache")
async def clear_cache():
    """🗑️ مسح الـ Cache."""
    cache = get_cache()
    cache.clear()
    return {"status": "cache cleared"}
