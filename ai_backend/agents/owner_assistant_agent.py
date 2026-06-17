"""
🧠 Owner Assistant Agent — المستشار الذكي لأصحاب البازارات
يساعد في: توليد أوصاف، اقتراح أسعار، ردود ذكية، محتوى تسويقي، ملخصات يومية
✅ UPGRADED: Timeout protection, retry/fallback, app_id fix, logging
"""
import json
import asyncio
import logging
from datetime import datetime
from services.gemini_service import get_llm, get_fast_llm

logger = logging.getLogger(__name__)


# ============================================================
# System Prompts
# ============================================================

PRODUCT_DESCRIPTION_PROMPT = """أنت كاتب محتوى محترف متخصص في المنتجات المصرية التراثية والهدايا التذكارية.

مهمتك: كتابة وصف منتج احترافي يجذب السياح للشراء.

معلومات المنتج:
- الاسم: {product_name}
- الفئة: {category}
- المادة: {material}
- تفاصيل إضافية: {extra_details}

معلومات السوق:
{market_context}

أكتب الرد بصيغة JSON فقط:
{{
    "description_ar": "وصف عربي احترافي (3-5 جمل) يبرز القيمة التراثية والجمالية",
    "description_en": "English translation of the Arabic description",
    "title_suggestions_ar": ["عنوان 1", "عنوان 2", "عنوان 3"],
    "title_suggestions_en": ["Title 1", "Title 2", "Title 3"],
    "category_suggestion": "التصنيف المقترح",
    "category_confidence": 0.95,
    "seo_keywords": ["keyword1", "keyword2", "keyword3", "keyword4", "keyword5"],
    "marketing_highlights": ["ميزة 1", "ميزة 2", "ميزة 3"]
}}

اجعل الوصف:
- يتحدث عن القصة وراء المنتج (الحرفة، التاريخ، الرمزية)
- يبرز ما يميزه عن البدائل
- يخاطب السياح والمهتمين بالثقافة المصرية
- مختصر ومؤثر — ليس طويل ممل
"""

PRICE_SUGGESTION_PROMPT = """أنت خبير تسعير متخصص في المنتجات المصرية التراثية.

المنتج: {product_name}
الفئة: {category}
المادة: {material}

بيانات السوق الحالية:
{market_data}

أعطني اقتراح سعر بصيغة JSON:
{{
    "suggested_price": السعر_المقترح,
    "price_range_min": الحد_الأدنى,
    "price_range_max": الحد_الأقصى,
    "market_average": المتوسط,
    "reasoning": "شرح مختصر لسبب هذا السعر",
    "confidence": 0.85
}}

ضع في اعتبارك:
- متوسط السوق في المنصة
- نوع المادة وجودتها
- الطلب على هذه الفئة
- هامش ربح معقول (20-40%)
"""

REPLY_SUGGESTIONS_PROMPT = """أنت مساعد تواصل ذكي لأصحاب البازارات المصرية.

رسالة العميل: "{customer_message}"
اسم العميل: {customer_name}
سياق إضافي: {context}

حلل الرسالة وأعطني ردود مقترحة بصيغة JSON:
{{
    "detected_intent": "نوع السؤال (price_inquiry / availability / shipping / complaint / general)",
    "customer_sentiment": "positive / neutral / negative",
    "language_detected": "ar / en",
    "priority": "high / normal / low",
    "replies": [
        {{"text": "الرد المقترح 1 — مباشر وودي", "tone": "friendly", "confidence": 0.9}},
        {{"text": "الرد المقترح 2 — رسمي ومهني", "tone": "professional", "confidence": 0.85}},
        {{"text": "الرد المقترح 3 — شخصي ومرح", "tone": "casual", "confidence": 0.8}}
    ]
}}

قواعد:
- الردود تكون بنفس لغة العميل
- إذا العميل زعلان → رد يهدّيه ويحل مشكلته
- إذا سأل عن سعر/توفر → رد يشجعه على الشراء
- اجعل الردود مختصرة ومباشرة (جملتين-3 جمل)
- استخدم لهجة مصرية ودية مع إيموجي معتدل
"""

CONTENT_GENERATION_PROMPT = """أنت كاتب محتوى تسويقي محترف للمنتجات المصرية.

نوع المحتوى: {content_type}
المنتج: {product_name}
البازار: {bazaar_name}
تفاصيل العرض: {offer_details}
الجمهور المستهدف: {target_audience}
اللغة: {language}

اكتب المحتوى بصيغة JSON:
{{
    "content": "المحتوى الرئيسي",
    "hashtags": ["#هاشتاق1", "#هاشتاق2"],
    "call_to_action": "جملة تشجع على الإجراء",
    "variations": ["نسخة بديلة 1", "نسخة بديلة 2"]
}}

أنواع المحتوى:
- ad: إعلان قصير جذاب
- social: بوست لسوشيال ميديا (إنستجرام/فيسبوك)
- seo: نص محسّن لمحركات البحث
- offer: إعلان عرض/خصم
"""

DAILY_DIGEST_PROMPT = """أنت مستشار أعمال ذكي لأصحاب البازارات المصرية.

بيانات الأداء:
{analytics_data}

تاريخ اليوم: {today}

اكتب ملخص يومي ذكي بصيغة JSON:
{{
    "greeting": "تحية صباحية مخصصة حسب الأداء",
    "yesterday_summary": {{
        "revenue": المبلغ,
        "orders": العدد,
        "top_product": "اسم أفضل منتج",
        "highlight": "أبرز حدث أمس"
    }},
    "today_goals": [
        "هدف 1 عملي ومحدد",
        "هدف 2",
        "هدف 3"
    ],
    "alerts": [
        {{"type": "warning", "icon": "⚠️", "title": "تنبيه", "text": "نص التنبيه"}},
        {{"type": "tip", "icon": "💡", "title": "نصيحة", "text": "نص النصيحة"}}
    ],
    "tip_of_day": "نصيحة عملية مبنية على البيانات",
    "performance_score": درجة_من_100
}}

كن مختصراً وعملياً. التحية بالعربية المصرية.
ركز على أرقام حقيقية من البيانات (لا تخترع أرقام).
"""

PRODUCT_SUGGESTIONS_PROMPT = """أنت مستشار منتجات خبير في السوق المصري السياحي.

منتجات البازار الحالية:
{current_products}

بيانات السوق:
{market_data}

تحليل المبيعات:
{sales_data}

اقترح منتجات جديدة بصيغة JSON:
{{
    "trending_categories": [
        {{"category": "اسم الفئة", "demand": "high/medium", "reason": "السبب"}}
    ],
    "gap_analysis": [
        {{"gap": "وصف الفجوة", "opportunity": "الفرصة", "priority": "high/medium/low"}}
    ],
    "suggestions": [
        {{"name": "اسم المنتج المقترح", "category": "الفئة", "price_range": "100-200", "reason": "لماذا هذا المنتج", "potential": "high/medium"}}
    ],
    "market_trends": ["اتجاه 1", "اتجاه 2", "اتجاه 3"]
}}
"""

TRANSLATE_PROMPT = """Translate the following text from {source_lang} to {target_lang}.
Keep the tone, style, and meaning as close to the original as possible.
If the text contains Egyptian Arabic, translate naturally (not literally).

Text: {text}

Return ONLY the translated text, nothing else."""


# ============================================================
# Agent Functions
# ============================================================

async def generate_product_description(
    product_name: str,
    category: str = "",
    material: str = "",
    extra_details: str = "",
    market_context: str = "",
) -> dict:
    """توليد وصف منتج احترافي."""
    llm = get_llm(temperature=0.7, app_id="owner")
    prompt = PRODUCT_DESCRIPTION_PROMPT.format(
        product_name=product_name,
        category=category or "غير محدد",
        material=material or "غير محدد",
        extra_details=extra_details or "لا يوجد",
        market_context=market_context or "لا تتوفر بيانات سوق",
    )

    result = await _safe_invoke(llm, prompt, timeout=30.0, label="description")
    if result is None:
        return {
            "description_ar": f"منتج مصري أصيل — {product_name}",
            "description_en": f"Authentic Egyptian product — {product_name}",
            "title_suggestions_ar": [product_name],
            "title_suggestions_en": [product_name],
            "category_suggestion": category or "أخرى",
            "category_confidence": 0.5,
            "seo_keywords": [],
            "marketing_highlights": [],
        }
    return _parse_json_response(result.content, {
        "description_ar": f"منتج مصري أصيل — {product_name}",
        "description_en": f"Authentic Egyptian product — {product_name}",
        "title_suggestions_ar": [product_name],
        "title_suggestions_en": [product_name],
        "category_suggestion": category or "أخرى",
        "category_confidence": 0.5,
        "seo_keywords": [],
        "marketing_highlights": [],
    })


async def suggest_price(
    product_name: str,
    category: str,
    material: str = "",
    market_data: str = "",
) -> dict:
    """اقتراح سعر تنافسي."""
    llm = get_fast_llm(temperature=0.3, app_id="owner")
    prompt = PRICE_SUGGESTION_PROMPT.format(
        product_name=product_name,
        category=category,
        material=material or "غير محدد",
        market_data=market_data or "لا تتوفر بيانات",
    )

    result = await _safe_invoke(llm, prompt, timeout=20.0, label="price")
    if result is None:
        return {"suggested_price": 0, "price_range_min": 0, "price_range_max": 0, "market_average": 0, "reasoning": "لا تتوفر بيانات كافية", "confidence": 0.0}
    return _parse_json_response(result.content, {
        "suggested_price": 0, "price_range_min": 0, "price_range_max": 0,
        "market_average": 0, "reasoning": "لا تتوفر بيانات كافية", "confidence": 0.0,
    })


async def suggest_replies(
    customer_message: str,
    customer_name: str = "",
    context: str = "",
) -> dict:
    """اقتراح ردود ذكية على رسائل العملاء."""
    llm = get_llm(temperature=0.7, app_id="owner")
    prompt = REPLY_SUGGESTIONS_PROMPT.format(
        customer_message=customer_message,
        customer_name=customer_name or "العميل",
        context=context or "محادثة عامة",
    )

    result = await _safe_invoke(llm, prompt, timeout=30.0, label="replies")
    if result is None:
        return {
            "detected_intent": "general", "customer_sentiment": "neutral",
            "language_detected": "ar", "priority": "normal",
            "replies": [{"text": "شكراً لتواصلك! هنرد عليك في أقرب وقت 😊", "tone": "friendly", "confidence": 0.7}],
        }
    return _parse_json_response(result.content, {
        "detected_intent": "general", "customer_sentiment": "neutral",
        "language_detected": "ar", "priority": "normal",
        "replies": [{"text": "شكراً لتواصلك! هنرد عليك في أقرب وقت 😊", "tone": "friendly", "confidence": 0.7}],
    })


async def generate_content(
    content_type: str,
    product_name: str = "",
    bazaar_name: str = "",
    offer_details: str = "",
    target_audience: str = "tourists",
    language: str = "ar",
) -> dict:
    """توليد محتوى تسويقي."""
    llm = get_llm(temperature=0.8, app_id="owner")
    prompt = CONTENT_GENERATION_PROMPT.format(
        content_type=content_type,
        product_name=product_name or "منتج",
        bazaar_name=bazaar_name or "بازار",
        offer_details=offer_details or "لا يوجد",
        target_audience=target_audience,
        language=language,
    )

    result = await _safe_invoke(llm, prompt, timeout=30.0, label="content")
    if result is None:
        return {"content": "", "hashtags": [], "call_to_action": "", "variations": []}
    return _parse_json_response(result.content, {
        "content": "", "hashtags": [], "call_to_action": "", "variations": [],
    })


async def generate_daily_digest(analytics_data: dict) -> dict:
    """توليد ملخص يومي ذكي."""
    llm = get_llm(temperature=0.6, app_id="owner")
    prompt = DAILY_DIGEST_PROMPT.format(
        analytics_data=json.dumps(analytics_data, ensure_ascii=False, default=str),
        today=datetime.now().strftime("%Y-%m-%d %A"),
    )

    result = await _safe_invoke(llm, prompt, timeout=30.0, label="digest")
    if result is None:
        return {
            "greeting": "صباح الخير! يوم جديد مليان فرص 🌅",
            "yesterday_summary": {}, "today_goals": [], "alerts": [],
            "tip_of_day": "", "performance_score": 50,
        }
    return _parse_json_response(result.content, {
        "greeting": "صباح الخير! يوم جديد مليان فرص 🌅",
        "yesterday_summary": {}, "today_goals": [], "alerts": [],
        "tip_of_day": "", "performance_score": 50,
    })


async def suggest_products(
    current_products: str,
    market_data: str = "",
    sales_data: str = "",
) -> dict:
    """اقتراح منتجات جديدة."""
    llm = get_llm(temperature=0.7, app_id="owner")
    prompt = PRODUCT_SUGGESTIONS_PROMPT.format(
        current_products=current_products,
        market_data=market_data or "لا تتوفر بيانات",
        sales_data=sales_data or "لا تتوفر بيانات",
    )

    result = await _safe_invoke(llm, prompt, timeout=30.0, label="suggestions")
    if result is None:
        return {"trending_categories": [], "gap_analysis": [], "suggestions": [], "market_trends": []}
    return _parse_json_response(result.content, {
        "trending_categories": [], "gap_analysis": [], "suggestions": [], "market_trends": [],
    })


async def translate_text(text: str, source_lang: str = "ar", target_lang: str = "en") -> str:
    """ترجمة نص."""
    llm = get_fast_llm(temperature=0.3, app_id="owner")
    prompt = TRANSLATE_PROMPT.format(
        text=text,
        source_lang="Arabic" if source_lang == "ar" else "English",
        target_lang="English" if target_lang == "en" else "Arabic",
    )

    result = await _safe_invoke(llm, prompt, timeout=15.0, label="translate")
    if result is None:
        return text  # Return original text as fallback
    return result.content.strip()


async def generate_analytics_insights(analytics_data: dict) -> list[dict]:
    """توليد insights ذكية من بيانات التحليلات."""
    llm = get_fast_llm(temperature=0.5, app_id="owner")
    prompt = f"""أنت محلل بيانات ذكي. حلل البيانات التالية واستخرج 3-5 insights مفيدة.

البيانات:
{json.dumps(analytics_data, ensure_ascii=False, default=str)}

أعط الإجابة بصيغة JSON array:
[
    {{"type": "success/warning/tip/danger", "icon": "📈/⚠️/💡/🔴", "title": "عنوان قصير", "text": "شرح مختصر ومفيد"}},
    ...
]

قواعد:
- استخدم الأرقام الحقيقية من البيانات
- كل insight يجب أن يكون actionable (يقدر صاحب البازار يعمل حاجة بيه)
- رتب حسب الأهمية
- اكتب بالعربية المصرية بشكل ودي
"""

    result = await _safe_invoke(llm, prompt, timeout=25.0, label="insights")
    if result is None:
        return [{"type": "tip", "icon": "💡", "title": "نصيحة", "text": "تابع أداء منتجاتك باستمرار"}]
    parsed = _parse_json_response(result.content, [])
    if isinstance(parsed, list):
        return parsed
    return []


# ============================================================
# Utility
# ============================================================

def _parse_json_response(text: str, fallback):
    """Wrapper for shared JSON parser with fallback support."""
    from utils.json_parser import parse_json_response
    parsed = parse_json_response(text)
    if not parsed:
        logger.warning(f"JSON parse failed, using fallback. Raw text[:200]: {text[:200]}")
        return fallback
    return parsed


async def _safe_invoke(llm, prompt: str, timeout: float = 30.0, fallback=None, label: str = "agent"):
    """Invoke LLM with timeout + retry + fallback — production-safe wrapper."""
    for attempt in range(2):
        try:
            result = await asyncio.wait_for(llm.ainvoke(prompt), timeout=timeout)
            return result
        except asyncio.TimeoutError:
            logger.warning(f"[{label}] LLM timeout (attempt {attempt+1}/2)")
        except Exception as e:
            logger.warning(f"[{label}] LLM error (attempt {attempt+1}/2): {e}")
            if attempt == 0:
                await asyncio.sleep(1)
    logger.error(f"[{label}] All LLM attempts failed, using fallback")
    return None


# ============================================================
# NEW: Competitor Analysis
# ============================================================

COMPETITOR_ANALYSIS_PROMPT = """أنت محلل أسواق متخصص في المنتجات المصرية التراثية.

بيانات بازار المالك:
{owner_data}

بيانات المنافسين في نفس الفئة:
{competitors_data}

حلل الوضع التنافسي وأعطني النتائج بصيغة JSON:
{{
    "market_position": "leader / competitive / needs_improvement",
    "price_comparison": {{
        "owner_avg": 0,
        "market_avg": 0,
        "position": "أقل من السوق / متوسط / أعلى من السوق",
        "recommendation": "نصيحة تسعيرية"
    }},
    "strengths": ["نقطة قوة 1", "نقطة قوة 2"],
    "weaknesses": ["نقطة ضعف 1", "نقطة ضعف 2"],
    "opportunities": ["فرصة 1", "فرصة 2"],
    "action_items": [
        {{"priority": "high", "action": "إجراء عاجل", "expected_impact": "التأثير المتوقع"}},
        {{"priority": "medium", "action": "إجراء متوسط", "expected_impact": "التأثير"}}
    ]
}}

ركز على نصائح عملية يقدر صاحب البازار ينفذها فوراً.
"""


async def analyze_competitors(owner_data: str, competitors_data: str) -> dict:
    """تحليل تنافسي ذكي لموقف البازار في السوق."""
    llm = get_llm(temperature=0.5, app_id="owner")
    prompt = COMPETITOR_ANALYSIS_PROMPT.format(
        owner_data=owner_data,
        competitors_data=competitors_data,
    )
    result = await _safe_invoke(llm, prompt, timeout=30.0, label="competitor")
    if result is None:
        return {"market_position": "unknown", "strengths": [], "weaknesses": [], "opportunities": [], "action_items": []}
    return _parse_json_response(result.content, {
        "market_position": "unknown", "strengths": [], "weaknesses": [],
        "opportunities": [], "action_items": [],
    })


# ============================================================
# NEW: Smart Campaign Generator
# ============================================================

SMART_CAMPAIGN_PROMPT = """أنت خبير تسويق رقمي متخصص في الأسواق المصرية والسياحية.

هدف الحملة: {campaign_goal}
اسم البازار: {bazaar_name}
المنتجات الرئيسية: {products_summary}
بيانات الأداء: {performance_data}

صمم حملة تسويقية ذكية بصيغة JSON:
{{
    "campaign_name": "اسم الحملة الجذاب",
    "strategy": "وصف الاستراتيجية في 2-3 جمل",
    "variants": [
        {{
            "type": "conservative",
            "label": "حملة آمنة",
            "social_post": "نص البوست لسوشيال ميديا",
            "discount_suggestion": "اقتراح خصم (إن وجد)",
            "duration_days": 7,
            "estimated_reach": "الوصول المتوقع",
            "budget_hint": "ميزانية مقترحة"
        }},
        {{
            "type": "balanced",
            "label": "حملة متوازنة",
            "social_post": "نص البوست",
            "discount_suggestion": "خصم مقترح",
            "duration_days": 14,
            "estimated_reach": "الوصول المتوقع",
            "budget_hint": "ميزانية مقترحة"
        }},
        {{
            "type": "aggressive",
            "label": "حملة قوية",
            "social_post": "نص البوست",
            "discount_suggestion": "خصم كبير",
            "duration_days": 30,
            "estimated_reach": "الوصول المتوقع",
            "budget_hint": "ميزانية مقترحة"
        }}
    ],
    "hashtags": ["#هاشتاق1", "#هاشتاق2", "#هاشتاق3"],
    "best_posting_times": ["10:00 صباحاً", "8:00 مساءً"],
    "target_audience": "وصف الجمهور المستهدف"
}}

اجعل المحتوى باللهجة المصرية وجذاب للسياح والمصريين.
"""


async def generate_smart_campaign(
    campaign_goal: str, bazaar_name: str = "",
    products_summary: str = "", performance_data: str = "",
) -> dict:
    """توليد حملة تسويقية ذكية متعددة المستويات."""
    llm = get_llm(temperature=0.8, app_id="owner")
    prompt = SMART_CAMPAIGN_PROMPT.format(
        campaign_goal=campaign_goal,
        bazaar_name=bazaar_name or "بازار",
        products_summary=products_summary or "منتجات مصرية تراثية",
        performance_data=performance_data or "لا تتوفر بيانات",
    )
    result = await _safe_invoke(llm, prompt, timeout=35.0, label="campaign")
    if result is None:
        return {"campaign_name": "", "strategy": "", "variants": [], "hashtags": []}
    return _parse_json_response(result.content, {
        "campaign_name": "", "strategy": "", "variants": [],
        "hashtags": [], "best_posting_times": [], "target_audience": "",
    })


# ============================================================
# NEW: Review Intelligence
# ============================================================

REVIEW_ANALYSIS_PROMPT = """أنت محلل آراء عملاء متخصص.

مراجعات العملاء:
{reviews_data}

حلل المراجعات واستخرج insights بصيغة JSON:
{{
    "sentiment_breakdown": {{"positive": 0, "neutral": 0, "negative": 0}},
    "average_sentiment_score": 0.0,
    "top_praised": ["ميزة 1 يمدحها العملاء", "ميزة 2"],
    "top_complaints": ["شكوى 1", "شكوى 2"],
    "common_themes": [
        {{"theme": "الموضوع", "count": 5, "sentiment": "positive/negative"}}
    ],
    "priority_actions": [
        {{"action": "إجراء مطلوب", "urgency": "high/medium/low", "reason": "السبب"}}
    ],
    "suggested_responses": [
        {{"for": "نوع المراجعة", "response": "رد مقترح"}}
    ],
    "overall_health": "excellent / good / needs_attention / critical"
}}

استخدم الأرقام الحقيقية من المراجعات. كن دقيقاً وعملياً.
"""


async def analyze_reviews(reviews_data: str) -> dict:
    """تحليل ذكي لمراجعات العملاء."""
    llm = get_llm(temperature=0.4, app_id="owner")
    prompt = REVIEW_ANALYSIS_PROMPT.format(reviews_data=reviews_data)
    result = await _safe_invoke(llm, prompt, timeout=30.0, label="reviews")
    if result is None:
        return {"sentiment_breakdown": {"positive": 0, "neutral": 0, "negative": 0}, "overall_health": "unknown"}
    return _parse_json_response(result.content, {
        "sentiment_breakdown": {"positive": 0, "neutral": 0, "negative": 0},
        "overall_health": "unknown", "top_praised": [], "top_complaints": [],
        "priority_actions": [], "suggested_responses": [],
    })


# ============================================================
# NEW: Inventory Alerts
# ============================================================

INVENTORY_ALERTS_PROMPT = """أنت خبير إدارة مخزون ذكي.

بيانات المنتجات والمخزون:
{inventory_data}

بيانات المبيعات (آخر 30 يوم):
{sales_data}

حلل المخزون وأعطني تنبيهات بصيغة JSON:
{{
    "restock_urgent": [
        {{"product_name": "المنتج", "current_stock": 5, "daily_sales_rate": 2.0, "days_until_stockout": 2, "suggested_reorder": 50, "urgency": "critical"}}
    ],
    "overstock_warnings": [
        {{"product_name": "المنتج", "current_stock": 200, "daily_sales_rate": 0.1, "days_of_supply": 2000, "suggested_discount": "20%", "reason": "السبب"}}
    ],
    "healthy_stock": [
        {{"product_name": "المنتج", "current_stock": 50, "days_of_supply": 25, "status": "healthy"}}
    ],
    "overall_health": "good / warning / critical",
    "summary": "ملخص قصير عن حالة المخزون"
}}

استخدم الأرقام الحقيقية. رتب حسب الأهمية.
"""


async def generate_inventory_alerts(inventory_data: str, sales_data: str) -> dict:
    """توليد تنبيهات مخزون ذكية."""
    llm = get_fast_llm(temperature=0.3, app_id="owner")
    prompt = INVENTORY_ALERTS_PROMPT.format(
        inventory_data=inventory_data,
        sales_data=sales_data,
    )
    result = await _safe_invoke(llm, prompt, timeout=25.0, label="inventory")
    if result is None:
        return {"restock_urgent": [], "overstock_warnings": [], "healthy_stock": [], "overall_health": "unknown"}
    return _parse_json_response(result.content, {
        "restock_urgent": [], "overstock_warnings": [],
        "healthy_stock": [], "overall_health": "unknown", "summary": "",
    })
