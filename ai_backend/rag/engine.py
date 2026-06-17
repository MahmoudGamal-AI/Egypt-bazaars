"""
🚀 RAG Engine (Serverless Optimized)
يعتمد حصرياً على AWS Aurora pgvector لسرعة الأداء.
بدون استهلاك للذاكرة أو بطء في إقلاع الـ Lambda (Zero Cold Start).
"""
import asyncio
import logging
from services.gemini_service import get_embeddings
from memory.aws_memory import search_knowledge_pgvector
from langchain_core.documents import Document
from config import TOP_K_RESULTS
from rag.corrective_rag import corrective_rag_pipeline

logger = logging.getLogger(__name__)

class ServerlessRetriever:
    """Retriever وهمي يحاكي الـ HybridRetriever القديم، لكنه متصل بـ pgvector فوراً"""
    @property
    def is_ready(self) -> bool:
        # قاعدة البيانات دائماً جاهزة بإذن الله
        return True
        
    async def search(self, query: str, top_k: int = TOP_K_RESULTS) -> list[tuple[Document, float]]:
        embedder = get_embeddings()
        try:
            # تحويل النص لـ Vector واستدعاء Aurora عبر aws_memory
            embedding: list[float] = await embedder.aembed_query(query)
            # CRIT-01 Fix: Run sync DB query in thread pool to avoid blocking the event loop
            results = await asyncio.to_thread(search_knowledge_pgvector, embedding, top_k)
            return [
                (Document(page_content=str(r["content"]), metadata={"source": r["source"]}), float(r["score"]))
                for r in results
            ]
        except Exception as e:
            logger.warning(f"pgvector search error: {e}")
            return []

# Singleton instance
_retriever = ServerlessRetriever()

async def initialize_rag():
    """في بيئة الـ Serverless لا نحتاج لتهيئة (In-Memory). البيانات في Aurora أصلاً!"""
    logger.info("RAG engine initialized (Serverless Native Aurora pgvector)")

def get_hybrid_retriever() -> ServerlessRetriever:
    return _retriever

async def search_knowledge(query: str, context: str = "") -> str:
    """نقطة الدخول الرئيسية للبحث في قاعدة المعرفة — يستخدمها الوكلاء."""
    if not _retriever.is_ready:
        return "⚠️ نظام RAG غير متصل."

    # استخدام الـ Corrective RAG (CRAG) كالسابق للتقييم والبحث في الويب إن لزم
    result = await corrective_rag_pipeline(query, _retriever, context)

    if not result["documents"]:
        return "لم يتم العثور على معلومات ذات صلة."

    docs_text = "\n\n".join([
        doc.page_content for doc in result["documents"][:TOP_K_RESULTS]
    ])

    info = f"📖 طريقة البحث: {result['method']} (Aurora pgvector)"
    if result["web_used"]:
        info += " (تم استخدام بحث الويب للطوارئ)"

    return f"{info}\n📊 درجة الارتباط: {result['score']:.1f}\n\n{docs_text}"

async def incremental_update(documents: list) -> None:
    """LOW-04: Not implemented in serverless architecture.
    
    In production, document ingestion is handled by an S3 Event Trigger
    that invokes a separate Lambda function to embed and store in pgvector.
    This function exists for interface compatibility only.
    """
    raise NotImplementedError(
        "incremental_update is not available in serverless mode. "
        "Use the S3 trigger-based ingestion pipeline instead."
    )
