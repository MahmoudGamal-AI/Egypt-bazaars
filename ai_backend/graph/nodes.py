"""
🔀 Graph Nodes — عقد الجراف
كل الدوال اللي بتتنفذ في كل عقدة من LangGraph
✅ HIGH-02: Consolidated summarizer into episodic_memory
✅ HIGH-08: learn_preferences throttled to every 5th message
✅ MED-08: Enhanced reflection with language/markdown/ID checks
"""
import logging
from graph.state import AgentState
from services.gemini_service import get_llm
from langchain_core.messages import AIMessage

# استيراد كل الوكلاء
from agents.supervisor import run_supervisor
from agents.commerce_agent import run_commerce_agent
from agents.explorer_agent import run_explorer_agent
from agents.assistant_agent import run_assistant_agent
from agents.personalization_agent import run_personalization_agent, analyze_sentiment_quick

logger = logging.getLogger(__name__)


# ============================================================
# عقدة تحميل الذاكرة (أول عقدة بعد الدخول)
# ============================================================

async def memory_loader_node(state: AgentState) -> dict:
    """تحميل ذاكرة المستخدم — تفضيلات + ملخصات سابقة + تحليل مشاعر + كشف لغة."""
    user_id = state.get("user_id", "")
    messages = state.get("messages", [])
    last_message = messages[-1].content if messages else ""
    last_message_text = last_message if isinstance(last_message, str) else str(last_message)

    memory_context = ""
    user_preferences = {}
    sentiment = "neutral"
    conversation_summary = state.get("conversation_summary", "")
    chat_history = []

    # كشف لغة المستخدم (فوري)
    from services.language_service import detect_language
    user_language = detect_language(last_message_text) if last_message_text else "ar"

    try:
        # تحميل التفضيلات
        if user_id:
            from memory.semantic_memory import load_preferences, get_preferences_context
            from memory.episodic_memory import get_episode_context

            import asyncio
            prefs, episode_ctx = await asyncio.gather(
                load_preferences(user_id),
                get_episode_context(user_id)
            )
            
            if prefs:
                user_preferences = prefs.model_dump()
                prefs_ctx = get_preferences_context(prefs)
            else:
                prefs_ctx = ""
                
            if not episode_ctx:
                episode_ctx = ""

            parts = []
            if prefs_ctx:
                parts.append(prefs_ctx)
            if episode_ctx:
                parts.append(episode_ctx)
            memory_context = "\n\n".join(parts)

        # تحليل المشاعر (keyword-based — فوري)
        if last_message_text:
            sentiment = await analyze_sentiment_quick(last_message_text)

    except Exception as e:
        logger.warning(f"خطأ في تحميل الذاكرة: {e}")

    # حفظ في الذاكرة العاملة + تلخيص لو لازم
    try:
        from memory.working_memory import (
            add_message, update_session_metadata, get_session,
            should_summarize, get_messages,
        )
        # HIGH-02: Use episodic_memory.summarize_conversation (consolidated)
        from memory.episodic_memory import summarize_conversation

        session_id = state.get("session_id", "default")
        if messages:
            add_message(session_id, messages[-1])

        session = get_session(session_id)
        msg_count = session.get("message_count", 0)

        # BUG-01 Fix: get actual messages from working memory
        session_messages = get_messages(session_id)

        # تلخيص المحادثة كل 15 رسالة (using episodic_memory)
        if should_summarize(session_id):
            from memory.working_memory import get_conversation_text
            conv_text = get_conversation_text(session_id)
            summary = await summarize_conversation(conv_text, session_id)
            if summary:
                conversation_summary = summary
                logger.info(f"📝 تم تلخيص المحادثة ({msg_count} رسالة)")

        # استخراج المحادثات السابقة لتغذية الـ LLM
        # نستثني الرسالة الأخيرة لأنها الرسالة الحالية للمستخدم
        chat_history = session_messages[:-1] if session_messages else []

        update_session_metadata(
            session_id,
            user_id=user_id,
            current_sentiment=sentiment,
            last_agent="",
        )
    except Exception as e:
        logger.warning(f"خطأ في الذاكرة العاملة: {e}")

    return {
        "chat_history": chat_history,
        "memory_context": memory_context,
        "user_preferences": user_preferences,
        "sentiment": sentiment,
        "conversation_summary": conversation_summary,
        "user_language": user_language,
        "cards": [], # مسح الكروت القديمة في بداية كل دورة جديدة لمنع التراكم
    }


# ============================================================
# عقدة المنسق
# ============================================================

async def supervisor_node(state: AgentState) -> dict:
    """عقدة المنسق — بيوجه الطلب للوكيل المناسب."""
    return await run_supervisor(state)


# ============================================================
# عقد الوكلاء
# ============================================================

async def commerce_agent_node(state: AgentState) -> dict:
    return await run_commerce_agent(state)

async def explorer_agent_node(state: AgentState) -> dict:
    return await run_explorer_agent(state)

async def assistant_agent_node(state: AgentState) -> dict:
    return await run_assistant_agent(state)

async def personalization_agent_node(state: AgentState) -> dict:
    return await run_personalization_agent(state)



# ============================================================
# عقدة المراجعة الذاتية (Score-based — سريعة بدون LLM call)
# ============================================================

# علامات الردود الضعيفة
_WEAK_INDICATORS = [
    "عذراً، حدث خطأ",
    "مش قادر أساعدك",
    "لم يتم العثور",
    "جرب تاني",
    "حدث خطأ مؤقت",
    "لم أتمكن",
    "I can't",
    "I'm sorry",
    "error occurred",
]


async def reflection_node(state: AgentState) -> dict:
    """مراجعة وتحسين رد الوكيل — Score-based (سريع بدون LLM call إضافي).

    القواعد:
    1. لو الرد أقل من 30 حرف → إعادة صياغة بـ LLM
    2. لو الرد generic/ضعيف → محاولة تحسين بـ LLM
    3. لو الرد كويس → يمرّ بدون تعديل
    """
    from config import ENABLE_REFLECTION

    if not ENABLE_REFLECTION:
        # MED-01 Fix: Return empty dict (no changes) instead of full state
        return {}

    output = state.get("agent_output", "")
    agent = state.get("current_agent", "")
    user_language = state.get("user_language", "ar")

    if not output:
        return {}

    # === فحص 1: الرد قصير جداً ===
    if len(output.strip()) < 30:
        improved = await _improve_response(output, agent)
        if improved:
            return {"agent_output": improved}
        return {}

    # === فحص 2: الرد generic/ضعيف ===
    output_lower = output.lower()
    is_weak = any(indicator in output_lower for indicator in _WEAK_INDICATORS)

    if is_weak and len(output.strip()) < 100:
        improved = await _improve_response(output, agent)
        if improved and len(improved) > len(output):
            return {"agent_output": improved}

    # === MED-08: فحص 3: لغة خاطئة ===
    # لو المستخدم بيتكلم عربي والرد بالإنجليزي (> 80% English chars)
    if user_language == "ar" and output.strip():
        ascii_ratio = sum(1 for c in output if c.isascii() and c.isalpha()) / max(len(output), 1)
        if ascii_ratio > 0.7:
            logger.warning(f"🔍 Reflection: Language mismatch (user=ar, response=en)")
            improved = await _improve_response(
                f"الرد التالي بالإنجليزي والمستخدم عربي، ترجمه للعربية:\n{output}", agent
            )
            if improved:
                return {"agent_output": improved}

    # === MED-08: فحص 4: جداول Markdown في ردود المحادثة (الموبايل مش بيرندرها كويس) ===
    if "|---" in output or "| ---" in output:
        logger.info(f"🔍 Reflection: Markdown table detected, reformatting")
        improved = await _improve_response(
            f"حول الجدول التالي لقائمة مرتبة بدل الجدول:\n{output}", agent
        )
        if improved:
            return {"agent_output": improved}

    # === الرد كويس — يمرّ بدون تعديل ===
    return {}


async def _improve_response(output: str, agent: str) -> str | None:
    """محاولة تحسين رد ضعيف — LLM call واحد فقط."""
    import asyncio
    try:
        llm = get_llm(temperature=0.5)
        prompt = (
            f"أنت مساعد سياحة مصرية. الرد التالي ضعيف أو قصير.\n"
            f"حسّنه وأعد نسخة أفضل وأغنى بالمعلومات.\n"
            f"لا تشرح التحسين — أعد الرد المحسن فقط.\n\n"
            f"الرد الأصلي: {output}\n\n"
            f"الرد المحسن:"
        )
        result = await asyncio.wait_for(llm.ainvoke(prompt), timeout=15.0)
        content = result.content
        improved = content.strip() if isinstance(content, str) else str(content).strip()

        # تحقق أن التحسين فعلاً أحسن
        if improved and len(improved) > 20:
            logger.info(f"🔍 Reflection: تم تحسين رد {agent}")
            return improved
    except Exception as e:
        logger.warning(f"Reflection error: {e}")

    return None


# ============================================================
# عقدة بناء الرد النهائي مع Rich Cards
# ============================================================

async def build_response_node(state: AgentState) -> dict:
    """بناء الرد النهائي مع Rich Cards والإجراءات السريعة.

    ✅ محسّن: يستخدم current_viewed_items لبناء كروت منتجات حقيقية مع product_id
    """
    output = state.get("agent_output", "")
    agent = state.get("current_agent", "")
    sentiment = state.get("sentiment", "neutral")
    suggestions = state.get("proactive_suggestions", [])

    # === Rich Cards حسب الوكيل ===
    # === Rich Cards حسب الوكيل ===
    # لو الوكيل (مثل commerce_agent أو explorer_agent) رجّع كروت جاهزة → استخدمها وحميها من الشطب
    existing_cards = state.get("cards", [])
    if existing_cards:
        cards = existing_cards  # كروت حقيقية ومستخرجة من الأدوات
    else:
        cards = _build_rich_cards(agent, output, state)

    # === إجراءات سريعة حسب الوكيل ===
    quick_actions = _get_quick_actions(agent)

    # === إضافة اقتراحات تلقائية ===
    if suggestions:
        for s in suggestions[:2]:
            quick_actions.append({
                "label": f"{s.get('title', '💡 اقتراح')}",
                "message": s.get("message", ""),
            })

    # === تحديث الذاكرة العاملة ===
    try:
        from memory.working_memory import add_message, update_session_metadata
        session_id = state.get("session_id", "default")
        add_message(session_id, AIMessage(content=output, name=agent))
        update_session_metadata(session_id, last_agent=agent)
    except Exception:
        pass

    return {
        "final_response": output,
        "quick_actions": quick_actions,
        "cards": cards,
        "sources": state.get("sources", []),
    }


# ============================================================
# عقدة تعلم التفضيلات (بعد بناء الرد)
# ============================================================

async def learn_preferences_node(state: AgentState) -> dict:
    """تعلم تفضيلات المستخدم من المحادثة الحالية.
    
    ✅ HIGH-08: Only runs every 5th message to reduce LLM calls.
    """
    user_id = state.get("user_id", "")
    if not user_id:
        return {}

    # HIGH-08: Only learn every 30th message to reduce LLM overhead
    try:
        from memory.working_memory import get_session
        session = get_session(state.get("session_id", "default"))
        msg_count = session.get("message_count", 0)
        if msg_count % 30 != 0:
            return {}
    except Exception:
        return {}

    messages = state.get("messages", [])
    agent_output = state.get("agent_output", "")
    agent = state.get("current_agent", "")

    # نتعلم فقط من محادثات ذات معنى
    if agent in ("assistant_agent",):
        return {}

    user_msg = messages[-1].content if messages else ""
    conversation_text = f"المستخدم: {user_msg}\nالمساعد: {agent_output}"

    try:
        from memory.semantic_memory import load_preferences, learn_from_conversation, save_preferences
        import asyncio

        async def _background_learn():
            try:
                current_prefs = await load_preferences(user_id)
                updated_prefs = await asyncio.wait_for(
                    learn_from_conversation(user_id, conversation_text, current_prefs),
                    timeout=15.0,
                )
                await save_preferences(user_id, updated_prefs)
                logger.info(f"🧠 تم تحديث تفضيلات المستخدم {user_id} (msg #{msg_count})")
            except Exception as e:
                logger.warning(f"خطأ في تعلم التفضيلات في الخلفية: {e}")

        await _background_learn()
    except Exception as e:
        logger.warning(f"خطأ في إطلاق تعلم التفضيلات: {e}")

    return {}


# ============================================================
# بناء Rich Cards — محسّن مع current_viewed_items
# ============================================================

from typing import Any

def _build_rich_cards(agent: str, output: str, state: Any = None) -> list[dict]:
    """بناء Rich Cards حسب نوع الوكيل والمحتوى.

    ✅ محسّن: product_agent يستخدم current_viewed_items
    """
    cards = []
    output_lower = output.lower() if output else ""
    state = state or {}

    # === 1. Agent-Specific Cards (إذا لم يكن هناك كروت مستخرجة من الأدوات) ===
    viewed_items = state.get("current_viewed_items", [])
    if agent == "commerce_agent" and not viewed_items:
        if "سلة" in output_lower or "cart" in output_lower:
            cards.append({
                "type": "cart_summary",
                "data": {
                    "title": "🛒 سلة المشتريات",
                    "description": "تم تحديث السلة",
                    "icon": "shopping_cart",
                },
                "actions": [
                    {"label": "💳 إتمام الشراء", "action": "navigate", "params": {"target": "checkout"}},
                    {"label": "🛍️ تسوق أكتر", "action": "send_message", "params": {"message": "عايز أتسوق أكتر"}},
                ],
            })
        else:
            cards.append({
                "type": "product",
                "data": {
                    "title": "🛍️ منتجات مقترحة",
                    "description": "تصفح المنتجات المصرية الأصيلة",
                    "icon": "shopping_bag",
                },
                "actions": [
                    {"label": "تصفح المنتجات", "action": "navigate", "params": {"screen": "products"}},
                    {"label": "عروض اليوم", "action": "send_message", "params": {"message": "عروض اليوم"}},
                ],
            })

    elif agent == "explorer_agent":
        artifact_keywords = {
            "توت عنخ": {"name": "توت عنخ آمون", "area": "المتحف المصري الكبير", "icon": "👑"},
            "رمسيس": {"name": "رمسيس الثاني", "area": "أبو سمبل، أسوان", "icon": "🏛️"},
            "كليوباترا": {"name": "كليوباترا السابعة", "area": "الإسكندرية", "icon": "👸"},
            "أهرام": {"name": "أهرامات الجيزة", "area": "الجيزة", "icon": "🔺"},
            "أبو الهول": {"name": "أبو الهول", "area": "الجيزة", "icon": "🦁"},
            "حتشبسوت": {"name": "حتشبسوت", "area": "الأقصر", "icon": "👑"},
            "خان الخليلي": {"name": "خان الخليلي", "area": "القاهرة القديمة", "icon": "🏪"},
            "أقصر": {"name": "الأقصر", "area": "صعيد مصر", "icon": "🏛️"},
            "أسوان": {"name": "أسوان", "area": "جنوب مصر", "icon": "⛵"},
        }
        for keyword, info in artifact_keywords.items():
            if keyword in output_lower:
                is_artifact = "أهرام" in keyword or "رمسيس" in keyword or "توت" in keyword or "أبو الهول" in keyword or "حتشبسوت" in keyword or "كليوباترا" in keyword
                cards.insert(0, {
                    "type": "artifact" if is_artifact else "bazaar",
                    "data": {
                        "title": f"{info['icon']} {info['name']}",
                        "location": info["area"],
                        "area": info["area"],
                        "description": f"استكشف أكثر حول {info['name']} واكتشف أفضل المستنسخات والهدايا التذكارية المرتبطة بها.",
                    },
                    "actions": [
                        {"label": "📍 الخريطة", "action": "open_map", "params": {"query": f"{info['name']} in {info['area']}"}},
                    ],
                })
                break


    return cards


def _get_quick_actions(agent: str) -> list[dict]:
    """إجراءات سريعة حسب الوكيل المستخدم. كحد أقصى 4 إجراءات."""
    actions_map = {
        "commerce_agent": [
            {"label": "🛒 عرض السلة", "message": "عرض السلة"},
            {"label": "🎟️ كوبون خصم", "message": "في كوبونات خصم؟"},
            {"label": "💳 إتمام الشراء", "message": "عايز أكمل عملية الشراء"},
            {"label": "⭐ منتجات مميزة", "message": "أعرض المنتجات المميزة"},
        ],
        "explorer_agent": [
            {"label": "📸 أماكن سياحية", "message": "اقترح أماكن سياحية"},
            {"label": "🏪 بازارات قريبة", "message": "فين أقرب بازار؟"},
            {"label": "🛍️ هدايا من هنا", "message": "منتجات مميزة من المكان ده"},
            {"label": "🏺 أشهر الآثار", "message": "أشهر الآثار المصرية"},
        ],
        "assistant_agent": [
            {"label": "📜 تاريخ", "message": "احكيلي عن الفراعنة"},
            {"label": "🛍️ تسوق", "message": "عايز أتسوق"},
            {"label": "🗺️ بازارات", "message": "فين أقرب بازار؟"},
        ],
        "personalization_agent": [
            {"label": "🛍️ اقتراحات لي", "message": "اقترح حاجات تناسبني"},
            {"label": "📜 اهتماماتي", "message": "عايز حاجات حسب اهتماماتي"},
            {"label": "⭐ عروض اليوم", "message": "عروض اليوم"},
        ],
    }

    return actions_map.get(agent, [
        {"label": "🛍️ تسوق", "message": "عايز أتسوق"},
        {"label": "📜 تاريخ", "message": "احكيلي عن الفراعنة"},
        {"label": "🗺️ بازارات", "message": "فين أقرب بازار؟"},
    ])[:4]
