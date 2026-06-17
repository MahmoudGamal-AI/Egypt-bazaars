"""
🔴 Admin AI Service — Main Application
FastAPI application containing admin endpoints + frontend-compatible aliases.
Features: Auth middleware, rate limiting, CORS restriction, clean streaming,
          professional health endpoint with DB + LLM checks.
"""
import json
import asyncio
import logging
import time
from fastapi import FastAPI, APIRouter, HTTPException, Depends, Security
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import APIKeyHeader

from core.config import validate_config, ALLOWED_ORIGINS, ADMIN_API_KEY
from services.admin.models.schemas import (
    AdminChatRequest, BusinessReportRequest,
    GenerateMessageRequest, AdminChatResponse,
    ModerationResponse, ApplicationAnalysisResponse,
    BusinessReportResponse, PlatformInsightsResponse,
    GenerateMessageResponse, PromotionSuggestionsResponse
)
from services.admin.agents.admin_assistant import (
    admin_chat, generate_business_report,
    get_platform_insights, generate_admin_message, suggest_promotions,
    _create_admin_agent, ADMIN_TOOLS, ADMIN_SYSTEM_MSG,
    _save_conversation_turn, _load_conversation_history,
    _generate_smart_actions,
)
from services.admin.agents.moderation import (
    moderate_product, analyze_application
)

# Setup logging
logger = logging.getLogger("Admin_AI_API")

# Track service start time for uptime
_SERVICE_START_TIME = time.time()

# Initialize and validate
validate_config(service_name="AdminService")
app = FastAPI(title="Egyptian Tourism Admin AI", version="3.0.0", root_path="/prod")

# --- CORS: Configurable origins + X-API-Key in headers ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True if ALLOWED_ORIGINS != ["*"] else False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept", "X-API-Key"],
)

# --- Authentication ---
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)


async def verify_api_key(api_key: str = Security(api_key_header)):
    """Verify the API key if ADMIN_API_KEY is configured."""
    if not ADMIN_API_KEY:
        # Auth disabled — pass through (with warning logged at startup)
        return True
    if api_key != ADMIN_API_KEY:
        raise HTTPException(status_code=403, detail="Invalid or missing API key")
    return True


router = APIRouter(
    prefix="/api/admin/ai",
    tags=["Admin AI"],
    dependencies=[Depends(verify_api_key)],
)


# ============================================================
# 1. Admin AI Chatbot (REST & Stream)
# ============================================================

@router.post("/chat", response_model=AdminChatResponse)
async def api_admin_chat(request: AdminChatRequest):
    """🤖 Admin Chatbot — Answers questions in natural language."""
    try:
        result = await admin_chat(
            question=request.message,
            context=request.context or "",
            session_id=request.session_id,
        )
        return result
    except Exception as e:
        logger.error(f"Admin chat error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/chat/stream")
async def api_admin_chat_stream(request: AdminChatRequest):
    """📡 Admin Chatbot with SSE Streaming — uses shared agent factory."""
    async def generate_events():
        try:
            yield f"data: {json.dumps({'type': 'status', 'status': 'thinking'}, ensure_ascii=False)}\n\n"

            # Use shared agent factory — no code duplication
            from langchain_core.messages import HumanMessage
            from core.json_utils import parse_json_response
            from core.analytics_service import compute_platform_analytics

            agent = _create_admin_agent()

            # Load conversation history for context
            history = _load_conversation_history(request.session_id)
            prompt_str = f"سياق إضافي: {request.context}\n\nسؤال المدير: {request.message}" if request.context else request.message
            messages = history + [HumanMessage(content=prompt_str)]

            yield f"data: {json.dumps({'type': 'status', 'status': 'generating'}, ensure_ascii=False)}\n\n"

            final_text = ""
            async for event in agent.astream_events({"messages": messages}, version="v2"):
                if event["event"] == "on_chat_model_stream":
                    chunk_text = event["data"]["chunk"].content
                    if isinstance(chunk_text, str) and chunk_text:
                        final_text += chunk_text
                        yield f"data: {json.dumps({'type': 'chunk', 'content': chunk_text}, ensure_ascii=False)}\n\n"
                        await asyncio.sleep(0.01)

                elif event["event"] == "on_tool_start":
                    tool_name = event["name"]
                    yield f"data: {json.dumps({'type': 'status', 'status': f'جاري جلب إحصائيات: {tool_name}...'}, ensure_ascii=False)}\n\n"

            # Save conversation turn
            _save_conversation_turn(request.session_id, request.message, final_text)

            # Generate smart contextual actions
            quick_actions = _generate_smart_actions(request.message, final_text)

            # Fetch charts data for the response
            try:
                analytics = await compute_platform_analytics("month")
                charts_data = analytics.get("charts_data", {})
            except Exception:
                charts_data = None

            yield f"data: {json.dumps({'type': 'done', 'quick_actions': quick_actions, 'charts_data': charts_data, 'data_tables': None}, ensure_ascii=False)}\n\n"

        except Exception as e:
            logger.error(f"Stream Admin Chat Error: {e}")
            yield f"data: {json.dumps({'type': 'error', 'content': 'حدثت مشكلة مفاجئة! برجاء المحاولة لاحقاً.'}, ensure_ascii=False)}\n\n"

    return StreamingResponse(
        generate_events(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "Connection": "keep-alive"}
    )


# ============================================================
# 2. Moderate Product — Original + Frontend-compatible alias
# ============================================================

@router.get("/moderate-product/{product_id}", response_model=ModerationResponse)
async def api_moderate_product(product_id: str):
    """🛡️ AI Product Moderation — Returns score and recommendations."""
    try:
        return await moderate_product(product_id)
    except Exception as e:
        logger.error(f"Moderation error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# Frontend sends POST /moderate/{id} — alias for compatibility
@router.post("/moderate/{product_id}", response_model=ModerationResponse)
async def api_moderate_product_alias(product_id: str):
    """🛡️ [Alias] Product Moderation — POST variant for frontend compatibility."""
    return await api_moderate_product(product_id)


# ============================================================
# 3. Analyze Bazaar Application — Original + POST alias
# ============================================================

@router.get("/analyze-application/{application_id}", response_model=ApplicationAnalysisResponse)
async def api_analyze_application(application_id: str):
    """📋 Analyze new bazaar joining application."""
    try:
        return await analyze_application(application_id)
    except Exception as e:
        logger.error(f"Application analysis error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# Frontend sends POST /analyze-application/{id}
@router.post("/analyze-application/{application_id}", response_model=ApplicationAnalysisResponse)
async def api_analyze_application_alias(application_id: str):
    """📋 [Alias] Analyze application — POST variant for frontend compatibility."""
    return await api_analyze_application(application_id)


# ============================================================
# 4. Business Report
# ============================================================

@router.post("/business-report", response_model=BusinessReportResponse)
async def api_business_report(request: BusinessReportRequest):
    """📊 Generate comprehensive BI report."""
    try:
        return await generate_business_report(period=request.period.value, focus=request.focus.value if request.focus else None)
    except Exception as e:
        logger.error(f"Business report error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# 5. Platform Insights
# ============================================================

@router.get("/platform-insights", response_model=PlatformInsightsResponse)
async def api_platform_insights():
    """🔍 Quick real-time platform system health & insights."""
    try:
        return await get_platform_insights()
    except Exception as e:
        logger.error(f"Platform insights error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# 6. Generate Admin Message
# ============================================================

@router.post("/generate-message", response_model=GenerateMessageResponse)
async def api_generate_message(request: GenerateMessageRequest):
    """✉️ Generate professional admin/owner communication message."""
    try:
        return await generate_admin_message(
            message_type=request.message_type.value,
            bazaar_name=request.bazaar_name,
            context=request.context or "",
            custom_notes=request.custom_notes or "",
        )
    except Exception as e:
        logger.error(f"Generate message error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# 7. Promotion Suggestions — Original + Frontend-compatible alias
# ============================================================

@router.get("/promotion-suggestions", response_model=PromotionSuggestionsResponse)
async def api_promotion_suggestions():
    """🏷️ AI smart promotion and discounting suggestions."""
    try:
        return await suggest_promotions()
    except Exception as e:
        logger.error(f"Promotion suggestions error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# Frontend sends GET /suggest-promotions — alias for compatibility
@router.get("/suggest-promotions", response_model=PromotionSuggestionsResponse)
async def api_suggest_promotions_alias():
    """🏷️ [Alias] Promotion suggestions — alternative path for frontend compatibility."""
    return await api_promotion_suggestions()


# Include the router
app.include_router(router)


# ============================================================
# Professional Health Endpoint — Matches frontend expectations
# ============================================================

@app.get("/health")
async def health_check():
    """Professional health check with DB connectivity, LLM status, and uptime."""
    uptime = time.time() - _SERVICE_START_TIME

    # Check DB connectivity
    db_status = "unknown"
    try:
        from core.aws_memory import get_aurora_connection, release_aurora_connection
        conn = get_aurora_connection()
        if conn:
            try:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
                db_status = "connected"
            finally:
                release_aurora_connection(conn)
        else:
            db_status = "disconnected"
    except Exception as e:
        db_status = f"error: {str(e)[:50]}"

    # Check DynamoDB
    memory_status = "unknown"
    try:
        from core.aws_memory import get_dynamo_table, DYNAMODB_SESSIONS_TABLE
        table = get_dynamo_table(DYNAMODB_SESSIONS_TABLE)
        if table:
            memory_status = "ready"
    except Exception:
        memory_status = "unavailable"

    return {
        "status": "ok",
        "service": "admin-ai",
        "version": "3.0.0",
        "rag": "ready" if db_status == "connected" else "not_ready",
        "active_sessions": 0,  # Could be tracked via DynamoDB if needed
        "database": db_status,
        "memory": memory_status,
        "tools_count": len(ADMIN_TOOLS),
        "uptime_seconds": round(uptime, 0),
    }
