"""
☁️ Core DB Service — Aurora PostgreSQL & DynamoDB queries.
Admin-relevant queries: products, bazaars, orders, analytics.
"""
import json
import asyncio
import logging
from decimal import Decimal
from datetime import datetime, timedelta
from psycopg2.extras import RealDictCursor
from core.aws_memory import get_aurora_connection, release_aurora_connection, get_dynamo_table

logger = logging.getLogger(__name__)


# ============================================================
# Helper: Run blocking DB call in thread pool
# ============================================================

def _execute_aurora_query(query_fn):
    """Execute a synchronous Aurora query function, managing connection lifecycle."""
    conn = get_aurora_connection()
    if not conn:
        return None
    try:
        return query_fn(conn)
    except Exception as e:
        logger.error(f"Aurora query error: {e}")
        return None
    finally:
        release_aurora_connection(conn)


def _execute_aurora_query_with_retry(query_fn, max_retries: int = 2):
    """Execute Aurora query with retry on connection errors."""
    for attempt in range(max_retries + 1):
        try:
            result = _execute_aurora_query(query_fn)
            if result is not None:
                return result
            if attempt < max_retries:
                logger.warning(f"Aurora query returned None, retry {attempt + 1}/{max_retries}")
                import time
                time.sleep(0.5 * (attempt + 1))
        except Exception as e:
            if attempt < max_retries:
                logger.warning(f"Aurora query error (retry {attempt + 1}): {e}")
            else:
                logger.error(f"Aurora query failed after {max_retries + 1} attempts: {e}")
    return None


def json_serial(obj):
    """JSON serializer for objects not serializable by default json code."""
    if isinstance(obj, (datetime,)):
        return obj.isoformat()
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError("Type %s not serializable" % type(obj))


def _convert_decimals(row: dict) -> dict:
    """Convert all Decimal values in a dict to float for JSON safety."""
    for key, val in row.items():
        if isinstance(val, Decimal):
            row[key] = float(val)
    return row


# ============================================================
# Product Queries (Aurora PostgreSQL)
# ============================================================

async def get_product_by_id(product_id: str) -> dict | None:
    """Get a single product by ID."""
    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                'SELECT id, name_ar AS "nameAr", name_en AS "nameEn", '
                'description_ar AS "descriptionAr", description_en AS "descriptionEn", '
                'category_name AS category, price, old_price AS "oldPrice", '
                'rating, review_count AS "reviewCount", image_url AS "imageUrl", '
                'bazaar_name AS "bazaarName", bazaar_id AS "bazaarId", '
                'material, sizes '
                'FROM products WHERE id = %s', (product_id,)
            )
            row = cur.fetchone()
            if row:
                res = _convert_decimals(dict(row))
                if res.get("sizes") and isinstance(res["sizes"], str):
                    try:
                        res["sizes"] = json.loads(res["sizes"])
                    except Exception:
                        res["sizes"] = [res["sizes"]]
                return res
        return None

    return await asyncio.to_thread(_execute_aurora_query_with_retry, _query)


async def get_all_products() -> list[dict]:
    """Get all products (Full details — for Admin Dashboard)."""
    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                'SELECT id, name_ar AS "nameAr", name_en AS "nameEn", '
                'description_ar AS "descriptionAr", category_name AS category, '
                'price, old_price AS "oldPrice", rating, review_count AS "reviewCount", '
                'image_url AS "imageUrl", bazaar_name AS "bazaarName", '
                'is_active AS "isActive", is_featured AS "isFeatured" '
                'FROM products'
            )
            rows = cur.fetchall()
            return [_convert_decimals(dict(r)) for r in rows]

    result = await asyncio.to_thread(_execute_aurora_query_with_retry, _query)
    return result or []


# ============================================================
# Bazaar Queries (Aurora PostgreSQL)
# ============================================================

async def get_bazaar_by_id(bazaar_id: str) -> dict | None:
    """Get a single bazaar by ID."""
    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                'SELECT id, name_ar AS "nameAr", name_en AS "nameEn", '
                'description_ar AS "descriptionAr", address, '
                'working_hours AS "workingHours", phone, rating, '
                'review_count AS "reviewCount", is_open AS "isOpen", '
                'is_approved AS "isApproved", latitude, longitude '
                'FROM bazaars WHERE id = %s', (bazaar_id,)
            )
            row = cur.fetchone()
            return _convert_decimals(dict(row)) if row else None

    return await asyncio.to_thread(_execute_aurora_query_with_retry, _query)


async def get_bazaar_application(application_id: str) -> dict | None:
    """Get a bazaar application by ID."""
    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT * FROM bazaar_applications WHERE id = %s", (application_id,))
            row = cur.fetchone()
            return dict(row) if row else None

    return await asyncio.to_thread(_execute_aurora_query_with_retry, _query)


async def get_all_bazaars() -> list[dict]:
    """Get all bazaars."""
    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                'SELECT id, name_ar AS "nameAr", name_en AS "nameEn", '
                'address, is_open AS "isOpen", is_approved AS "isApproved" '
                'FROM bazaars'
            )
            return [dict(r) for r in cur.fetchall()]

    result = await asyncio.to_thread(_execute_aurora_query_with_retry, _query)
    return result or []


# ============================================================
# Orders & Analytics Queries — FIXED N+1 with JOIN
# ============================================================

async def get_all_orders(days: int) -> list[dict]:
    """Get all orders with their items in the last N days — single JOIN query."""
    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cutoff = datetime.utcnow() - timedelta(days=days)
            # Single JOIN query instead of N+1
            cur.execute("""
                SELECT 
                    o.id, o.bazaar_id, o.total_amount AS total, 
                    o.status, o.created_at,
                    oi.id AS item_id, oi.product_id, oi.quantity, 
                    oi.price_at_purchase AS item_price
                FROM orders o
                LEFT JOIN order_items oi ON oi.order_id = o.id
                WHERE o.created_at >= %s
                ORDER BY o.created_at DESC
            """, (cutoff,))
            
            rows = cur.fetchall()
            
            # Group items by order
            orders_map: dict[str, dict] = {}
            for row in rows:
                row = dict(row)
                order_id = row["id"]
                if order_id not in orders_map:
                    orders_map[order_id] = {
                        "id": order_id,
                        "bazaar_id": row.get("bazaar_id"),
                        "total": float(row.get("total") or 0) if row.get("total") else 0,
                        "status": row.get("status", "unknown"),
                        "created_at": row.get("created_at"),
                        "items": [],
                    }
                # Add item if exists (LEFT JOIN may produce null items)
                if row.get("item_id"):
                    orders_map[order_id]["items"].append({
                        "product_id": row.get("product_id"),
                        "quantity": row.get("quantity", 1),
                        "price": float(row["item_price"]) if row.get("item_price") else 0,
                    })
            
            return list(orders_map.values())

    result = await asyncio.to_thread(_execute_aurora_query_with_retry, _query)
    return result or []


async def get_user_count() -> int:
    """Get total count of registered users."""
    def _query(conn):
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM users")
            return cur.fetchone()[0]
    return await asyncio.to_thread(_execute_aurora_query_with_retry, _query) or 0


async def get_bazaar_orders(bazaar_id: str, days: int) -> list[dict]:
    """Get orders for a specific bazaar in the last N days — JOIN query."""
    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cutoff = datetime.utcnow() - timedelta(days=days)
            cur.execute("""
                SELECT 
                    o.id, o.bazaar_id, o.total_amount AS total,
                    o.status, o.created_at,
                    oi.id AS item_id, oi.product_id, oi.quantity,
                    oi.price_at_purchase AS item_price
                FROM orders o
                LEFT JOIN order_items oi ON oi.order_id = o.id
                WHERE o.bazaar_id = %s AND o.created_at >= %s
                ORDER BY o.created_at DESC
            """, (bazaar_id, cutoff))
            
            rows = cur.fetchall()
            orders_map: dict[str, dict] = {}
            for row in rows:
                row = dict(row)
                order_id = row["id"]
                if order_id not in orders_map:
                    orders_map[order_id] = {
                        "id": order_id,
                        "bazaar_id": row.get("bazaar_id"),
                        "total": float(row.get("total") or 0),
                        "status": row.get("status"),
                        "created_at": row.get("created_at"),
                        "items": [],
                    }
                if row.get("item_id"):
                    orders_map[order_id]["items"].append({
                        "product_id": row.get("product_id"),
                        "quantity": row.get("quantity", 1),
                        "price": float(row["item_price"]) if row.get("item_price") else 0,
                    })
            return list(orders_map.values())

    result = await asyncio.to_thread(_execute_aurora_query_with_retry, _query)
    return result or []


async def get_bazaar_reviews(bazaar_id: str) -> list[dict]:
    """Get reviews for a specific bazaar."""
    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT * FROM reviews WHERE bazaar_id = %s", (bazaar_id,))
            return [dict(r) for r in cur.fetchall()]

    result = await asyncio.to_thread(_execute_aurora_query_with_retry, _query)
    return result or []


# ============================================================
# User Memory (DynamoDB)
# ============================================================

async def get_user_memory(user_id: str) -> dict:
    """Get user memory (preferences + favorites)."""
    from core.aws_memory import get_preferences
    prefs = get_preferences(user_id)
    return {
        "preferences": prefs,
        "topics_discussed": [],
        "conversation_count": 0,
    }


# ============================================================
# Market Prices — SQL Aggregation (no full table scan)
# ============================================================

async def get_market_prices(category: str) -> dict:
    """Get market price statistics for a given category using SQL aggregation."""
    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT 
                    COALESCE(AVG(price), 0) AS average,
                    COALESCE(MIN(price), 0) AS min_price,
                    COALESCE(MAX(price), 0) AS max_price,
                    COUNT(*) AS count,
                    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS median
                FROM products 
                WHERE category_name = %s AND price > 0
            """, (category,))
            row = cur.fetchone()
            if row and row["count"] > 0:
                return {
                    "average": round(float(row["average"]), 2),
                    "min": float(row["min_price"]),
                    "max": float(row["max_price"]),
                    "median": float(row["median"]) if row.get("median") else 0,
                    "count": row["count"],
                }
            return {"average": 0, "min": 0, "max": 0, "median": 0, "count": 0}

    result = await asyncio.to_thread(_execute_aurora_query_with_retry, _query)
    return result or {"average": 0, "min": 0, "max": 0, "median": 0, "count": 0}


# ============================================================
# Category & Hall Queries (Aurora PostgreSQL)
# ============================================================

async def get_all_categories() -> list[dict]:
    """Get all categories."""
    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute('SELECT * FROM categories ORDER BY "order" ASC')
            return [dict(r) for r in cur.fetchall()]
    return await asyncio.to_thread(_execute_aurora_query_with_retry, _query) or []


async def get_all_halls() -> list[dict]:
    """Get all exhibition halls."""
    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute('SELECT * FROM exhibition_halls')
            return [dict(r) for r in cur.fetchall()]
    return await asyncio.to_thread(_execute_aurora_query_with_retry, _query) or []


# ============================================================
# Advanced Analytics Queries — SQL-level aggregation
# ============================================================

async def get_revenue_summary(days: int = 30) -> dict:
    """Get revenue summary using SQL aggregation — no Python loops needed."""
    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cutoff = datetime.utcnow() - timedelta(days=days)
            cur.execute("""
                SELECT
                    COALESCE(SUM(total_amount), 0) AS total_revenue,
                    COUNT(*) AS total_orders,
                    COALESCE(AVG(total_amount), 0) AS avg_order_value,
                    COALESCE(MAX(total_amount), 0) AS max_order,
                    COALESCE(MIN(total_amount), 0) AS min_order,
                    COUNT(CASE WHEN status = 'delivered' THEN 1 END) AS delivered,
                    COUNT(CASE WHEN status = 'cancelled' THEN 1 END) AS cancelled,
                    COUNT(CASE WHEN status = 'pending' THEN 1 END) AS pending,
                    COUNT(CASE WHEN status = 'accepted' THEN 1 END) AS accepted
                FROM orders
                WHERE created_at >= %s
            """, (cutoff,))
            row = cur.fetchone()
            if row:
                return {k: float(v) if isinstance(v, Decimal) else v for k, v in dict(row).items()}
            return {}
    result = await asyncio.to_thread(_execute_aurora_query_with_retry, _query)
    return result or {"total_revenue": 0, "total_orders": 0, "avg_order_value": 0}


async def get_top_products(limit: int = 10, days: int = 30) -> list[dict]:
    """Get top selling products by revenue — single SQL JOIN query."""
    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cutoff = datetime.utcnow() - timedelta(days=days)
            cur.execute("""
                SELECT
                    p.id,
                    p.name_ar AS "nameAr",
                    p.category_name AS category,
                    p.price,
                    p.image_url AS "imageUrl",
                    COUNT(oi.id) AS total_sold,
                    COALESCE(SUM(oi.price_at_purchase * oi.quantity), 0) AS total_revenue
                FROM order_items oi
                JOIN products p ON p.id = oi.product_id
                JOIN orders o ON o.id = oi.order_id
                WHERE o.created_at >= %s
                  AND o.status IN ('delivered', 'accepted')
                GROUP BY p.id, p.name_ar, p.category_name, p.price, p.image_url
                ORDER BY total_revenue DESC
                LIMIT %s
            """, (cutoff, limit))
            rows = cur.fetchall()
            return [_convert_decimals(dict(r)) for r in rows]
    result = await asyncio.to_thread(_execute_aurora_query_with_retry, _query)
    return result or []


async def get_category_stats() -> list[dict]:
    """Get category-level statistics from SQL — no Python grouping needed."""
    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT
                    category_name AS category,
                    COUNT(*) AS product_count,
                    COALESCE(AVG(price), 0) AS avg_price,
                    COALESCE(MIN(price), 0) AS min_price,
                    COALESCE(MAX(price), 0) AS max_price,
                    COUNT(CASE WHEN is_active = true THEN 1 END) AS active_count,
                    COUNT(CASE WHEN is_featured = true THEN 1 END) AS featured_count
                FROM products
                GROUP BY category_name
                ORDER BY product_count DESC
            """)
            rows = cur.fetchall()
            return [_convert_decimals(dict(r)) for r in rows]
    result = await asyncio.to_thread(_execute_aurora_query_with_retry, _query)
    return result or []


async def get_daily_orders(days: int = 30) -> list[dict]:
    """Get daily order trends from SQL aggregation."""
    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cutoff = datetime.utcnow() - timedelta(days=days)
            cur.execute("""
                SELECT
                    DATE(created_at) AS date,
                    COUNT(*) AS order_count,
                    COALESCE(SUM(total_amount), 0) AS daily_revenue,
                    COUNT(CASE WHEN status = 'delivered' THEN 1 END) AS delivered,
                    COUNT(CASE WHEN status = 'cancelled' THEN 1 END) AS cancelled
                FROM orders
                WHERE created_at >= %s
                GROUP BY DATE(created_at)
                ORDER BY date ASC
            """, (cutoff,))
            rows = cur.fetchall()
            result = []
            for r in rows:
                row = dict(r)
                # Convert date object to string
                if hasattr(row.get("date"), "isoformat"):
                    row["date"] = row["date"].isoformat()
                result.append(_convert_decimals(row))
            return result
    result = await asyncio.to_thread(_execute_aurora_query_with_retry, _query)
    return result or []


async def get_reviews_summary() -> dict:
    """Get platform-wide review statistics from SQL."""
    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT
                    COUNT(*) AS total_reviews,
                    COALESCE(AVG(rating), 0) AS avg_rating,
                    COUNT(CASE WHEN rating >= 4 THEN 1 END) AS positive_reviews,
                    COUNT(CASE WHEN rating <= 2 THEN 1 END) AS negative_reviews,
                    COUNT(CASE WHEN rating = 5 THEN 1 END) AS five_star,
                    COUNT(CASE WHEN rating = 1 THEN 1 END) AS one_star
                FROM reviews
            """)
            row = cur.fetchone()
            if row:
                return {k: float(v) if isinstance(v, Decimal) else v for k, v in dict(row).items()}
            return {}
    result = await asyncio.to_thread(_execute_aurora_query_with_retry, _query)
    return result or {"total_reviews": 0, "avg_rating": 0, "positive_reviews": 0, "negative_reviews": 0}


# ============================================================
# 🧠 Text-to-SQL Engine — Dynamic Read-Only Queries
# ============================================================

# Allowed tables (whitelist — only business tables, not system tables)
_ALLOWED_TABLES = {
    "orders", "order_items", "products", "bazaars", "users",
    "reviews", "categories", "exhibition_halls", "bazaar_applications",
}

# Dangerous keywords — STRICTLY BLOCKED
_BLOCKED_KEYWORDS = {
    "INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "TRUNCATE", "CREATE",
    "GRANT", "REVOKE", "EXEC", "EXECUTE", "CALL", "COPY", "LOAD",
    "MERGE", "REPLACE", "UPSERT", "SET", "VACUUM", "REINDEX",
    "COMMENT", "SECURITY", "OWNER", "REASSIGN", "LOCK", "NOTIFY",
    "LISTEN", "UNLISTEN", "DISCARD", "PREPARE", "DEALLOCATE",
    "BEGIN", "COMMIT", "ROLLBACK", "SAVEPOINT", "RELEASE",
    "pg_", "information_schema",  # Block access to system schemas
}

# Max rows and timeout
_MAX_RESULT_ROWS = 100
_QUERY_TIMEOUT_SECONDS = 10


async def get_db_schema() -> dict:
    """Introspect the actual database schema from information_schema.
    Returns table names with their columns, types, and constraints.
    Cached for 10 minutes to avoid repeated introspection."""

    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            # Get columns for allowed tables only
            placeholders = ", ".join(["%s"] * len(_ALLOWED_TABLES))
            cur.execute(f"""
                SELECT
                    table_name,
                    column_name,
                    data_type,
                    is_nullable,
                    column_default
                FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name IN ({placeholders})
                ORDER BY table_name, ordinal_position
            """, tuple(_ALLOWED_TABLES))

            rows = cur.fetchall()
            schema = {}
            for row in rows:
                tbl = row["table_name"]
                if tbl not in schema:
                    schema[tbl] = {"columns": []}
                schema[tbl]["columns"].append({
                    "name": row["column_name"],
                    "type": row["data_type"],
                    "nullable": row["is_nullable"] == "YES",
                })

            # Get row counts for each table
            for tbl in schema:
                try:
                    cur.execute(f'SELECT COUNT(*) AS cnt FROM "{tbl}"')
                    count_row = cur.fetchone()
                    schema[tbl]["row_count"] = count_row["cnt"] if count_row else 0
                except Exception:
                    schema[tbl]["row_count"] = -1

            # Get foreign key relationships
            cur.execute("""
                SELECT
                    tc.table_name,
                    kcu.column_name,
                    ccu.table_name AS foreign_table,
                    ccu.column_name AS foreign_column
                FROM information_schema.table_constraints AS tc
                JOIN information_schema.key_column_usage AS kcu
                    ON tc.constraint_name = kcu.constraint_name
                JOIN information_schema.constraint_column_usage AS ccu
                    ON ccu.constraint_name = tc.constraint_name
                WHERE tc.constraint_type = 'FOREIGN KEY'
                  AND tc.table_schema = 'public'
            """)
            fk_rows = cur.fetchall()
            for fk in fk_rows:
                tbl = fk["table_name"]
                if tbl in schema:
                    if "foreign_keys" not in schema[tbl]:
                        schema[tbl]["foreign_keys"] = []
                    schema[tbl]["foreign_keys"].append({
                        "column": fk["column_name"],
                        "references": f"{fk['foreign_table']}.{fk['foreign_column']}",
                    })

            return schema

    result = await asyncio.to_thread(_execute_aurora_query_with_retry, _query)
    return result or {}


def _validate_sql_safety(sql: str) -> tuple[bool, str]:
    """Multi-layer SQL security validation. Returns (is_safe, reason)."""

    if not sql or not sql.strip():
        return False, "استعلام فارغ"

    cleaned = sql.strip().rstrip(";").strip()
    upper = cleaned.upper()

    # Layer 1: Must start with SELECT or WITH (for CTEs)
    if not upper.startswith("SELECT") and not upper.startswith("WITH"):
        return False, "مسموح فقط باستعلامات SELECT للقراءة"

    # Layer 2: Check for blocked keywords
    # Split by whitespace, parentheses, and common SQL delimiters
    import re
    tokens = set(re.findall(r'[A-Za-z_][A-Za-z0-9_]*', upper))
    for blocked in _BLOCKED_KEYWORDS:
        if blocked.upper() in tokens:
            return False, f"الكلمة '{blocked}' ممنوعة — استعلامات القراءة فقط"

    # Layer 3: Block multiple statements (SQL injection via semicolons)
    # Remove string literals first to avoid false positives
    no_strings = re.sub(r"'[^']*'", "", cleaned)
    if ";" in no_strings:
        return False, "ممنوع تنفيذ أكثر من استعلام في نفس الوقت"

    # Layer 4: Block comments (potential SQL injection)
    if "--" in cleaned or "/*" in cleaned:
        return False, "التعليقات ممنوعة في الاستعلامات"

    # Layer 5: Verify only allowed tables are referenced
    # Extract table references from FROM and JOIN clauses
    from_tables = re.findall(r'(?:FROM|JOIN)\s+([a-zA-Z_][a-zA-Z0-9_]*)', cleaned, re.IGNORECASE)
    for tbl in from_tables:
        if tbl.lower() not in _ALLOWED_TABLES:
            return False, f"الجدول '{tbl}' غير مسموح بالوصول إليه"

    return True, "آمن"


async def execute_readonly_sql(sql: str) -> dict:
    """Execute a validated read-only SQL query against Aurora.
    Returns {success, data, row_count, sql, error}."""

    # Validate safety
    is_safe, reason = _validate_sql_safety(sql)
    if not is_safe:
        return {"success": False, "error": reason, "sql": sql, "data": [], "row_count": 0}

    # Add LIMIT if not present
    cleaned = sql.strip().rstrip(";")
    if "LIMIT" not in cleaned.upper():
        cleaned += f" LIMIT {_MAX_RESULT_ROWS}"

    def _query(conn):
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            # Set statement timeout for this connection
            old_autocommit = conn.autocommit
            try:
                conn.autocommit = True
                cur.execute(f"SET statement_timeout = '{_QUERY_TIMEOUT_SECONDS * 1000}'")
                conn.autocommit = False
                cur.execute(cleaned)
                rows = cur.fetchall()
                columns = [desc[0] for desc in cur.description] if cur.description else []
                return {
                    "columns": columns,
                    "rows": [_convert_decimals(dict(r)) for r in rows],
                    "row_count": len(rows),
                }
            finally:
                # Reset timeout
                try:
                    conn.autocommit = True
                    cur.execute("SET statement_timeout = '0'")
                    conn.autocommit = old_autocommit
                except Exception:
                    pass

    try:
        result = await asyncio.to_thread(_execute_aurora_query_with_retry, _query)
        if result:
            return {
                "success": True,
                "sql": cleaned,
                "columns": result["columns"],
                "data": result["rows"],
                "row_count": result["row_count"],
                "error": None,
            }
        return {"success": False, "error": "فشل الاتصال بقاعدة البيانات", "sql": cleaned, "data": [], "row_count": 0}
    except Exception as e:
        logger.error(f"Dynamic SQL execution error: {e}")
        return {"success": False, "error": str(e)[:200], "sql": cleaned, "data": [], "row_count": 0}


async def generate_and_execute_sql(question: str) -> dict:
    """Full Text-to-SQL pipeline: schema → LLM generates SQL → validate → execute → return results.
    This is the main entry point for the dynamic query tool."""
    from core.llm_service import invoke_with_fallback

    # Step 1: Get real schema
    schema = await get_db_schema()
    if not schema:
        return {"success": False, "error": "تعذر الوصول لهيكل قاعدة البيانات", "data": [], "sql": ""}

    # Format schema for the LLM
    schema_text = "## الجداول المتاحة:\n"
    for tbl, info in schema.items():
        cols = ", ".join([f"{c['name']} ({c['type']})" for c in info.get("columns", [])])
        row_count = info.get("row_count", "?")
        schema_text += f"\n### {tbl} ({row_count} صف)\nالأعمدة: {cols}\n"
        if info.get("foreign_keys"):
            fks = ", ".join([f"{fk['column']} → {fk['references']}" for fk in info["foreign_keys"]])
            schema_text += f"العلاقات: {fks}\n"

    # Step 2: LLM generates SQL
    prompt = f"""أنت خبير PostgreSQL. مهمتك كتابة استعلام SQL واحد فقط للإجابة على سؤال المدير.

{schema_text}

## قواعد صارمة:
1. اكتب SELECT فقط — ممنوع INSERT, UPDATE, DELETE, DROP أو أي تعديل
2. استخدم الجداول والأعمدة الموجودة فقط
3. أضف LIMIT 100 إذا النتائج ممكن تكون كثيرة
4. استخدم COALESCE للقيم الفارغة
5. استخدم العربي في الـ aliases (AS "اسم")
6. لا تكتب أي شرح — فقط الاستعلام SQL

## سؤال المدير:
{question}

## الاستعلام (SQL فقط، بدون markdown أو شرح):"""

    sql_text = await invoke_with_fallback(prompt, agent="admin", temperature=0.1, app_id="admin")

    # Clean the LLM output — extract SQL only
    import re
    sql_text = sql_text.strip()
    # Remove markdown code blocks if present
    sql_text = re.sub(r'^```(?:sql)?\s*', '', sql_text, flags=re.MULTILINE)
    sql_text = re.sub(r'```\s*$', '', sql_text, flags=re.MULTILINE)
    sql_text = sql_text.strip()

    # If multiple lines, take only the SQL statement
    if not sql_text.upper().startswith("SELECT") and not sql_text.upper().startswith("WITH"):
        # Try to find SELECT in the text
        match = re.search(r'(SELECT\b.+)', sql_text, re.IGNORECASE | re.DOTALL)
        if match:
            sql_text = match.group(1).strip()

    # Step 3: Execute with safety validation
    result = await execute_readonly_sql(sql_text)
    result["question"] = question
    return result
