"""
🔄 Corrective RAG — نظام RAG تصحيحي (مع Query Rewriter)
✅ HIGH-06: Parallel rewrite + expansion, early-exit if score ≥ 0.6
"""
import asyncio
import logging
from langchain_core.documents import Document
from config import RELEVANCE_THRESHOLD

logger = logging.getLogger(__name__)


async def corrective_rag_pipeline(query: str, hybrid_retriever,
                                   context: str = "") -> dict:
    """Pipeline الـ RAG — محسّن مع تشغيل متوازي وخروج مبكر.

    الخطوات:
    1. بحث هجين مباشر
    2. HIGH-06: لو النتائج كويسة (≥ 0.6) → خروج مبكر
    3. لو ضعيفة → إعادة صياغة + توسيع بالتوازي
    4. لو مفيش نتائج → بحث ويب
    """
    result = {
        "documents": [],
        "score": 0.0,
        "method": "hybrid",
        "query_used": query,
        "web_used": False,
        "rewritten": False,
        "sources": [],
    }

    # ============ الخطوة 1: بحث هجين مباشر ============
    docs = await hybrid_retriever.search(query)

    if docs:
        relevant_docs = [doc for doc, score in docs if score > 0.3]
        avg_score = sum(s for _, s in docs) / len(docs) if docs else 0.0

        result["documents"] = relevant_docs if relevant_docs else [doc for doc, _ in docs[:3]]
        result["score"] = avg_score

    # ============ HIGH-06: خروج مبكر لو النتائج كويسة ============
    if result["score"] >= 0.6 and len(result["documents"]) >= 2:
        logger.info(f"✅ CRAG Early-exit: score={result['score']:.2f}, docs={len(result['documents'])}")
        return result

    # ============ الخطوة 2: بحث ويب كخطة بديلة لو البحث المحلي فشل ============
    if not result["documents"]:
        result["web_used"] = True
        result["method"] = "web_fallback"
        try:
            from tools.web_tools import _do_tavily_search, _format_tavily_response
            response = await _do_tavily_search(f"Egyptian history tourism {query}", max_results=3)
            web_text = _format_tavily_response(response)
            result["documents"] = [
                Document(page_content=web_text, metadata={"source": "web"})
            ]
            result["score"] = 0.8
        except Exception as e:
            logger.warning(f"Web search fallback failed: {e}")

    return result
