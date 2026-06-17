"""
⚡ Smart Cache Service — تخزين ذكي للأسئلة المتكررة
✅ MED-03: Two-tier cache — user-specific for cart/personal queries, shared for general queries
"""
import hashlib
import time
from collections import OrderedDict

# ============================================================
# إعدادات الـ Cache
# ============================================================
CACHE_MAX_SIZE = 500         # حد أقصى 500 إدخال
CACHE_TTL_SECONDS = 3600     # صلاحية ساعة واحدة

# MED-03: Cart/personal keywords that must NOT be shared across users
_USER_SPECIFIC_KEYWORDS = {
    "سلة", "cart", "عربة", "كوبون", "coupon", "خصم",
    "طلبي", "طلباتي", "حسابي", "orders", "my order",
    "تفضيلاتي", "اقتراحات لي", "يناسبني", "على ذوقي",
    "preferences", "for me", "personalized",
}


class SmartCache:
    """MED-03: Two-tier cache — user-specific + shared.
    
    - Cart/personal queries → keyed by (user_id, message) — never served to other users
    - General queries (history, tourism, products) → shared across users for max hit rate
    """

    def __init__(self, max_size: int = CACHE_MAX_SIZE, ttl: int = CACHE_TTL_SECONDS):
        self._shared_cache: OrderedDict[str, dict] = OrderedDict()
        self._user_cache: OrderedDict[str, dict] = OrderedDict()
        self._max_size = max_size
        self._max_user_size = max_size // 2  # User cache is smaller
        self._ttl = ttl
        self._hits = 0
        self._misses = 0

    def _is_user_specific(self, message: str) -> bool:
        """MED-03: Determine if a query is user-specific (cart, orders, preferences)."""
        msg_lower = message.lower()
        return any(kw in msg_lower for kw in _USER_SPECIFIC_KEYWORDS)

    def _hash_key(self, message: str, user_id: str = "") -> str:
        """إنشاء hash للرسالة بعد تنظيفها."""
        cleaned = message.strip().lower()
        for ch in "؟?!.،,":
            cleaned = cleaned.replace(ch, "")
        cleaned = " ".join(cleaned.split())
        combined = f"{user_id}:{cleaned}" if user_id else cleaned
        return hashlib.md5(combined.encode()).hexdigest()

    def get(self, message: str, user_id: str = "") -> dict | None:
        """MED-03: Two-tier lookup — user cache first for personal queries, then shared."""
        is_personal = self._is_user_specific(message)

        # Tier 1: User-specific cache for personal queries
        if is_personal and user_id:
            key = self._hash_key(message, user_id)
            result = self._lookup(self._user_cache, key)
            if result is not None:
                return result
            # Personal queries should NOT fall through to shared cache
            self._misses += 1
            return None

        # Tier 2: Shared cache for general queries
        key = self._hash_key(message)  # No user_id = shared key
        result = self._lookup(self._shared_cache, key)
        if result is not None:
            return result

        self._misses += 1
        return None

    def set(self, message: str, data: dict, user_id: str = ""):
        """MED-03: Store in the appropriate tier."""
        is_personal = self._is_user_specific(message)

        if is_personal and user_id:
            key = self._hash_key(message, user_id)
            self._store(self._user_cache, key, data, user_id, self._max_user_size)
        else:
            key = self._hash_key(message)
            self._store(self._shared_cache, key, data, user_id, self._max_size)

    def _lookup(self, cache: OrderedDict, key: str) -> dict | None:
        """Internal lookup with TTL check."""
        if key not in cache:
            return None

        entry = cache[key]
        if time.time() - entry["timestamp"] > self._ttl:
            del cache[key]
            return None

        cache.move_to_end(key)
        self._hits += 1
        return entry["data"]

    def _store(self, cache: OrderedDict, key: str, data: dict, user_id: str, max_size: int):
        """Internal store with LRU eviction."""
        if key in cache:
            cache.move_to_end(key)
            cache[key] = {"data": data, "timestamp": time.time(), "user_id": user_id}
            return

        while len(cache) >= max_size:
            cache.popitem(last=False)

        cache[key] = {"data": data, "timestamp": time.time(), "user_id": user_id}

    def invalidate(self, user_id: str):
        """مسح كل الـ cache الخاص بمستخدم معين."""
        for cache in (self._user_cache, self._shared_cache):
            keys_to_delete = [
                k for k, v in cache.items() if v.get("user_id") == user_id
            ]
            for k in keys_to_delete:
                del cache[k]

    def clear(self):
        """مسح كل الـ cache."""
        self._shared_cache.clear()
        self._user_cache.clear()
        self._hits = 0
        self._misses = 0

    @property
    def stats(self) -> dict:
        """إحصائيات الـ cache."""
        total = self._hits + self._misses
        hit_rate = (self._hits / total * 100) if total > 0 else 0
        return {
            "shared_size": len(self._shared_cache),
            "user_size": len(self._user_cache),
            "total_size": len(self._shared_cache) + len(self._user_cache),
            "max_size": self._max_size,
            "hits": self._hits,
            "misses": self._misses,
            "hit_rate": f"{hit_rate:.1f}%",
        }


# Singleton instance
_cache = SmartCache()


def get_cache() -> SmartCache:
    """الحصول على instance الـ cache."""
    return _cache
