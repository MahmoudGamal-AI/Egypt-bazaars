"""
🛡️ Moderation Agent
Used exclusively by the admin application to review and approve/reject products and bazaars.
Features: Fallback chain, input sanitization, robust error handling.
"""
import logging
import re
from core.llm_service import invoke_with_fallback
from core.db_service import get_product_by_id, get_bazaar_application, get_bazaar_by_id, get_market_prices
from core.json_utils import parse_json_response

logger = logging.getLogger(__name__)


# ============================================================
# Input Sanitization
# ============================================================

def _sanitize_input(text: str, max_length: int = 500) -> str:
    """Sanitize user-provided text before sending to LLM to prevent prompt injection."""
    if not text:
        return ""
    # Remove potential prompt injection patterns
    text = text.strip()[:max_length]
    # Remove markdown-like instructions that could confuse the LLM
    text = re.sub(r'```[\s\S]*?```', '[code removed]', text)
    text = re.sub(r'<[^>]+>', '', text)  # Remove HTML tags
    return text


# ============================================================
# System Prompts
# ============================================================

MODERATE_PRODUCT_PROMPT = """أنت مراقب جودة محتوى في منصة سياحة مصرية.

مهمتك: فحص منتج جديد والتأكد من جودته قبل العرض.

بيانات المنتج:
- الاسم (عربي): {name_ar}
- الاسم (إنجليزي): {name_en}
- الوصف (عربي): {desc_ar}
- الوصف (إنجليزي): {desc_en}
- السعر: {price} ج.م
- الفئة: {category}
- رابط الصورة: {image_url}

بيانات السوق لنفس الفئة:
- متوسط السعر: {avg_price} ج.م
- نطاق الأسعار: {price_range}

قيّم المنتج بصيغة JSON:
{{
    "overall_score": نقاط_من_100,
    "status": "approved | needs_review | rejected",
    "checks": {{
        "name_quality": {{"score": 0, "pass": true, "feedback": ".."}},
        "description_quality": {{"score": 0, "pass": true, "feedback": ".."}},
        "price_analysis": {{"score": 0, "pass": true, "feedback": ".."}},
        "image_presence": {{"score": 0, "pass": true, "feedback": ".."}},
        "category_match": {{"score": 0, "pass": true, "feedback": ".."}},
        "content_safety": {{"score": 0, "pass": true, "feedback": ".."}}
    }},
    "auto_category": "الفئة المقترحة",
    "category_confidence": 0.9,
    "suggestions": ["اقتراح 1"]
}}

معايير: 80+ (موافقة تلقائية), 50-79 (مراجعة), <50 (مرفوض)
"""

ANALYZE_APPLICATION_PROMPT = """أنت مراجع طلبات انضمام بازارات في منصة سياحة مصرية.

بيانات الطلب:
- البازار: {bazaar_name}
- الوصف: {description}
- العنوان: {location}
- رقم الهاتف: {phone}
- البريد: {email}
- المالك: {owner_name}

قيّم الطلب بصيغة JSON:
{{
    "overall_score": 0,
    "recommendation": "approve | review | reject",
    "checks": {{
        "name_validation": {{"score": 0, "pass": true, "feedback": ".."}},
        "description_quality": {{"score": 0, "pass": true, "feedback": ".."}},
        "location_validation": {{"score": 0, "pass": true, "feedback": ".."}},
        "contact_info": {{"score": 0, "pass": true, "feedback": ".."}}
    }},
    "risk_factors": [],
    "suggestions": []
}}
"""

# ============================================================
# Agent Execution
# ============================================================

async def moderate_product(product_id: str) -> dict:
    """Analyze a single product and return a moderation score and decision."""
    product = await get_product_by_id(product_id)
    if not product:
        return {
            "product_id": product_id,
            "overall_score": 0, "status": "rejected", "checks": {},
            "suggestions": ["المنتج غير موجود ببيانات النظام."],
            "auto_category": "", "category_confidence": 0.0,
        }

    category = product.get("category", "أخرى")
    market = await get_market_prices(category)

    prompt = MODERATE_PRODUCT_PROMPT.format(
        name_ar=_sanitize_input(product.get("nameAr", "")),
        name_en=_sanitize_input(product.get("nameEn", "")),
        desc_ar=_sanitize_input(product.get("descriptionAr", ""), max_length=1000),
        desc_en=_sanitize_input(product.get("descriptionEn", ""), max_length=1000),
        price=product.get("price", 0),
        category=_sanitize_input(category),
        image_url=product.get("imageUrl", "لا يوجد"),
        avg_price=market.get("average", 0),
        price_range=f"{market.get('min', 0)} - {market.get('max', 0)}",
    )

    result_text = await invoke_with_fallback(prompt, agent="admin", temperature=0.3, app_id="admin")
    parsed = parse_json_response(result_text)
    if not parsed:
        parsed = {"overall_score": 50, "status": "needs_review", "checks": {}, "suggestions": ["تعذر تقييم المنتج تلقائياً"]}

    parsed["product_id"] = product_id
    return parsed


async def analyze_application(application_id: str) -> dict:
    """Analyze a newly submitted bazaar application."""
    data = await get_bazaar_application(application_id)
    if not data:
        data = await get_bazaar_by_id(application_id)  # fallback

    if not data:
        return {
            "application_id": application_id, "overall_score": 0,
            "recommendation": "reject", "checks": {},
            "risk_factors": ["الطلب المعرف غير موجود بالقاعدة"], "suggestions": []
        }

    prompt = ANALYZE_APPLICATION_PROMPT.format(
        bazaar_name=_sanitize_input(data.get("nameAr", data.get("name_ar", ""))),
        description=_sanitize_input(data.get("descriptionAr", data.get("description_ar", "")), max_length=1000),
        location=_sanitize_input(data.get("address", data.get("location", ""))),
        phone=_sanitize_input(data.get("phone", "")),
        email=_sanitize_input(data.get("email", "")),
        owner_name=_sanitize_input(data.get("ownerName", data.get("owner_name", ""))),
    )

    result_text = await invoke_with_fallback(prompt, agent="admin", temperature=0.3, app_id="admin")
    parsed = parse_json_response(result_text)
    if not parsed:
        parsed = {"overall_score": 50, "recommendation": "review", "checks": {}, "suggestions": ["تعذر تقييم الطلب تلقائياً"]}

    parsed["application_id"] = application_id
    return parsed
