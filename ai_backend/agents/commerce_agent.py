"""
🛍️ Commerce Agent — وكيل التجارة الموحد
يجمع بين البحث عن المنتجات (Product) وإدارة السلة (Cart) لأقصى سرعة
✅ يستخدم Tool Calling لعمليات المتجر والسلة
✅ يكتب ويقرأ current_viewed_items من הـ State مباشرة (Context Hand-off)
"""
import re
import asyncio
from graph.state import AgentState

from prompts.agent_prompts import COMMERCE_AGENT_PROMPT
from tools.all_tools import PRODUCT_TOOLS, CART_TOOLS, BAZAAR_TOOLS
from agents.tool_executor import run_agent_with_tools
from langchain_core.messages import AIMessage
from rag.engine import search_knowledge
from models.structured_output import ProductCard, CartActionResult, CartActionType, BazaarCard, ArtifactCard

# دمج كل أدوات التجارة والسلة والبازارات
COMMERCE_TOOLS = PRODUCT_TOOLS + CART_TOOLS + BAZAAR_TOOLS

_CRUD_KEYWORDS = [
    "أضف", "ضيف", "حط", "سلة", "احذف", "شيل", "كم", "سعر",
    "أعرض", "عرض", "قارن", "add", "remove", "cart", "compare", "show",
]

def _needs_rag(message: str) -> bool:
    """هل السؤال محتاج RAG؟ أسئلة المعلومات = True، عمليات السلة والأسعار = False."""
    msg_lower = message.lower()
    crud_count = sum(1 for kw in _CRUD_KEYWORDS if kw in msg_lower)
    return crud_count == 0

def _extract_all_cards_from_text(text: str) -> list:
    """Extract Product, Bazaar, and Artifact cards from tool output text."""
    cards = []
    id_matches = list(re.finditer(r'\[ID:(.*?)\]', text))
    if not id_matches:
        return cards
        
    for idx, match in enumerate(id_matches, 1):
        item_id = match.group(1).strip()
        if not item_id: continue

        start_pos = id_matches[idx - 2].end() if idx > 1 else 0
        section = text[start_pos:match.start()]
        
        # Artifact Card
        if '🏺' in section:
            name_match = re.search(r'\*\*([^*]+)\*\*', section)
            name_ar = name_match.group(1).strip() if name_match else f"أثر {idx}"
            
            era_match = re.search(r'العصر:\s*([^\n—-]+)', section)
            era = era_match.group(1).strip() if era_match else ""
            
            loc_match = re.search(r'الموقع:\s*([^\n—-]+)', section)
            loc = loc_match.group(1).strip() if loc_match else ""
            
            try:
                cards.append(ArtifactCard(artifact_id=item_id, name_ar=name_ar, era=era, location=loc))
            except Exception:
                pass
                
        # Bazaar Card
        elif '🏪' in section and 'السعر:' not in section:
            name_match = re.search(r'\*\*([^*]+)\*\*', section)
            name_ar = name_match.group(1).strip() if name_match else f"بازار {idx}"
            
            addr_match = re.search(r'📍\s*(?:العنوان:)?\s*([^\n—-]+)', section)
            addr = addr_match.group(1).strip() if addr_match else ""
            
            is_open = 'مفتوح ✅' in section
            
            try:
                cards.append(BazaarCard(bazaar_id=item_id, name_ar=name_ar, address=addr, is_open=is_open))
            except Exception:
                pass
                
        # Product Card
        else:
            name_match = re.search(r'\*\*([^*]+)\*\*', section)
            name_ar = name_match.group(1).strip() if name_match else f"منتج {idx}"
            
            price_match = re.search(r'(\d+(?:\.\d+)?)\s*(?:جنيه|ج\b)', section)
            price = float(price_match.group(1)) if price_match else 0.0
            
            cat_match = re.search(r'القسم:\s*([^\n—-]+)', section)
            category = cat_match.group(1).strip() if cat_match else ""
            
            img_match = re.search(r'!\[.*?\]\(([^)]+)\)', section)
            image_url = img_match.group(1).strip() if img_match else ""
            
            try:
                cards.append(ProductCard(
                    index=idx, product_id=item_id, name_ar=name_ar, price=price,
                    category=category, image_url=image_url
                ))
            except Exception:
                pass
                
    return cards

async def run_commerce_agent(state: AgentState) -> dict:
    """تشغيل الوكيل التجاري (يجمع بحث المنتجات + إدارة السلة)."""
    messages = state.get("messages", [])
    last_msg = messages[-1].content if messages else ""
    session_id = state.get("session_id", "default")
    user_id = state.get("user_id", "default")
    chat_history = state.get("chat_history", [])

    extra_parts = []

    # 1. Context Hand-off: قراءة المنتجات المعروضة (حتى لو لسه معروضة دلوقتي)
    viewed_items = state.get("current_viewed_items", [])
    if viewed_items:
        items_lines = []
        for item in viewed_items:
            idx = item.get("index", 0)
            name = item.get("name_ar", "منتج")
            pid = item.get("product_id", "")
            items_lines.append(f" {idx}. {name} (ID: {pid})")
        extra_parts.append(
            f"\n\n🔗 المنتجات التي تم عرضها أو الحديث عنها مؤخراً:\n" + "\n".join(items_lines) +
            f"\n\nالقاعدة: استخدم הـ ID الخاص بالمنتج مباشرة إذا أشار له المستخدم (الأول، التاني، ده)."
        )

    # 2. معلومات أساسية وأمان السلة
    extra_parts.append(f"\n⚠️ User ID الحالي: \"{user_id}\" - ضروري لأي عملية سلة.")

    # 3. RAG 
    if _needs_rag(last_msg):
        try:
            rag_context = await asyncio.wait_for(search_knowledge(f"منتجات {last_msg}"), timeout=10.0)
            rag_str = str(rag_context)
            if len(rag_str) > 2500:
                rag_str = rag_str[:2500] + "..."
            extra_parts.append(f"\n\n--- قاعدة المعرفة (منتجات) ---\n{rag_str}")
        except Exception:
            pass

    # 4. التفضيلات
    prefs = state.get("user_preferences", {})
    if prefs.get("favorite_categories"):
        extra_parts.append("\nالعميل يفضل: " + ", ".join(prefs["favorite_categories"][:3]))

    # الموقع الجغرافي
    lat = state.get("latitude")
    lng = state.get("longitude")
    if lat and lng:
        extra_parts.append(f"\n📍 الموقع الحالي للمستخدم (Latitude: {lat}, Longitude: {lng}). يمكنك استخدام هذه الإحداثيات عند البحث عن الأماكن القريبة.")

    # تجميع السياق
    extra_context = "".join(extra_parts)

    try:
        response, final_messages = await run_agent_with_tools(
            system_prompt=COMMERCE_AGENT_PROMPT,
            user_message=last_msg,
            tools=COMMERCE_TOOLS,
            context=extra_context,
            chat_history=chat_history,
            session_id=session_id,
            user_id=user_id,
            agent_name="commerce_agent"
        )
    except Exception as e:
        print(f"❌ Commerce Agent Error: {e}")
        response = "عذراً، حدث خطأ أثناء الاتصال بالمنتجات أو السلة."
        final_messages = []

    tool_outputs_text = "\n".join([str(msg.get("content", "")) if isinstance(msg, dict) else getattr(msg, "content", "") for msg in final_messages if (isinstance(msg, dict) and msg.get("type") == "tool") or getattr(msg, "type", "") == "tool"])
    
    new_cards = _extract_all_cards_from_text(tool_outputs_text)
    
    viewed_items_dicts = []
    rich_cards = []
    
    if new_cards:
        # Keep only the models that have to_rich_card
        for c in new_cards:
            if hasattr(c, "model_dump"):
                viewed_items_dicts.append(c.model_dump())
            if hasattr(c, "to_rich_card"):
                rich_cards.append(c.to_rich_card())

    return {
        "agent_output": response,
        "current_agent": "commerce_agent",
        "current_viewed_items": viewed_items_dicts,
        "last_search_query": last_msg,
        "cards": rich_cards,
        "messages": [AIMessage(content=response, name="commerce_agent")],
    }
