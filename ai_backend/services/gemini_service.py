"""
Egyptian Tourism AI Backend - LLM & Embeddings Service
يدعم Groq و Gemini — مع Fallback Chain ذكي + Singleton Caching + Async Fallback
"""
import asyncio
import logging
from typing import Any
from functools import lru_cache
from config import (
    GEMINI_API_KEY, GEMINI_MODEL, GEMINI_EMBEDDING_MODEL,
    GROQ_API_KEY, GROQ_API_KEY_OWNER, GROQ_API_KEY_ADMIN,
    TOURIST_GROQ_API_KEYS,
    GROQ_MODEL, GROQ_FAST_MODEL, LLM_PROVIDER,
)
import random

logger = logging.getLogger(__name__)

# ============================================================
# ردود مخزنة للطوارئ — آخر خط دفاع
# ============================================================
EMERGENCY_RESPONSES = {
    "history_agent": "عذراً، النظام مشغول حالياً. لكن أقدر أقولك إن مصر فيها أكتر من 7000 سنة تاريخ مذهل! جرّب تاني بعد شوية وهحكيلك كل حاجة 😊",
    "product_agent": "عذراً، مش قادر أوصل للمنتجات دلوقتي. بس تقدر تتصفح المنتجات في الابليكيشن مباشرة! جرّب تاني بعد شوية 🛍️",
    "tour_guide_agent": "عذراً، النظام مشغول. بس نصيحتي: ابدأ بأهرامات الجيزة والمتحف المصري الكبير — دول لازم يتزاروا! 🏛️",
    "cart_agent": "عذراً، مش قادر أعالج طلب السلة دلوقتي. جرّب تاني بعد شوية! 🛒",
    "general_agent": "عذراً، النظام مشغول شوية. جرّب تاني بعد دقيقة وهكون جاهز أساعدك! 😊",
    "default": "عذراً، حدث خطأ مؤقت. جرّب تاني بعد شوية! 🙏",
}

# ============================================================
# LLM Instance Cache — بدل ما ننشئ instance جديد كل مرة
# CRIT-02 Fix: Tourist app with multiple Groq keys skips cache
#              so round-robin key rotation actually works.
# ============================================================
_llm_cache: dict[str, Any] = {}


def _has_multiple_tourist_keys(app_id: str) -> bool:
    """CRIT-02: Check if we should skip cache to enable Groq key rotation."""
    return (app_id == "tourist"
            and LLM_PROVIDER == "groq"
            and len(TOURIST_GROQ_API_KEYS) > 1)


def _get_groq_key_for_app(app_id: str) -> str:
    """الحصول على مفتاح الـ API المناسب بناءً على نوع التطبيق لتوزيع الأحمال."""
    if app_id == "admin":
        return GROQ_API_KEY_ADMIN or GROQ_API_KEY or ""
    if app_id == "owner":
        return GROQ_API_KEY_OWNER or GROQ_API_KEY or ""
    if TOURIST_GROQ_API_KEYS:
        return random.choice(TOURIST_GROQ_API_KEYS)
    return GROQ_API_KEY or ""


def get_llm(temperature: float = 0.7, app_id: str = "tourist"):
    """Get LLM instance — Groq أو Gemini حسب الإعدادات (مع caching).

    CRIT-02 Fix: Tourist app with multiple Groq keys uses api_key in cache_key
    to preserve connection pooling while still distributing load.
    """
    api_key = _get_groq_key_for_app(app_id)
    cache_key = f"{LLM_PROVIDER}_{temperature}_{app_id}_{api_key}"

    if cache_key in _llm_cache:
        return _llm_cache[cache_key]

    if LLM_PROVIDER == "groq":
        from langchain_groq import ChatGroq
        instance = ChatGroq(
            model=GROQ_MODEL,
            api_key=api_key,
            temperature=temperature,
            max_tokens=1024,
        )
    else:
        from langchain_google_genai import ChatGoogleGenerativeAI
        instance = ChatGoogleGenerativeAI(
            model=GEMINI_MODEL,
            google_api_key=GEMINI_API_KEY,
            temperature=temperature,
            convert_system_message_to_human=False,
        )

    _llm_cache[cache_key] = instance
    return instance


def get_fast_llm(temperature: float = 0.7, app_id: str = "tourist"):
    """Get fast LLM — نموذج أصغر وأسرع للمهام البسيطة (routing, evaluation)."""
    api_key = _get_groq_key_for_app(app_id)
    cache_key = f"fast_{LLM_PROVIDER}_{temperature}_{app_id}_{api_key}"

    if cache_key in _llm_cache:
        return _llm_cache[cache_key]

    if LLM_PROVIDER != "groq":
        instance = get_llm(temperature=temperature, app_id=app_id)
        _llm_cache[cache_key] = instance
        return instance

    from langchain_groq import ChatGroq
    from config import GROQ_FAST_MODEL
    instance = ChatGroq(
        model=GROQ_FAST_MODEL,
        temperature=temperature,
        api_key=_get_groq_key_for_app(app_id),
        max_tokens=1024,
        max_retries=2,
        timeout=15.0,
    )

    _llm_cache[cache_key] = instance
    return instance


def get_streaming_llm(temperature: float = 0.7, app_id: str = "tourist"):
    """Get streaming LLM — للردود المتدفقة chunk by chunk."""
    api_key = _get_groq_key_for_app(app_id)
    cache_key = f"stream_{LLM_PROVIDER}_{temperature}_{app_id}_{api_key}"

    if cache_key in _llm_cache:
        return _llm_cache[cache_key]

    if LLM_PROVIDER == "groq":
        from langchain_groq import ChatGroq
        instance = ChatGroq(
            model=GROQ_MODEL,
            api_key=_get_groq_key_for_app(app_id),
            temperature=temperature,
            max_tokens=1024,
            streaming=True,
        )
    else:
        from langchain_google_genai import ChatGoogleGenerativeAI
        instance = ChatGoogleGenerativeAI(
            model=GEMINI_MODEL,
            google_api_key=GEMINI_API_KEY,
            temperature=temperature,
            convert_system_message_to_human=False,
            streaming=True,
        )

    _llm_cache[cache_key] = instance
    return instance


def _get_gemini_fallback(temperature: float = 0.7):
    """الحصول على Gemini كـ fallback — بغض النظر عن الـ provider الأساسي."""
    cache_key = f"gemini_fallback_{temperature}"
    if cache_key in _llm_cache:
        return _llm_cache[cache_key]

    from langchain_google_genai import ChatGoogleGenerativeAI
    instance = ChatGoogleGenerativeAI(
        model=GEMINI_MODEL,
        google_api_key=GEMINI_API_KEY,
        temperature=temperature,
        convert_system_message_to_human=False,
    )
    _llm_cache[cache_key] = instance
    return instance


# ============================================================
# Fallback Chain — الآن async + يدعم messages list
# ============================================================

async def invoke_with_fallback(prompt, agent: str = "default",
                                temperature: float = 0.7,
                                timeout: float = 30.0) -> str:
    """استدعاء LLM مع Fallback Chain: Primary → Gemini → رد مخزن."""
    # === المحاولة 1: المزود الأساسي (مع محاولتين داخليتين) ===
    for attempt in range(2):
        try:
            llm = get_llm(temperature=temperature, app_id="tourist")
            result = await asyncio.wait_for(llm.ainvoke(prompt), timeout=timeout)
            return str(result.content)
        except Exception as e:
            if attempt == 1:
                logger.warning(f"Primary LLM failed after 2 attempts: {e}")
            else:
                await asyncio.sleep(1)

    # === المحاولة 2: Gemini كـ fallback ===
    if GEMINI_API_KEY and LLM_PROVIDER != "gemini":
        try:
            gemini = _get_gemini_fallback(temperature)
            result = await asyncio.wait_for(gemini.ainvoke(prompt), timeout=timeout)
            logger.info("Gemini fallback succeeded")
            return str(result.content)
        except Exception as e:
            logger.warning(f"Gemini fallback failed: {e}")

    # === المحاولة 3: رد مخزن (آخر خط دفاع) ===
    logger.warning("Using emergency response")
    return EMERGENCY_RESPONSES.get(agent, EMERGENCY_RESPONSES["default"])


async def invoke_llm_with_retry(prompt, temperature: float = 0.7,
                                 max_retries: int = 3,
                                 agent: str = "default") -> str:
    """استدعاء LLM مع retry + exponential backoff + fallback.

    أفضل من invoke_with_fallback لأنه يحاول نفس المزود أكثر من مرة قبل الـ fallback.
    """
    last_error = None

    for attempt in range(max_retries):
        try:
            llm = get_llm(temperature=temperature, app_id="tourist")
            timeout = 30.0 + (attempt * 10)  # timeout يزيد مع كل محاولة
            result = await asyncio.wait_for(llm.ainvoke(prompt), timeout=timeout)
            return str(result.content)
        except asyncio.TimeoutError:
            last_error = "timeout"
            logger.warning(f"LLM timeout (attempt {attempt + 1}/{max_retries})")
        except Exception as e:
            last_error = str(e)
            error_msg = str(e).lower()

            # Rate limit → انتظار أطول
            if "429" in error_msg or "rate" in error_msg or "quota" in error_msg:
                wait_time = 5 * (attempt + 1)
                logger.warning(f"Rate limited (attempt {attempt + 1}). Waiting {wait_time}s...")
                await asyncio.sleep(wait_time)
            else:
                # خطأ آخر → انتظار قصير
                await asyncio.sleep(1 * (attempt + 1))

    # كل المحاولات فشلت → fallback
    logger.error(f"All {max_retries} retries failed. Last error: {last_error}")
    return await invoke_with_fallback(prompt, agent=agent, temperature=temperature)


# ============================================================
# Embeddings
# ============================================================

def get_embeddings():
    """Get Gemini embeddings instance with manual truncation to 1536 to prevent pgvector dimension mismatch."""
    from langchain_google_genai import GoogleGenerativeAIEmbeddings
    
    class TruncatedEmbeddings(GoogleGenerativeAIEmbeddings):
        def embed_documents(self, texts: list[str], *args, **kwargs) -> list[list[float]]:
            embeddings = super().embed_documents(texts, *args, **kwargs)
            return [e[:1536] for e in embeddings]
        
        def embed_query(self, text: str, *args, **kwargs) -> list[float]:
            embedding = super().embed_query(text, *args, **kwargs)
            return embedding[:1536]
            
        async def aembed_documents(self, texts: list[str], *args, **kwargs) -> list[list[float]]:
            embeddings = await super().aembed_documents(texts, *args, **kwargs)
            return [e[:1536] for e in embeddings]
            
        async def aembed_query(self, text: str, *args, **kwargs) -> list[float]:
            embedding = await super().aembed_query(text, *args, **kwargs)
            return embedding[:1536]

    cache_key = "embeddings_doc_1536_trunc"
    if cache_key in _llm_cache:
        return _llm_cache[cache_key]

    instance = TruncatedEmbeddings(
        model=GEMINI_EMBEDDING_MODEL,
        google_api_key=GEMINI_API_KEY,
        task_type="retrieval_document",
    )
    _llm_cache[cache_key] = instance
    return instance


def get_query_embeddings():
    """Get Gemini query embeddings instance with manual truncation to 1536."""
    from langchain_google_genai import GoogleGenerativeAIEmbeddings
    
    class TruncatedQueryEmbeddings(GoogleGenerativeAIEmbeddings):
        def embed_documents(self, texts: list[str], *args, **kwargs) -> list[list[float]]:
            embeddings = super().embed_documents(texts, *args, **kwargs)
            return [e[:1536] for e in embeddings]
        
        def embed_query(self, text: str, *args, **kwargs) -> list[float]:
            embedding = super().embed_query(text, *args, **kwargs)
            return embedding[:1536]
            
        async def aembed_documents(self, texts: list[str], *args, **kwargs) -> list[list[float]]:
            embeddings = await super().aembed_documents(texts, *args, **kwargs)
            return [e[:1536] for e in embeddings]
            
        async def aembed_query(self, text: str, *args, **kwargs) -> list[float]:
            embedding = await super().aembed_query(text, *args, **kwargs)
            return embedding[:1536]

    cache_key = "embeddings_query_1536_trunc"
    if cache_key in _llm_cache:
        return _llm_cache[cache_key]

    instance = TruncatedQueryEmbeddings(
        model=GEMINI_EMBEDDING_MODEL,
        google_api_key=GEMINI_API_KEY,
        task_type="retrieval_query",
    )
    _llm_cache[cache_key] = instance
    return instance
