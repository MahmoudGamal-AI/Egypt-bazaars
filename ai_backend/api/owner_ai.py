"""
📱 Owner AI API Routes — 8 endpoints لأصحاب البازارات
✅ UPGRADED: Weighted predictions, bazaar scoping, enhanced AI summary
"""
import json
import logging
from fastapi import APIRouter, HTTPException

from models.ai_models import (
    GenerateDescriptionRequest, GenerateDescriptionResponse,
    SuggestPriceRequest, SuggestPriceResponse,
    SuggestRepliesRequest, SuggestRepliesResponse,
    GenerateContentRequest, GenerateContentResponse,
    TranslateRequest, TranslateResponse,
    DailyDigestResponse, BazaarAnalyticsResponse,
    ProductSuggestionsResponse,
)
from agents.owner_assistant_agent import (
    generate_product_description, suggest_price,
    suggest_replies, generate_content,
    generate_daily_digest, suggest_products,
    translate_text, generate_analytics_insights,
)
from services.analytics_service import compute_bazaar_analytics, get_market_prices
from services.aws_db_service import get_bazaar_products, get_bazaar_orders, get_all_products

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/owner/ai", tags=["Owner AI"])


# ============================================================
# 1. Generate Product Description
# ============================================================

@router.post("/generate-description", response_model=GenerateDescriptionResponse)
async def api_generate_description(request: GenerateDescriptionRequest):
    """✍️ توليد وصف منتج احترافي بالعربية والإنجليزية."""
    try:
        # Get market context if category is provided
        market_context = ""
        if request.category:
            prices = await get_market_prices(request.category)
            market_context = f"متوسط السعر: {prices.get('average', 0)} ج.م | النطاق: {prices.get('min', 0)}-{prices.get('max', 0)} ج.م | عدد المنتجات المشابهة: {prices.get('count', 0)}"

        result = await generate_product_description(
            product_name=request.product_name,
            category=request.category or "",
            material=request.material or "",
            extra_details=request.extra_details or "",
            market_context=market_context,
        )

        return GenerateDescriptionResponse(**result)

    except Exception as e:
        logger.error(f"Generate description error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# 2. Suggest Price
# ============================================================

@router.post("/suggest-price", response_model=SuggestPriceResponse)
async def api_suggest_price(request: SuggestPriceRequest):
    """💰 اقتراح سعر تنافسي بناءً على تحليل السوق."""
    try:
        market = await get_market_prices(request.category)
        market_data = json.dumps(market, ensure_ascii=False, default=str)

        result = await suggest_price(
            product_name=request.product_name,
            category=request.category,
            material=request.material or "",
            market_data=market_data,
        )

        # Enrich with actual market data
        result["similar_products"] = market.get("similar_products", [])
        if result.get("market_average", 0) == 0:
            result["market_average"] = market.get("average", 0)
        if result.get("price_range_min", 0) == 0:
            result["price_range_min"] = market.get("min", 0)
        if result.get("price_range_max", 0) == 0:
            result["price_range_max"] = market.get("max", 0)

        return SuggestPriceResponse(**result)

    except Exception as e:
        logger.error(f"Suggest price error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# 3. Suggest Replies
# ============================================================

@router.post("/suggest-replies", response_model=SuggestRepliesResponse)
async def api_suggest_replies(request: SuggestRepliesRequest):
    """💬 اقتراح ردود ذكية على رسائل العملاء."""
    try:
        result = await suggest_replies(
            customer_message=request.customer_message,
            customer_name=request.customer_name or "",
            context=request.context or "",
        )

        return SuggestRepliesResponse(**result)

    except Exception as e:
        logger.error(f"Suggest replies error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# 4. Daily Digest
# ============================================================

@router.get("/daily-digest/{bazaar_id}")
async def api_daily_digest(bazaar_id: str):
    """⚡ ملخص يومي ذكي لأداء البازار."""
    try:
        analytics = await compute_bazaar_analytics(bazaar_id, period="day")
        result = await generate_daily_digest(analytics)
        return result

    except Exception as e:
        logger.error(f"Daily digest error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# 5. Analytics — ✅ UPGRADED with smart predictions
# ============================================================

@router.get("/analytics/{bazaar_id}")
async def api_bazaar_analytics(bazaar_id: str, period: str = "week"):
    """📊 تحليلات ذكية مع بيانات charts وتنبؤات AI."""
    try:
        # Compute raw analytics
        analytics = await compute_bazaar_analytics(bazaar_id, period)

        # Generate AI insights
        insights = await generate_analytics_insights(analytics)

        # Combine
        analytics["ai_insights"] = insights

        # ✅ UPGRADED: Weighted Moving Average predictions
        revenue_data = analytics.get("charts_data", {}).get("revenue_line", [])
        if len(revenue_data) >= 3:
            # Weighted moving average: recent days have more weight
            recent = [d["revenue"] for d in revenue_data[-7:]]  # Up to 7 days
            weights = list(range(1, len(recent) + 1))  # [1, 2, 3, ..., n]
            weighted_avg = sum(r * w for r, w in zip(recent, weights)) / sum(weights)

            # Trend detection: compare first half vs second half
            mid = len(recent) // 2
            first_half_avg = sum(recent[:mid]) / max(mid, 1)
            second_half_avg = sum(recent[mid:]) / max(len(recent) - mid, 1)
            trend_factor = second_half_avg / max(first_half_avg, 1) if first_half_avg > 0 else 1.0
            trend_factor = max(0.5, min(trend_factor, 2.0))  # Clamp

            predicted_daily = weighted_avg * trend_factor
            confidence = min(0.95, 0.50 + (0.05 * len(revenue_data)))

            # Revenue prediction with range
            predicted_weekly = round(predicted_daily * 7, 2)
            analytics["predictions"] = {
                "next_week_revenue": predicted_weekly,
                "revenue_low": round(predicted_weekly * 0.8, 2),
                "revenue_high": round(predicted_weekly * 1.2, 2),
                "predicted_daily": round(predicted_daily, 2),
                "confidence": round(confidence, 2),
                "trend": analytics.get("revenue", {}).get("trend", "flat"),
                "trend_factor": round(trend_factor, 2),
                "method": "weighted_moving_average",
            }
        else:
            analytics["predictions"] = {
                "next_week_revenue": 0,
                "revenue_low": 0,
                "revenue_high": 0,
                "predicted_daily": 0,
                "confidence": 0.3,
                "trend": "insufficient_data",
                "trend_factor": 1.0,
                "method": "insufficient_data",
            }

        # ✅ UPGRADED: Enhanced AI Summary
        total_rev = analytics.get("revenue", {}).get("total", 0)
        change = analytics.get("revenue", {}).get("change_pct", 0)
        orders_total = analytics.get("orders", {}).get("total", 0)
        orders_change = analytics.get("orders", {}).get("change_pct", 0)
        active_products = analytics.get("products", {}).get("active", 0)
        avg_rating = analytics.get("rating", {}).get("average", 0)
        low_count = len(analytics.get("low_performers", []))

        trend_emoji = "📈" if change > 0 else "📉" if change < 0 else "➡️"
        orders_emoji = "📦" if orders_change > 0 else "📭" if orders_change < 0 else "📋"

        summary_parts = [
            f"{trend_emoji} إيرادات الفترة: {total_rev:,.0f} ج.م ({'↑' if change > 0 else '↓'} {abs(change):.1f}%)",
            f"{orders_emoji} طلبات: {orders_total} ({'↑' if orders_change > 0 else '↓'} {abs(orders_change):.1f}%)",
            f"⭐ تقييم: {avg_rating}",
            f"📦 منتجات نشطة: {active_products}",
        ]
        if low_count > 0:
            summary_parts.append(f"⚠️ {low_count} منتجات تحتاج تحسين")

        analytics["ai_summary"] = " | ".join(summary_parts)

        return analytics

    except Exception as e:
        logger.error(f"Analytics error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# 6. Generate Content
# ============================================================

@router.post("/generate-content", response_model=GenerateContentResponse)
async def api_generate_content(request: GenerateContentRequest):
    """📝 توليد محتوى تسويقي (إعلانات، سوشيال، عروض)."""
    try:
        result = await generate_content(
            content_type=request.content_type,
            product_name=request.product_name or "",
            bazaar_name=request.bazaar_name or "",
            offer_details=request.offer_details or "",
            target_audience=request.target_audience,
            language=request.language,
        )

        return GenerateContentResponse(**result)

    except Exception as e:
        logger.error(f"Content generation error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# 7. Product Suggestions
# ============================================================

@router.get("/product-suggestions/{bazaar_id}")
async def api_product_suggestions(bazaar_id: str):
    """🔮 اقتراح منتجات جديدة بناءً على اتجاهات السوق."""
    try:
        products = await get_bazaar_products(bazaar_id)
        orders = await get_bazaar_orders(bazaar_id, days=30)

        current_products = json.dumps(
            [{"name": p.get("nameAr", ""), "category": p.get("category", ""), "price": p.get("price", 0)}
             for p in products[:20]],
            ensure_ascii=False,
            default=str
        )

        # Sales data analysis
        from collections import Counter
        sold_categories = Counter()
        for order in orders:
            items = order.get("items", [])
            if isinstance(items, list):
                for item in items:
                    sold_categories[item.get("category", "أخرى")] += 1

        sales_data = json.dumps(dict(sold_categories), ensure_ascii=False)

        result = await suggest_products(
            current_products=current_products,
            sales_data=sales_data,
        )

        return result

    except Exception as e:
        logger.error(f"Product suggestions error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# 8. Translate
# ============================================================

@router.post("/translate", response_model=TranslateResponse)
async def api_translate(request: TranslateRequest):
    """🌐 ترجمة فورية عربي ↔ إنجليزي."""
    try:
        translated = await translate_text(
            text=request.text,
            source_lang=request.source_lang,
            target_lang=request.target_lang,
        )

        return TranslateResponse(
            translated_text=translated,
            source_lang=request.source_lang,
            target_lang=request.target_lang,
        )

    except Exception as e:
        logger.error(f"Translation error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# 9. Competitor Analysis
# ============================================================

@router.post("/competitor-analysis")
async def api_competitor_analysis(request: dict):
    """🏆 تحليل تنافسي لموقف البازار في السوق."""
    try:
        bazaar_id = request.get("bazaar_id", "")
        category = request.get("category")

        products = await get_bazaar_products(bazaar_id)
        all_products_raw = await get_all_products()

        # Owner's products summary
        owner_products = [p for p in all_products_raw if p.get("bazaarId") == bazaar_id]
        owner_data = json.dumps([{
            "name": p.get("nameAr", ""), "price": p.get("price", 0),
            "category": p.get("category", ""), "rating": p.get("rating", 0),
        } for p in owner_products[:15]], ensure_ascii=False, default=str)

        # Competitors in same categories
        owner_categories = {p.get("category") for p in owner_products if p.get("category")}
        if category:
            owner_categories = {category}

        competitor_products = [
            p for p in all_products_raw
            if p.get("bazaarId") != bazaar_id and p.get("category") in owner_categories
        ]
        competitors_data = json.dumps([{
            "name": p.get("nameAr", ""), "price": p.get("price", 0),
            "category": p.get("category", ""), "rating": p.get("rating", 0),
            "bazaar": p.get("bazaarName", ""),
        } for p in competitor_products[:30]], ensure_ascii=False, default=str)

        from agents.owner_assistant_agent import analyze_competitors
        result = await analyze_competitors(owner_data, competitors_data)
        return result

    except Exception as e:
        logger.error(f"Competitor analysis error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# 10. Smart Campaign Generator
# ============================================================

@router.post("/smart-campaign")
async def api_smart_campaign(request: dict):
    """🚀 توليد حملة تسويقية ذكية متعددة المستويات."""
    try:
        campaign_goal = request.get("campaign_goal", "sales_boost")
        bazaar_id = request.get("bazaar_id", "")
        bazaar_name = request.get("bazaar_name", "")

        # Get products and performance data
        products = await get_bazaar_products(bazaar_id) if bazaar_id else []
        products_summary = json.dumps([{
            "name": p.get("nameAr", ""), "price": p.get("price", 0), "category": p.get("category", ""),
        } for p in products[:10]], ensure_ascii=False, default=str)

        perf_data = ""
        if bazaar_id:
            analytics = await compute_bazaar_analytics(bazaar_id, "week")
            perf_data = json.dumps({
                "revenue": analytics.get("revenue", {}),
                "orders": analytics.get("orders", {}),
                "top_products": analytics.get("top_products", [])[:3],
            }, ensure_ascii=False, default=str)

        from agents.owner_assistant_agent import generate_smart_campaign
        result = await generate_smart_campaign(
            campaign_goal=campaign_goal,
            bazaar_name=bazaar_name,
            products_summary=products_summary,
            performance_data=perf_data,
        )
        return result

    except Exception as e:
        logger.error(f"Smart campaign error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# 11. Review Analyzer
# ============================================================

@router.get("/review-analyzer/{bazaar_id}")
async def api_review_analyzer(bazaar_id: str):
    """⭐ تحليل ذكي لمراجعات العملاء."""
    try:
        from services.aws_db_service import get_bazaar_reviews
        reviews = await get_bazaar_reviews(bazaar_id)

        if not reviews:
            return {
                "sentiment_breakdown": {"positive": 0, "neutral": 0, "negative": 0},
                "overall_health": "no_data", "top_praised": [], "top_complaints": [],
                "message": "لا توجد مراجعات بعد",
            }

        reviews_data = json.dumps([{
            "rating": r.get("rating", 0), "comment": r.get("comment", ""),
            "product": r.get("productName", ""), "date": str(r.get("created_at", "")),
        } for r in reviews[:50]], ensure_ascii=False, default=str)

        from agents.owner_assistant_agent import analyze_reviews
        result = await analyze_reviews(reviews_data)
        result["total_reviews"] = len(reviews)
        return result

    except Exception as e:
        logger.error(f"Review analysis error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================
# 12. Inventory Alerts
# ============================================================

@router.get("/inventory-alerts/{bazaar_id}")
async def api_inventory_alerts(bazaar_id: str):
    """📦 تنبيهات مخزون ذكية بناءً على سرعة البيع."""
    try:
        products = await get_bazaar_products(bazaar_id)
        orders = await get_bazaar_orders(bazaar_id, days=30)

        # Build inventory data
        inventory_data = json.dumps([{
            "name": p.get("nameAr", p.get("name", "")),
            "stock": p.get("stockQuantity", 0),
            "price": p.get("price", 0),
            "category": p.get("category", ""),
            "isInStock": p.get("isInStock", True),
        } for p in products[:30]], ensure_ascii=False, default=str)

        # Build sales data from orders
        from collections import Counter
        sales_counter = Counter()
        for order in orders:
            for item in order.get("items", []):
                name = item.get("product_name", "unknown")
                qty = int(item.get("quantity", 1))
                sales_counter[name] += qty

        sales_data = json.dumps(dict(sales_counter), ensure_ascii=False)

        from agents.owner_assistant_agent import generate_inventory_alerts
        result = await generate_inventory_alerts(inventory_data, sales_data)
        return result

    except Exception as e:
        logger.error(f"Inventory alerts error: {e}")
        raise HTTPException(status_code=500, detail=str(e))
