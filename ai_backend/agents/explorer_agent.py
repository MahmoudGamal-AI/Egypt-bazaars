"""
🏛️ Explorer Agent — وكيل الاستكشاف الموحد
يجمع بين البحث في التاريخ والآثار (History) والإرشاد السياحي للأماكن (Tour Guide)
يستخدم RAG + Tool Calling للبحث المجمّع السريع
"""
import logging
import asyncio
from graph.state import AgentState

from prompts.agent_prompts import EXPLORER_AGENT_PROMPT
from tools.all_tools import ARTIFACT_TOOLS, BAZAAR_TOOLS, PRODUCT_TOOLS
from tools.web_tools import WEB_TOOLS
from agents.tool_executor import run_agent_with_tools
from langchain_core.messages import AIMessage

# دمج أدوات الآثار وأدوات الإنترنت وأدوات المنتجات
EXPLORER_TOOLS = ARTIFACT_TOOLS + WEB_TOOLS + PRODUCT_TOOLS

logger = logging.getLogger(__name__)

async def run_explorer_agent(state: AgentState) -> dict:
    messages = state.get("messages", [])
    last_msg_content = messages[-1].content if messages else ""
    if isinstance(last_msg_content, list):
        last_msg = " ".join([m.get("text", "") if isinstance(m, dict) else str(m) for m in last_msg_content])
    else:
        last_msg = str(last_msg_content)
        
    chat_history = state.get("chat_history", [])

    extra_parts = []

    # سياق الذاكرة
    memory_ctx = state.get("memory_context", "")
    if memory_ctx:
        extra_parts.append(f"\n\n--- سياق المستخدم ---\n{memory_ctx}")

    # تعليمات اللغة
    user_lang = state.get("user_language", "ar")
    from services.language_service import get_language_instruction
    lang_instruction = get_language_instruction(user_lang)
    if lang_instruction:
        extra_parts.append(lang_instruction)

    # الموقع الجغرافي
    lat = state.get("latitude")
    lng = state.get("longitude")
    if lat and lng:
        extra_parts.append(f"\n\n📍 الموقع الحالي للمستخدم (Latitude: {lat}, Longitude: {lng}). يمكنك استخدام هذه الإحداثيات عند البحث عن الأماكن القريبة.")

    extra_context = "".join(extra_parts)
    session_id = state.get("session_id", "default")
    
    try:
        response, final_messages = await run_agent_with_tools(
            system_prompt=EXPLORER_AGENT_PROMPT,
            user_message=last_msg,
            tools=EXPLORER_TOOLS,
            context=extra_context,
            chat_history=chat_history,
            session_id=session_id,
            agent_name="explorer_agent",
        )
    except Exception as e:
        logger.error(f"Explorer agent error: {e}")
        response = "عذراً، حدث خطأ أثناء البحث عن المعلومات التاريخية والسياحية."
        final_messages = []

    # استخراج الكروت (منتجات، بازارات، آثار)
    from agents.commerce_agent import _extract_all_cards_from_text
    
    tool_outputs_text = "\n".join([str(msg.get("content", "")) if isinstance(msg, dict) else getattr(msg, "content", "") for msg in final_messages if (isinstance(msg, dict) and msg.get("type") == "tool") or getattr(msg, "type", "") == "tool"])
    
    new_cards = _extract_all_cards_from_text(tool_outputs_text)
    
    viewed_items_dicts = []
    rich_cards = []
    
    if new_cards:
        for c in new_cards:
            if hasattr(c, "model_dump"):
                viewed_items_dicts.append(c.model_dump())
            if hasattr(c, "to_rich_card"):
                rich_cards.append(c.to_rich_card())

    return {
        "agent_output": response,
        "current_agent": "explorer_agent",
        "current_viewed_items": viewed_items_dicts,
        "cards": rich_cards,
        "messages": [AIMessage(content=response, name="explorer_agent")],
    }
