"""
📊 Analytics Service — تحليلات متقدمة وسريعة باستخدام Aurora PostgreSQL (AWS Native)
✅ UPGRADED: Peak Hours, Categories Pie, Low Performers, Change% for all metrics
"""
import asyncio
from datetime import datetime, timedelta
from collections import defaultdict
from services.aws_db_service import (
    get_all_products, get_bazaar_by_id, get_all_bazaars,
    get_bazaar_orders, get_bazaar_reviews, get_bazaar_messages, get_all_orders
)


# ============================================================
# Bazaar-Level Analytics (Owner App)
# ============================================================

async def compute_bazaar_analytics(bazaar_id: str, period: str = "week") -> dict:
    """حساب تحليلات شاملة للمالك بناءً على قواعد بيانات AWS Aurora."""
    days_map = {"day": 1, "week": 7, "month": 30, "quarter": 90, "year": 365}
    days = days_map.get(period, 7)

    # Fetch data concurrently
    all_products, orders, reviews = await asyncio.gather(
        get_all_products(),
        get_bazaar_orders(bazaar_id, days),
        get_bazaar_reviews(bazaar_id),
    )

    # ✅ Bazaar Scoping: فقط منتجات هذا البازار
    bazaar_products = [p for p in all_products if p.get("bazaarId") == bazaar_id]

    total_revenue = 0.0
    daily_revenue = defaultdict(float)
    daily_orders = defaultdict(int)
    product_sales = defaultdict(lambda: {"quantity": 0, "revenue": 0.0, "name": "", "category": ""})
    status_counts = defaultdict(int)
    hourly_counts = defaultdict(int)  # ✅ NEW: Peak Hours
    category_revenue = defaultdict(float)  # ✅ NEW: Categories Pie

    for order in orders:
        # ✅ FIX L4: Support both subtotal and total_amount
        subtotal = float(order.get("subtotal", 0) or order.get("total_amount", 0) or 0)
        status = order.get("status", "unknown")
        status_counts[status] += 1

        if status in ("delivered", "accepted", "preparing"):
            total_revenue += subtotal

        created_at = order.get("created_at")
        if created_at:
            if hasattr(created_at, "strftime"):
                day_key = created_at.strftime("%Y-%m-%d")
                hour = created_at.hour  # ✅ Peak Hours
                hourly_counts[hour] += 1
            else:
                day_key = str(created_at)[:10]
                # Try to extract hour from ISO string
                try:
                    hour = int(str(created_at)[11:13])
                    hourly_counts[hour] += 1
                except (ValueError, IndexError):
                    pass
            daily_revenue[day_key] += subtotal
            daily_orders[day_key] += 1

        for item in order.get("items", []):
            pid = item.get("product_id", "")
            qty = int(item.get("quantity", 1))
            total_price = float(item.get("total_price", 0))
            cat = item.get("category", "أخرى")
            product_sales[pid]["quantity"] += qty
            product_sales[pid]["revenue"] += total_price
            product_sales[pid]["name"] = item.get("product_name", "منتج")
            product_sales[pid]["category"] = cat
            category_revenue[cat] += total_price  # ✅ Categories Pie

    # ============================================================
    # Previous Period Comparison
    # ============================================================
    prev_orders = await get_bazaar_orders(bazaar_id, days * 2)
    cutoff = datetime.utcnow() - timedelta(days=days)
    prev_revenue = 0.0
    prev_order_count = 0
    for order in prev_orders:
        created_at = order.get("created_at")
        is_previous_period = False
        if hasattr(created_at, "replace"):
            cnaive = created_at.replace(tzinfo=None)
            if cnaive < cutoff:
                is_previous_period = True
        elif isinstance(created_at, str) and created_at < cutoff.isoformat():
            is_previous_period = True

        if is_previous_period:
            prev_order_count += 1
            if order.get("status") in ("delivered", "accepted", "preparing"):
                prev_revenue += float(order.get("subtotal", 0) or order.get("total_amount", 0) or 0)

    # ✅ Revenue change %
    revenue_change = 0.0
    if prev_revenue > 0:
        revenue_change = ((total_revenue - prev_revenue) / prev_revenue) * 100

    # ✅ NEW: Orders change %
    orders_change = 0.0
    if prev_order_count > 0:
        orders_change = ((len(orders) - prev_order_count) / prev_order_count) * 100

    # Sort daily data
    sorted_days = sorted(daily_revenue.keys())
    revenue_chart = [
        {"date": d, "revenue": round(daily_revenue[d], 2), "orders": daily_orders[d]}
        for d in sorted_days
    ]

    # Top products
    sorted_products = sorted(product_sales.items(), key=lambda x: x[1]["revenue"], reverse=True)[:10]
    top_products = [
        {"id": pid, "name": data["name"], "quantity": data["quantity"], "revenue": round(data["revenue"], 2)}
        for pid, data in sorted_products
    ]

    # ✅ NEW: Low Performers — منتجات مسجلة لكن بدون مبيعات أو مبيعات ضعيفة
    sold_product_ids = set(product_sales.keys())
    low_performers = []
    for p in bazaar_products:
        pid = p.get("id", "")
        name = p.get("nameAr", p.get("name", "منتج"))
        if pid not in sold_product_ids:
            low_performers.append({
                "id": pid, "name": name,
                "issue": "لا توجد مبيعات",
                "suggestion": "حاول تحسين الصور والوصف أو تقديم خصم"
            })
        elif product_sales[pid]["quantity"] <= 1:
            low_performers.append({
                "id": pid, "name": name,
                "issue": f"مبيعات ضعيفة ({product_sales[pid]['quantity']} وحدة)",
                "suggestion": "جرب تغيير السعر أو إضافة عرض خاص"
            })
    low_performers = low_performers[:5]  # Top 5 worst

    # ✅ NEW: Peak Hours — أوقات الذروة
    peak_hours = []
    if hourly_counts:
        sorted_hours = sorted(hourly_counts.items(), key=lambda x: x[1], reverse=True)
        for hour, count in sorted_hours[:6]:
            peak_hours.append({
                "hour": hour,
                "label": f"{hour:02d}:00",
                "orders": count,
            })

    # ✅ NEW: Hourly bar chart data (all 24 hours)
    hourly_bar = [
        {"hour": h, "label": f"{h:02d}:00", "orders": hourly_counts.get(h, 0)}
        for h in range(24)
    ]

    # ✅ NEW: Categories Pie Chart
    categories_pie = sorted(
        [{"category": cat, "revenue": round(rev, 2)} for cat, rev in category_revenue.items()],
        key=lambda x: x["revenue"],
        reverse=True
    )[:6]

    # Avg rating
    avg_rating = 0.0
    if reviews:
        ratings = [float(r.get("rating", 0)) for r in reviews if r.get("rating")]
        avg_rating = round(sum(ratings) / len(ratings), 1) if ratings else 0.0

    return {
        "period": period,
        "days": days,
        "revenue": {
            "total": round(total_revenue, 2),
            "previous": round(prev_revenue, 2),
            "change_pct": round(revenue_change, 1),
            "trend": "up" if revenue_change > 0 else "down" if revenue_change < 0 else "flat",
        },
        "orders": {
            "total": len(orders),
            "previous": prev_order_count,
            "change_pct": round(orders_change, 1),
            "delivered": status_counts.get("delivered", 0),
            "cancelled": status_counts.get("cancelled", 0),
            "pending": status_counts.get("pending", 0),
        },
        "products": {
            "total": len(bazaar_products),
            "active": len([p for p in bazaar_products if p.get("isActive", True)]),
            "no_description": len([p for p in bazaar_products if not p.get("descriptionAr")]),
        },
        "rating": {"average": avg_rating, "count": len(reviews)},
        "top_products": top_products,
        "peak_hours": peak_hours,
        "low_performers": low_performers,
        "charts_data": {
            "revenue_line": revenue_chart,
            "categories_pie": categories_pie,
            "hourly_bar": hourly_bar,
            "products_bar": top_products[:5],
        },
    }


# ============================================================
# Platform-Level Analytics (Admin Panel)
# ============================================================

async def compute_platform_analytics(period: str = "month") -> dict:
    """تحليلات شاملة للمنصة للمديرين (Admin AI) — محسنة باستخدام SQL."""
    days_map = {"week": 7, "month": 30, "quarter": 90, "year": 365}
    days = days_map.get(period, 30)

    from services.aws_db_service import (
        get_platform_metrics_sql, get_bazaar_rankings_sql,
        get_category_distribution_sql, get_revenue_trend_sql
    )

    # Fetch optimized metrics concurrently — with null-safety
    raw_metrics, raw_rankings, raw_categories, raw_revenue_trend = await asyncio.gather(
        get_platform_metrics_sql(days),
        get_bazaar_rankings_sql(days, limit=10),
        get_category_distribution_sql(),
        get_revenue_trend_sql(days),
    )

    # ✅ Null-safety: protect against DB failures returning None
    metrics = raw_metrics or {
        "total_revenue": 0, "total_orders": 0, "delivered_orders": 0,
        "cancelled_orders": 0, "total_customers": 0, "total_bazaars": 0,
        "active_bazaars": 0, "total_products": 0, "cancellation_rate": 0,
    }
    rankings = raw_rankings or []
    categories = raw_categories or []
    revenue_trend = raw_revenue_trend or []

    # Format rankings for the UI
    bazaar_rankings = []
    for i, r in enumerate(rankings):
        bazaar_rankings.append({
            "id": r["id"],
            "name": r["name"],
            "revenue": float(r["revenue"]),
            "orders": r["order_count"],
            "tier": "gold" if i < 3 else "silver" if i < 6 else "bronze",
            "rank": i + 1,
        })

    if not bazaar_rankings:
        bazaar_rankings.append({"id": "dummy", "name": "لا مبيعات خالية", "revenue": 0.0, "orders": 0, "tier": "bronze", "rank": 1})

    return {
        "period": period,
        "key_metrics": {
            "total_revenue": float(metrics.get("total_revenue", 0) or 0),
            "total_orders": metrics.get("total_orders", 0) or 0,
            "delivered_orders": metrics.get("delivered_orders", 0) or 0,
            "total_customers": metrics.get("total_customers", 0) or 0,
            "total_bazaars": metrics.get("total_bazaars", 0) or 0,
            "active_bazaars": metrics.get("active_bazaars", 0) or 0,
            "total_products": metrics.get("total_products", 0) or 0,
            "cancellation_rate": metrics.get("cancellation_rate", 0) or 0,
        },
        "bazaar_rankings": bazaar_rankings,
        "inactive_bazaars": [], 
        "status_distribution": {}, 
        "charts_data": {
            "revenue_line": revenue_trend,
            "categories_pie": [{"category": c["category"] or "عام", "revenue": c["count"]} for c in categories[:6]],
            "bazaar_bar": bazaar_rankings[:5],
        },
    }

async def get_platform_health() -> dict:
    """الحصول على صحة المنصة الحقيقية بناءً على جودة البيانات."""
    from services.aws_db_service import get_system_health_metrics_sql
    health = await get_system_health_metrics_sql()
    
    return {
        "health_score": health["health_score"],
        "bazaars": {"total": health.get("bazaars_total", 0), "approved": 0}, # Simplified
        "products": {
            "total": health["products_total"],
            "active": health["products_total"], # Placeholder
            "no_image": health["missing_images"],
            "no_description": health["missing_descriptions"],
        },
        "pending_applications": health["pending_applications"]
    }

async def get_market_prices(category: str) -> dict:
    """تحليل أسعار السوق لفئة معينة باستخدام SQL."""
    from services.aws_db_service import get_market_prices_sql
    stats = await get_market_prices_sql(category)
    
    if not stats or stats.get("count", 0) == 0:
        return {"average": 0, "min": 0, "max": 0, "count": 0, "median": 0}

    return {
        "average": round(stats["average"], 2),
        "min": stats["min"],
        "max": stats["max"],
        "median": stats["median"],
        "count": stats["count"],
    }
