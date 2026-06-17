"""
🧠 AgentState — تعريف حالة الجراف الرئيسية
كل المعلومات اللي بتتنقل بين العقد (nodes) في LangGraph

✅ HIGH-07: build_initial_state() factory for consistent initialization
"""
import time
from typing import TypedDict, Annotated
from langchain_core.messages import BaseMessage, HumanMessage
from langgraph.graph.message import add_messages


class AgentState(TypedDict):
    """الحالة المركزية للنظام — بتتشارك بين كل الوكلاء."""

    # === الرسائل ===
    messages: Annotated[list[BaseMessage], add_messages]

    # === معرفات الجلسة ===
    session_id: str
    user_id: str

    # === حالة التوجيه ===
    current_agent: str          # اسم الوكيل الحالي
    agent_output: str           # مخرج الوكيل

    # === الرد النهائي ===
    final_response: str
    cards: list[dict]           # Rich cards (منتجات/آثار/بازارات)
    quick_actions: list[dict]   # أزرار إجراءات سريعة
    sources: list[str]          # مصادر (لو استخدم بحث الويب)

    # === الذاكرة والسياق ===
    chat_history: list[BaseMessage] # رسائل المحادثة السابقة
    memory_context: str         # سياق من الذاكرة (ملخصات + تفضيلات)
    conversation_summary: str   # ملخص المحادثة الحالية

    # === التخصيص ===
    sentiment: str              # مزاج المستخدم (positive/neutral/negative/curious)
    proactive_suggestions: list[dict]  # اقتراحات تلقائية
    user_preferences: dict      # تفضيلات المستخدم المحملة
    user_language: str          # لغة المستخدم: "ar" أو "en"

    # === التتبع والأداء ===
    start_time: float           # وقت بدء المعالجة — لحساب الـ latency
    error_count: int            # عدد الأخطاء في هذه الدورة
    last_agent_used: str        # آخر وكيل استُخدم — للـ follow-up detection

    # === Context Hand-off (تمرير السياق بين الوكلاء) ===
    current_viewed_items: list[dict]  # المنتجات المعروضة حالياً أمام المستخدم
    last_search_query: str            # آخر استعلام بحث تم تنفيذه
    last_tool_results: list[dict]     # نتائج الأدوات الأخيرة (خام)
    
    # === الموقع الجغرافي ===
    latitude: float | None
    longitude: float | None


def build_initial_state(
    user_message: str,
    session_id: str = "default",
    user_id: str = "",
    latitude: float | None = None,
    longitude: float | None = None,
) -> dict:
    """HIGH-07: Factory function for consistent state initialization.

    Ensures ALL API channels (WebSocket, SSE, REST) start with identical state shape.
    This eliminates the risk of missing keys causing KeyError at runtime.
    """
    return {
        "messages": [HumanMessage(content=user_message)],
        "session_id": session_id,
        "user_id": user_id,
        "current_agent": "",
        "agent_output": "",
        "final_response": "",
        "cards": [],
        "quick_actions": [],
        "sources": [],
        "chat_history": [],
        "memory_context": "",
        "conversation_summary": "",
        "sentiment": "neutral",
        "proactive_suggestions": [],
        "user_preferences": {},
        "user_language": "ar",
        "start_time": time.time(),
        "error_count": 0,
        "last_agent_used": "",
        "current_viewed_items": [],
        "last_search_query": "",
        "last_tool_results": [],
        "latitude": latitude,
        "longitude": longitude,
    }
