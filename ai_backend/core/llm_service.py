"""
🤖 Core LLM Service — Shared LLM access for all microservices.
Supports: Groq (primary) + Gemini (fallback) with per-app API key routing.
"""
import asyncio
import logging
import random
from typing import Any, Optional
from core.config import (
    GEMINI_API_KEY, GEMINI_MODEL, GEMINI_EMBEDDING_MODEL,
    GROQ_API_KEY, GROQ_API_KEY_OWNER, GROQ_API_KEY_ADMIN,
    TOURIST_GROQ_API_KEYS,
    GROQ_MODEL, GROQ_FAST_MODEL, LLM_PROVIDER, LLM_TIMEOUT,
)

logger = logging.getLogger(__name__)

# ============================================================
# Emergency Responses — Last line of defense
# ============================================================
EMERGENCY_RESPONSES = {
    "admin": "عذراً، النظام مشغول. جرّب تاني بعد لحظات.",
    "owner": "عذراً، مش قادر أوصل للبيانات دلوقتي. جرّب تاني.",
    "default": "عذراً، حدث خطأ مؤقت. جرّب تاني بعد شوية! 🙏",
}

# ============================================================
# LLM Instance Cache
# ============================================================
_llm_cache: dict[str, Any] = {}


def _get_groq_key_for_app(app_id: str) -> str | None:
    """Route to the correct Groq API key based on the app."""
    if app_id == "admin":
        return GROQ_API_KEY_ADMIN or GROQ_API_KEY
    if app_id == "owner":
        return GROQ_API_KEY_OWNER or GROQ_API_KEY
    # Tourist uses round-robin across multiple keys
    if TOURIST_GROQ_API_KEYS:
        return random.choice(TOURIST_GROQ_API_KEYS)
    return GROQ_API_KEY


def _build_groq_llm(model: str, temperature: float, app_id: str, timeout: Optional[float] = None):
    """Build a Groq LLM instance with proper config."""
    from langchain_groq import ChatGroq
    return ChatGroq(
        model=model,
        api_key=_get_groq_key_for_app(app_id),
        temperature=temperature,
        max_tokens=2048,
        max_retries=2,
        timeout=timeout or LLM_TIMEOUT,
    )


def _build_gemini_llm(temperature: float):
    """Build a Gemini LLM instance."""
    from langchain_google_genai import ChatGoogleGenerativeAI
    return ChatGoogleGenerativeAI(
        model=GEMINI_MODEL,
        google_api_key=GEMINI_API_KEY,
        temperature=temperature,
        convert_system_message_to_human=False,
    )


def get_llm(temperature: float = 0.7, app_id: str = "tourist"):
    """Get LLM instance — Groq or Gemini based on config (cached per app+temp)."""
    # Fix: Do not cache if we need round-robin key rotation
    disable_cache = LLM_PROVIDER == "groq" and app_id == "tourist" and len(TOURIST_GROQ_API_KEYS) > 1
    
    cache_key = f"{LLM_PROVIDER}_{temperature}_{app_id}"
    if not disable_cache and cache_key in _llm_cache:
        return _llm_cache[cache_key]

    if LLM_PROVIDER == "groq":
        instance = _build_groq_llm(GROQ_MODEL, temperature, app_id)
    else:
        instance = _build_gemini_llm(temperature)

    if not disable_cache:
        _llm_cache[cache_key] = instance
    return instance


def get_fast_llm(temperature: float = 0.7, app_id: str = "tourist"):
    """Get fast LLM — smaller model for routing/evaluation tasks."""
    # Fix: Do not cache if we need round-robin key rotation
    disable_cache = LLM_PROVIDER == "groq" and app_id == "tourist" and len(TOURIST_GROQ_API_KEYS) > 1

    cache_key = f"fast_{LLM_PROVIDER}_{temperature}_{app_id}"
    if not disable_cache and cache_key in _llm_cache:
        return _llm_cache[cache_key]

    if LLM_PROVIDER != "groq":
        instance = get_llm(temperature=temperature, app_id=app_id)
        if not disable_cache:
            _llm_cache[cache_key] = instance
        return instance

    instance = _build_groq_llm(GROQ_FAST_MODEL, temperature, app_id, timeout=15.0)
    if not disable_cache:
        _llm_cache[cache_key] = instance
    return instance


def _get_gemini_fallback(temperature: float = 0.7):
    """Get Gemini as fallback — regardless of primary provider."""
    cache_key = f"gemini_fallback_{temperature}"
    if cache_key in _llm_cache:
        return _llm_cache[cache_key]

    instance = _build_gemini_llm(temperature)
    _llm_cache[cache_key] = instance
    return instance


def clear_llm_cache():
    """Clear the LLM cache — useful when API keys change at runtime."""
    _llm_cache.clear()
    logger.info("LLM cache cleared")


# ============================================================
# Fallback Chain — Primary → Gemini → Emergency
# ============================================================

async def invoke_with_fallback(prompt, agent: str = "default",
                                temperature: float = 0.7,
                                timeout: Optional[float] = None,
                                app_id: str = "admin") -> str:
    """Invoke LLM with Fallback Chain: Primary → Gemini → Emergency response."""
    effective_timeout = timeout or LLM_TIMEOUT

    # Attempt 1: Primary provider (with 2 internal retries)
    for attempt in range(2):
        try:
            llm = get_llm(temperature=temperature, app_id=app_id)
            result = await asyncio.wait_for(llm.ainvoke(prompt), timeout=effective_timeout)
            return str(result.content) if not isinstance(result.content, str) else result.content
        except asyncio.TimeoutError:
            logger.warning(f"Primary LLM timeout (attempt {attempt + 1})")
        except Exception as e:
            if "rate limit" in str(e).lower() or "429" in str(e):
                logger.warning(f"Rate limit hit on attempt {attempt + 1}. Key rotation triggered.")
                # By immediately retrying, get_llm() will now pick a new random key because cache is disabled
            if attempt == 1:
                logger.warning(f"Primary LLM failed after 2 attempts: {e}")
            else:
                await asyncio.sleep(1)

    # Attempt 2: Gemini fallback
    if GEMINI_API_KEY and LLM_PROVIDER != "gemini":
        try:
            gemini = _get_gemini_fallback(temperature)
            result = await asyncio.wait_for(gemini.ainvoke(prompt), timeout=effective_timeout)
            logger.info("Gemini fallback succeeded")
            return str(result.content) if not isinstance(result.content, str) else result.content
        except Exception as e:
            logger.warning(f"Gemini fallback failed: {e}")

    # Attempt 3: Emergency response
    logger.warning("All LLM providers failed — using emergency response")
    return EMERGENCY_RESPONSES.get(agent, EMERGENCY_RESPONSES["default"])


# ============================================================
# Embeddings
# ============================================================

def get_embeddings():
    """Get Gemini embeddings instance (always Gemini)."""
    cache_key = "embeddings_doc"
    if cache_key in _llm_cache:
        return _llm_cache[cache_key]

    from langchain_google_genai import GoogleGenerativeAIEmbeddings
    instance = GoogleGenerativeAIEmbeddings(
        model=GEMINI_EMBEDDING_MODEL,
        google_api_key=GEMINI_API_KEY,
        task_type="retrieval_document",
    )
    _llm_cache[cache_key] = instance
    return instance


def get_query_embeddings():
    """Get Gemini embeddings for queries."""
    cache_key = "embeddings_query"
    if cache_key in _llm_cache:
        return _llm_cache[cache_key]

    from langchain_google_genai import GoogleGenerativeAIEmbeddings
    instance = GoogleGenerativeAIEmbeddings(
        model=GEMINI_EMBEDDING_MODEL,
        google_api_key=GEMINI_API_KEY,
        task_type="retrieval_query",
    )
    _llm_cache[cache_key] = instance
    return instance
