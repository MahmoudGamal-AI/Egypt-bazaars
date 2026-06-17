"""
📡 SSE (Server-Sent Events) Streaming — بث حقيقي للردود
✅ HIGH-07: Uses build_initial_state() for consistent initialization
✅ HIGH-04: Uses commit_session_async (non-blocking)
"""
import json
import asyncio
import logging
from fastapi import APIRouter, Query, HTTPException
from fastapi.responses import StreamingResponse

from graph.state import build_initial_state
from graph.workflow import get_workflow
from services.language_service import detect_language

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/stream", tags=["Streaming"])


@router.get("/chat")
async def stream_chat(
    message: str = Query(..., min_length=1, max_length=2000),
    session_id: str = Query(default="default", max_length=100),
    user_id: str = Query(default="", max_length=100),
):
    """SSE Chat Endpoint — بث حقيقي لرد الـ AI بدون انتظار كامل الرد."""

    async def event_generator():
        try:
            yield _sse_event("status", {"text": "⏳ جاري التفكير..."})

            graph = get_workflow()

            # HIGH-07: Use factory function for consistent state
            initial_state = build_initial_state(
                user_message=message,
                session_id=session_id,
                user_id=user_id,
            )
            initial_state["user_language"] = detect_language(message)

            # ============ Real Streaming via astream_events ============
            collected_response = ""
            current_agent = ""
            cards = []
            quick_actions = []
            sources = []

            async for event in graph.astream_events(initial_state, version="v2"):
                kind = event.get("event", "")
                name = event.get("name", "")

                # عقدة المنسق حددت الوكيل
                if kind == "on_chain_end" and name == "supervisor_node":
                    output = event.get("data", {}).get("output", {})
                    agent = output.get("current_agent", "")
                    if agent:
                        current_agent = agent
                        agent_labels = {
                            "commerce_agent": "🛍️ وكيل التسوق",
                            "explorer_agent": "🏛️ المرشد السياحي",
                            "assistant_agent": "💬 المساعد الذكي",
                            "personalization_agent": "✨ وكيل التخصيص",
                        }
                        label = agent_labels.get(agent, f"🤖 {agent}")
                        yield _sse_event("agent", {"agent": agent, "label": label})

                # بث أجزاء الرد من الـ LLM
                elif kind == "on_chat_model_stream":
                    chunk = event.get("data", {}).get("chunk", None)
                    if chunk and hasattr(chunk, "content") and chunk.content:
                        collected_response += chunk.content
                        yield _sse_event("token", {"text": chunk.content})

                # أداة قيد التنفيذ
                elif kind == "on_tool_start":
                    tool_name = event.get("name", "أداة")
                    yield _sse_event("tool", {
                        "tool": tool_name,
                        "status": "running",
                        "label": f"🔧 جاري استخدام: {tool_name}"
                    })

                # أداة انتهت
                elif kind == "on_tool_end":
                    tool_name = event.get("name", "أداة")
                    yield _sse_event("tool", {
                        "tool": tool_name,
                        "status": "done",
                        "label": f"✅ تم: {tool_name}"
                    })

                # عقدة بناء الرد النهائي
                elif kind == "on_chain_end" and name == "build_response_node":
                    output = event.get("data", {}).get("output", {})
                    final = output.get("final_response", "")
                    cards = output.get("cards", [])
                    quick_actions = output.get("quick_actions", [])
                    sources = output.get("sources", [])

                    if final and final != collected_response:
                        collected_response = final

            # ============ الرد النهائي ============
            if not collected_response:
                collected_response = "عذراً، لم أتمكن من الرد. جرب تاني! 😊"

            yield _sse_event("final", {
                "response": collected_response,
                "agent": current_agent,
                "cards": cards,
                "quick_actions": quick_actions,
                "sources": sources,
            })

            # HIGH-04: Non-blocking async commit
            try:
                from memory.working_memory import commit_session_async
                asyncio.create_task(commit_session_async(session_id))
            except Exception:
                pass

            yield _sse_event("done", {"text": "✅"})

        except asyncio.TimeoutError:
            yield _sse_event("error", {"text": "⏰ انتهت مهلة الرد. جرب تاني!"})
        except Exception as e:
            logger.error(f"SSE Stream error: {e}")
            yield _sse_event("error", {"text": f"حدث خطأ: {str(e)}"})

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.get("/health")
async def stream_health():
    """Health check for streaming endpoint."""
    return {"status": "ok", "streaming": True}


def _sse_event(event_type: str, data: dict) -> str:
    """Format SSE event string."""
    payload = json.dumps({"type": event_type, **data}, ensure_ascii=False)
    return f"event: {event_type}\ndata: {payload}\n\n"
