"""
🤖 Admin Assistant Agent — ReAct Agent for Admin Panel.
Features: Conversation memory, fallback chain, real-data promotions,
          11 tools, smart quick_actions, period comparison.
"""
from datetime import datetime
import json
import logging

from langchain_core.tools import tool
from langgraph.prebuilt import create_react_agent
from langchain_core.messages import HumanMessage, AIMessage

from core.llm_service import get_llm, invoke_with_fallback
from core.analytics_service import compute_platform_analytics, get_platform_health
from core.json_utils import parse_json_response
from core.aws_memory import save_session_data, get_session_data
from core.config import LLM_TIMEOUT
from core.db_service import (
    get_revenue_summary, get_top_products, get_category_stats,
    get_daily_orders, get_reviews_summary,
    get_all_bazaars, get_all_products,
    generate_and_execute_sql,
)

logger = logging.getLogger(__name__)

# Max conversation turns to keep in memory
MAX_MEMORY_TURNS = 10


# ============================================================
# Tools — Original (5)
# ============================================================

@tool
async def get_analytics_summary(period: str = "month") -> str:
    """Get platform performance summary (revenue, orders, active bazaars). Use ONLY when asked about overall numbers or dashboard metrics."""
    data = await compute_platform_analytics(period)
    return json.dumps(data.get("key_metrics", {}), ensure_ascii=False)


@tool
async def get_bazaar_rankings(period: str = "month") -> str:
    """Get top performing bazaars rankings with revenue and order count."""
    data = await compute_platform_analytics(period)
    return json.dumps(data.get("bazaar_rankings", []), ensure_ascii=False)


@tool
async def get_system_health() -> str:
    """Check platform system health, active products, and bazaars."""
    data = await get_platform_health()
    return json.dumps(data, ensure_ascii=False)


@tool
async def get_inactive_bazaars() -> str:
    """Get list of approved bazaars with zero sales."""
    data = await compute_platform_analytics("month")
    inactive = data.get("inactive_bazaars", [])
    return json.dumps(inactive[:10], ensure_ascii=False) if inactive else "لا توجد بازارات غير نشطة"


@tool
async def get_order_status_distribution() -> str:
    """Get breakdown of order statuses (delivered, cancelled, pending, etc.)."""
    data = await compute_platform_analytics("month")
    return json.dumps(data.get("status_distribution", {}), ensure_ascii=False)


# ============================================================
# Tools — NEW (6) — Direct SQL-powered, no analytics overhead
# ============================================================

@tool
async def get_revenue_details(days: int = 30) -> str:
    """Get detailed revenue breakdown directly from database: total, average, min, max order values, and status counts.
    Use when asked about revenue, earnings, income, or money.
    'days' parameter: 7=week, 30=month, 90=quarter, 365=year."""
    data = await get_revenue_summary(days)
    return json.dumps(data, ensure_ascii=False, default=str)


@tool
async def get_top_selling_products(limit: int = 10) -> str:
    """Get the top selling products ranked by revenue.
    Use when asked about best sellers, popular products, or top items.
    Returns product name, category, units sold, and revenue."""
    data = await get_top_products(limit=limit, days=30)
    return json.dumps(data, ensure_ascii=False, default=str)


@tool
async def get_category_breakdown() -> str:
    """Get statistics for each product category: count, average price, active products.
    Use when asked about categories, product distribution, or pricing analysis."""
    data = await get_category_stats()
    return json.dumps(data, ensure_ascii=False, default=str)


@tool
async def get_daily_trend(days: int = 30) -> str:
    """Get daily order and revenue trends.
    Use when asked about trends, patterns, daily performance, or charts.
    Returns date, order_count, daily_revenue, delivered, cancelled per day."""
    data = await get_daily_orders(days)
    return json.dumps(data, ensure_ascii=False, default=str)


@tool
async def get_reviews_overview() -> str:
    """Get platform-wide customer review statistics: average rating, positive/negative counts.
    Use when asked about customer satisfaction, ratings, or feedback."""
    data = await get_reviews_summary()
    return json.dumps(data, ensure_ascii=False, default=str)


@tool
async def compare_periods(current_days: int = 30, previous_days: int = 30) -> str:
    """Compare two time periods side by side.
    Use when asked to compare this week vs last week, this month vs last month, etc.
    Example: compare_periods(7, 7) compares last 7 days vs 7 days before that.
    Returns both period summaries with growth percentage."""
    current = await get_revenue_summary(current_days)
    previous = await get_revenue_summary(current_days + previous_days)

    # Calculate the previous-only values
    prev_revenue = float(previous.get("total_revenue", 0)) - float(current.get("total_revenue", 0))
    prev_orders = int(previous.get("total_orders", 0)) - int(current.get("total_orders", 0))
    curr_revenue = float(current.get("total_revenue", 0))
    curr_orders = int(current.get("total_orders", 0))

    revenue_growth = round(((curr_revenue - prev_revenue) / prev_revenue * 100), 1) if prev_revenue > 0 else 0
    orders_growth = round(((curr_orders - prev_orders) / prev_orders * 100), 1) if prev_orders > 0 else 0

    return json.dumps({
        "current_period": {
            "days": current_days,
            "revenue": curr_revenue,
            "orders": curr_orders,
            "avg_order": round(curr_revenue / curr_orders, 2) if curr_orders else 0,
        },
        "previous_period": {
            "days": previous_days,
            "revenue": prev_revenue,
            "orders": prev_orders,
            "avg_order": round(prev_revenue / prev_orders, 2) if prev_orders else 0,
        },
        "growth": {
            "revenue_pct": revenue_growth,
            "orders_pct": orders_growth,
            "direction": "up" if revenue_growth > 0 else "down" if revenue_growth < 0 else "flat",
        },
    }, ensure_ascii=False, default=str)


@tool
async def query_database(question: str) -> str:
    """Execute a dynamic SQL query against the database based on a natural language question.
    This is the MOST POWERFUL tool — use it when NO other tool can answer the question.
    Examples:
    - 'أعلى 5 بازارات من حيث عدد المنتجات'
    - 'الطلبات التي تجاوزت 500 جنيه'
    - 'المنتجات التي ليس لها طلبات'
    - 'عدد المستخدمين المسجلين كل شهر'
    - 'أي بازار فيه أكثر تقييمات سلبية'
    This tool is READ-ONLY — it cannot modify any data.
    DO NOT use this for questions that other tools can answer (revenue, top products, etc.)."""
    result = await generate_and_execute_sql(question)

    if result.get("success"):
        data = result.get("data", [])
        sql = result.get("sql", "")
        row_count = result.get("row_count", 0)
        output = f"✅ تم تنفيذ الاستعلام بنجاح ({row_count} نتيجة)\n"
        output += f"SQL: {sql}\n\n"
        output += json.dumps(data, ensure_ascii=False, default=str)
        return output
    else:
        error = result.get("error", "خطأ غير معروف")
        return f"❌ فشل الاستعلام: {error}"


ADMIN_TOOLS = [
    # Core analytics
    get_analytics_summary,
    get_bazaar_rankings,
    get_system_health,
    get_inactive_bazaars,
    get_order_status_distribution,
    # New SQL-powered tools
    get_revenue_details,
    get_top_selling_products,
    get_category_breakdown,
    get_daily_trend,
    get_reviews_overview,
    compare_periods,
    # Dynamic Text-to-SQL (the ultimate tool)
    query_database,
]

# ============================================================
# Prompts — Upgraded with tool routing guidance
# ============================================================

ADMIN_SYSTEM_MSG = """أنت المساعد الإداري الذكي لمنصة السياحة المصرية.
مهمتك الرد على أسئلة مدير المنصة بدقة عالية جداً باستخدام بيانات حقيقية.

## قواعد صارمة:
1. **استخدم الأدوات دائماً** قبل أي إجابة تتعلق بأرقام أو إحصائيات. لا تخترع أي رقم.
2. إذا لم تجد بيانات كافية، قُل "لا تتوفر بيانات حالياً" ولا تخمن.
3. أجب بالعربية الفصحى المهنية بتنسيق Markdown احترافي (عناوين، جداول، نقاط).
4. اختم كل إجابة بـ **💡 توصيات:** مع 2-3 نقاط عملية مبنية على البيانات.
5. لا تُرجع JSON أبداً — أجب بلغة طبيعية واضحة.
6. استخدم سياق المحادثة السابقة عند المتابعة.

## دليل اختيار الأداة المناسبة:
| السؤال | الأداة |
|---|---|
| إيرادات، مبيعات، أرباح | `get_revenue_details` |
| أفضل منتجات، الأكثر مبيعاً | `get_top_selling_products` |
| فئات المنتجات، توزيع الأسعار | `get_category_breakdown` |
| ترند يومي، تحليل الأيام | `get_daily_trend` |
| تقييمات، رأي العملاء | `get_reviews_overview` |
| مقارنة فترات (شهر بشهر) | `compare_periods` |
| ترتيب بازارات، أداء المتاجر | `get_bazaar_rankings` |
| بازارات غير نشطة | `get_inactive_bazaars` |
| صحة المنصة، حالة النظام | `get_system_health` |
| حالات الطلبات | `get_order_status_distribution` |
| ملخص شامل للمنصة | `get_analytics_summary` |
| **أي سؤال آخر لا تغطيه الأدوات أعلاه** | `query_database` |

## أداة query_database (استعلام ديناميكي):
هذه الأداة تمكنك من الإجابة على أي سؤال بكتابة استعلام SQL مباشر على قاعدة البيانات.
استخدمها فقط عندما لا تستطيع أي أداة أخرى الإجابة.
أمثلة: عدد المنتجات في بازار معين، الطلبات بمبلغ أعلى من X، المستخدمين الجدد هذا الأسبوع.
الأداة للقراءة فقط ولا يمكنها تعديل أي بيانات.
"""


# ============================================================
# Smart Quick Actions Generator
# ============================================================

def _generate_smart_actions(question: str, answer: str) -> list[str]:
    """Generate contextual quick actions based on the conversation."""
    q_lower = question.lower()

    if any(w in q_lower for w in ["إيراد", "revenue", "مبيعات", "أرباح"]):
        return ["📊 مقارنة بالشهر السابق", "🏪 أفضل البازارات", "📈 ترند يومي"]
    elif any(w in q_lower for w in ["بازار", "متجر", "ترتيب"]):
        return ["⚠️ البازارات غير النشطة", "📊 إيرادات المنصة", "💡 اقتراحات تسويقية"]
    elif any(w in q_lower for w in ["منتج", "product", "فئ", "category"]):
        return ["🔝 الأكثر مبيعاً", "📊 توزيع الفئات", "💰 تحليل الأسعار"]
    elif any(w in q_lower for w in ["صح", "health", "حال", "نظام"]):
        return ["📊 تقرير شامل", "⚠️ مشاكل تحتاج انتباه", "🏪 حالة البازارات"]
    elif any(w in q_lower for w in ["تقييم", "review", "رأي", "عمل"]):
        return ["📊 إحصائيات المنصة", "🏪 أفضل البازارات", "🔍 صحة المنصة"]
    elif any(w in q_lower for w in ["قارن", "مقارن", "compare", "سابق", "فات"]):
        return ["📈 ترند الأسبوع", "💰 تفاصيل الإيرادات", "🏪 ترتيب البازارات"]

    # Default actions
    return ["📊 تقرير أداء المنصة", "🏪 ترتيب البازارات", "🔍 صحة النظام"]


# ============================================================
# Conversation Memory Helpers
# ============================================================

def _load_conversation_history(session_id: str) -> list:
    """Load conversation history from DynamoDB."""
    if not session_id or session_id == "admin_default":
        return []
    try:
        data = get_session_data(session_id)
        if data and "messages" in data:
            messages = []
            for m in data["messages"][-MAX_MEMORY_TURNS:]:
                if m.get("role") == "human":
                    messages.append(HumanMessage(content=m["content"]))
                elif m.get("role") == "ai":
                    messages.append(AIMessage(content=m["content"]))
            return messages
    except Exception as e:
        logger.warning(f"Failed to load conversation history: {e}")
    return []


def _save_conversation_turn(session_id: str, question: str, answer: str):
    """Save a conversation turn to DynamoDB."""
    if not session_id or session_id == "admin_default":
        return
    try:
        data = get_session_data(session_id) or {"messages": []}
        data["messages"].append({"role": "human", "content": question})
        data["messages"].append({"role": "ai", "content": answer})
        # Keep only the last MAX_MEMORY_TURNS messages
        data["messages"] = data["messages"][-(MAX_MEMORY_TURNS * 2):]
        data["updated_at"] = datetime.now().isoformat()
        save_session_data(session_id, data)
    except Exception as e:
        logger.warning(f"Failed to save conversation turn: {e}")


# ============================================================
# Shared Agent Factory
# ============================================================

def _create_admin_agent():
    """Create a ReAct agent instance — single source of truth."""
    llm = get_llm(temperature=0.3, app_id="admin")
    return create_react_agent(llm, ADMIN_TOOLS, state_modifier=ADMIN_SYSTEM_MSG)


# ============================================================
# Agent Execution — with Memory + Smart Actions
# ============================================================

async def admin_chat(question: str, context: str = "", session_id: str = "") -> dict:
    """Execute LangGraph ReAct agent for the admin chat — with conversation memory."""
    agent = _create_admin_agent()

    # Build message list with history
    history = _load_conversation_history(session_id)
    prompt_str = f"سياق إضافي: {context}\n\nسؤال المدير: {question}" if context else question

    messages = history + [HumanMessage(content=prompt_str)]

    try:
        import asyncio
        response = await asyncio.wait_for(
            agent.ainvoke({"messages": messages}),
            timeout=LLM_TIMEOUT,
        )
        final_text = response["messages"][-1].content

        # Save to memory
        _save_conversation_turn(session_id, question, final_text)

        parsed = parse_json_response(final_text)
        if parsed and "text" in parsed:
            parsed["quick_actions"] = parsed.get("quick_actions") or _generate_smart_actions(question, final_text)
            return parsed

        return {
            "text": final_text,
            "quick_actions": _generate_smart_actions(question, final_text),
        }
    except asyncio.TimeoutError:
        logger.error("Admin chat timed out")
        return {
            "text": "عذراً، استغرق الطلب وقتاً طويلاً. برجاء المحاولة مرة أخرى.",
            "quick_actions": [],
        }
    except Exception as e:
        logger.error(f"ReAct Agent Error: {e}")
        return {
            "text": "عذراً، حدثت مشكلة أثناء معالجة طلبك.",
            "quick_actions": [],
        }


# ============================================================
# Direct Generators — with invoke_with_fallback
# ============================================================

async def generate_business_report(period: str = "month", focus: str = None) -> dict:
    """Generate comprehensive BI report with fallback chain."""
    analytics = await compute_platform_analytics(period)

    focus_instruction = ""
    if focus:
        focus_map = {
            "revenue": "ركز على تحليل وتوجهات الإيرادات",
            "bazaars": "ركز على أداء ونشاط البازارات وتوزيع التقييمات",
            "products": "ركز على المنتجات النشطة والفئات الأكثر طلباً",
            "customers": "ركز على توزيع العملاء وسلوك الحجوزات",
        }
        focus_instruction = focus_map.get(focus, "")

    safe_data = {
        "metrics": analytics.get("key_metrics"),
        "bazaars": analytics.get("bazaar_rankings", [])[:5]
    }

    prompt = f"""أنت محلل أعمال محترف في منصة سياحة مصرية.

بيانات الأداء للفترة ({period}):
{json.dumps(safe_data, ensure_ascii=False, default=str)}

المطلوب: تقرير ذكي شامل {focus_instruction}

اكتب التقرير بصيغة JSON:
{{
    "executive_summary": "ملخص تنفيذي (3-4 جمل) بأهم النتائج والاتجاهات",
    "insights": [
        {{"type": "success|warning|tip|danger", "icon": "📈", "title": "عنوان", "text": "تفصيل"}}
    ],
    "trends": [
        {{"metric": "المقياس", "direction": "up|down|flat", "value": "القيمة", "analysis": "التحليل"}}
    ],
    "recommendations": [
        "توصية عملية 1",
        "توصية عملية 2"
    ],
    "anomalies": []
}}"""

    result_text = await invoke_with_fallback(prompt, agent="admin", temperature=0.5, app_id="admin")
    parsed = parse_json_response(result_text)
    if not parsed:
        parsed = {
            "executive_summary": "تعذر توليد التقرير التلقائي.",
            "insights": [], "trends": [], "recommendations": [], "anomalies": []
        }

    parsed["period"] = period
    parsed["key_metrics"] = analytics.get("key_metrics", {})
    parsed["bazaar_rankings"] = analytics.get("bazaar_rankings", [])
    parsed["charts_data"] = analytics.get("charts_data", {})

    return parsed


async def get_platform_insights() -> dict:
    """Get fast snapshot insights of the platform — with fallback."""
    try:
        analytics = await compute_platform_analytics("week")
        health = await get_platform_health()
    except Exception as e:
        logger.error(f"Error getting platform insights data: {e}")
        return {
            "health_score": 0, "insights": [],
            "alerts": [{"type": "danger", "icon": "🔴", "title": "خطأ", "text": str(e)}],
            "quick_stats": {}, "bazaar_tiers": {},
        }

    safe_data = {
        "metrics": analytics.get("key_metrics"),
        "health": health
    }

    prompt = f"""حلل بيانات المنصة واستخرج insights سريعة بصيغة JSON:
{json.dumps(safe_data, ensure_ascii=False)}

المخرجات المطلوبة JSON:
{{"insights": [{{"type": "tip", "title": "...", "text": "...", "icon": "💡"}}], "alerts": [], "bazaar_tiers": {{"gold": 0, "silver": 0, "bronze": 0}}}}"""

    result_text = await invoke_with_fallback(prompt, agent="admin", temperature=0.4, app_id="admin")
    parsed = parse_json_response(result_text)
    if not parsed:
        parsed = {"insights": [], "alerts": [], "bazaar_tiers": {}}

    parsed["health_score"] = health.get("health_score", 0)
    parsed["quick_stats"] = analytics.get("key_metrics", {})

    return parsed


async def generate_admin_message(message_type: str, bazaar_name: str, context: str = "", custom_notes: str = "") -> dict:
    """Generate communication message for bazaars — with fallback."""
    prompt = f"""أنت مسؤول تواصل محترف في منصة سياحة مصرية.
النوع: {message_type}
البازار الموجه له: {bazaar_name}
ملاحظات إضافية: {custom_notes}
السياق: {context}

اكتب الخطاب بصيغة JSON:
{{"subject": "عنوان احترافي", "body": "نص الخطاب", "tone": "professional", "variations": [{{"body": "نسخة أخرى بصيغة أقصر"}}]}}"""

    result_text = await invoke_with_fallback(prompt, agent="admin", temperature=0.6, app_id="admin")
    parsed = parse_json_response(result_text)
    return parsed if parsed else {"subject": "إشعار إداري", "body": "حدث خطأ في توليد الرسالة.", "tone": "professional", "variations": []}


async def suggest_promotions() -> dict:
    """Generate promotional suggestions — fed with REAL platform data."""
    # Fetch real analytics to ground the AI
    try:
        analytics = await compute_platform_analytics("month")
        health = await get_platform_health()
    except Exception as e:
        logger.warning(f"Failed to fetch data for promotions: {e}")
        analytics = {"key_metrics": {}, "bazaar_rankings": [], "charts_data": {}}
        health = {}

    platform_data = {
        "metrics": analytics.get("key_metrics", {}),
        "top_bazaars": [b.get("name") for b in analytics.get("bazaar_rankings", [])[:3]],
        "inactive_count": len(analytics.get("inactive_bazaars", [])),
        "categories": [c.get("name") for c in analytics.get("charts_data", {}).get("categories_pie", [])],
    }

    prompt = f"""أنت خبير تسويق في منصة سياحة مصرية.
التاريخ: {datetime.now().strftime("%Y-%m-%d")}

بيانات المنصة الحقيقية:
{json.dumps(platform_data, ensure_ascii=False, default=str)}

بناءً على هذه البيانات الحقيقية، اقترح عروض ترويجية ذكية بصيغة JSON:
{{"suggestions": [{{"type": "discount|bundle|coupon", "title": "اسم العرض", "description": "الوصف مع ربطه بالبيانات", "priority": "high|medium|low", "estimated_impact": "مثال: زيادة 10% بالمبيعات"}}], "seasonal_events": [{{"name": "...", "date": "..."}}], "market_analysis": "تحليل مختصر مبني على البيانات"}}"""

    result_text = await invoke_with_fallback(prompt, agent="admin", temperature=0.7, app_id="admin")
    parsed = parse_json_response(result_text)
    return parsed if parsed else {"suggestions": [], "seasonal_events": [], "market_analysis": ""}
