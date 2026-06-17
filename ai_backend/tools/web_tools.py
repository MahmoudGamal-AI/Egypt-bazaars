"""
Web Search Tools using Tavily API.
✅ MED-01: Tavily calls wrapped in asyncio.to_thread (non-blocking)
✅ MED-02: Shared logic extracted into _do_tavily_search (no tool-calling-tool)
"""
import asyncio
from langchain_core.tools import tool
from config import TAVILY_API_KEY


async def _do_tavily_search(query: str, max_results: int = 5) -> dict:
    """MED-02: Shared Tavily search logic — called by both tools directly."""
    def _sync_search():
        from tavily import TavilyClient
        client = TavilyClient(api_key=TAVILY_API_KEY)
        return client.search(
            query=query,
            search_depth="advanced",
            max_results=max_results,
            include_answer=True,
        )
    # MED-01: Run sync Tavily call in thread pool to avoid blocking event loop
    return await asyncio.to_thread(_sync_search)


def _format_tavily_response(response: dict) -> str:
    """Format Tavily response into readable text."""
    answer = response.get("answer", "")
    results = response.get("results", [])

    output = ""
    if answer:
        output += f"📝 الإجابة: {answer}\n\n"

    if results:
        output += "📚 المصادر:\n"
        for r in results[:3]:
            output += f"- {r.get('title', '')}: {r.get('content', '')[:200]}...\n"
            output += f"  🔗 {r.get('url', '')}\n"

    return output or "لم يتم العثور على نتائج."


@tool
async def web_search(query: str, topic: str = "general") -> str:
    """Search the web for information about Egyptian history, artifacts, or tourism.
    Use this when local knowledge base doesn't have enough information."""
    try:
        response = await _do_tavily_search(f"Egyptian history tourism {query}")
        return _format_tavily_response(response)
    except Exception as e:
        return f"⚠️ خطأ في البحث: {str(e)}"


@tool
async def web_search_egyptian_history(query: str) -> str:
    """Search specifically for Egyptian history and archaeology information."""
    try:
        # MED-02: Direct call to shared logic instead of tool.ainvoke()
        response = await _do_tavily_search(f"Ancient Egypt pharaoh archaeology {query}")
        return _format_tavily_response(response)
    except Exception as e:
        return f"⚠️ خطأ في البحث: {str(e)}"


@tool
async def web_extract_url(url: str) -> str:
    """Extract and read content from a specific web URL."""
    try:
        def _sync_extract():
            from tavily import TavilyClient
            client = TavilyClient(api_key=TAVILY_API_KEY)
            return client.extract(urls=[url])

        # MED-01: Non-blocking
        response = await asyncio.to_thread(_sync_extract)
        results = response.get("results", [])
        if results:
            return results[0].get("raw_content", "")[:2000]
        return "لم يتم استخراج محتوى."
    except Exception as e:
        return f"⚠️ خطأ: {str(e)}"


WEB_TOOLS = [web_search, web_search_egyptian_history, web_extract_url]
