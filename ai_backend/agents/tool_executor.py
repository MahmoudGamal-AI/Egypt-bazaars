"""
🔧 Tool Executor — تنفيذ أدوات الوكلاء (ReAct Loop)
محسّن مع: retry logic, fallback chain, better error handling
✅ جديد: validation على tool args قبل التنفيذ لمنع التخريف
"""
import asyncio
from typing import Optional
from langchain_core.messages import HumanMessage, AIMessage, ToolMessage, SystemMessage
from services.gemini_service import get_llm, invoke_with_fallback
from config import MAX_TOOL_CALLS


# ============================================================
# Tool Argument Validation — يمنع التخريف
# ============================================================

_INVALID_IDS = frozenset({
    "default", "unknown", "null", "undefined", "none", "",
    "test", "example", "sample", "placeholder",
    "product_id", "user_id", "item_id",
})


def _validate_tool_args(tool_name: str, tool_args: dict) -> tuple[bool, str]:
    """فحص صلاحية الـ arguments قبل تنفيذ الأداة.

    Returns:
        (is_valid, error_message)
    """
    # --- add_to_cart: يجب أن يكون product_id موجود وحقيقي ---
    if tool_name == "add_to_cart":
        pid = str(tool_args.get("product_id", "")).strip().lower()
        if not pid or pid in _INVALID_IDS:
            return False, (
                "❌ product_id مفقود أو غير صالح. "
                "استخدم أداة search_products للبحث عن المنتج أولاً."
            )
        # IDs طويلة جداً أو قصيرة جداً → مريبة
        if len(pid) < 3 or len(pid) > 100:
            return False, f"❌ product_id '{pid}' يبدو غير صالح (طول غير معقول)."

    # --- remove_from_cart: يجب أن يكون item_index رقم موجب ---
    if tool_name == "remove_from_cart":
        idx = tool_args.get("item_index")
        if idx is None or (isinstance(idx, (int, float)) and idx < 1):
            return False, "❌ item_index يجب أن يكون رقم موجب (1 أو أكبر)."

    # --- get_product_details: يجب أن يكون product_id موجود ---
    if tool_name == "get_product_details":
        pid = str(tool_args.get("product_id", "")).strip().lower()
        if not pid or pid in _INVALID_IDS:
            return False, "❌ product_id مفقود. حدد معرّف المنتج."

    # --- compare_products: يجب أن يكون فيه 2 IDs مختلفة ---
    if tool_name == "compare_products":
        p1 = str(tool_args.get("product_id_1", "")).strip()
        p2 = str(tool_args.get("product_id_2", "")).strip()
        if not p1 or not p2:
            return False, "❌ مطلوب معرّفين مختلفين للمقارنة."
        if p1 == p2:
            return False, "❌ لا يمكن مقارنة منتج بنفسه."

    return True, ""


async def run_agent_with_tools(
    system_prompt: str,
    user_message: str,
    tools: list,
    context: str = "",
    chat_history: Optional[list] = None,
    session_id: str = "",
    user_id: str = "",
    temperature: float = 0.7,
    max_iterations: int = MAX_TOOL_CALLS,
    timeout: float = 25.0,
    agent_name: str = "agent",
) -> tuple[str, list]:
    """تشغيل الوكيل في حلقة ReAct مع أدوات — مع retry و fallback و validation.
    
    ✅ المحادثات السابقة متضمنة بالكامل لفهم السياق (Multi-turn).

    المسار:
    1. إرسال الرسالة + الأدوات للـ LLM
    2. لو الـ LLM قرر يستخدم أداة → نتحقق من الـ args ثم ننفذها
    3. لو الـ LLM رد نصياً → نرجع الرد
    4. لو حصل خطأ → retry ثم fallback
    """
    messages = []

    # بناء System Message
    full_prompt = system_prompt
    if context:
        full_prompt += f"\n\n📋 سياق:\n{context}"

    messages.append(SystemMessage(content=full_prompt))
    
    # NEW: إدراج الذاكرة السابقة حتى يفهم الوكيل الموضوع الذي يتحدث عنه المستخدم!
    if chat_history:
        # نأخذ آخر 4 رسائل عشان الـ token limit ميتخطاش الـ 8000 (TPM) لـ Groq
        messages.extend(chat_history[-4:])
        
    messages.append(HumanMessage(content=user_message))

    # ربط الأدوات بالـ LLM
    llm = get_llm(temperature=temperature)
    llm_with_tools = llm.bind_tools(tools) if tools else llm

    for iteration in range(max_iterations):
        try:
            # استدعاء LLM مع timeout
            response = await asyncio.wait_for(
                llm_with_tools.ainvoke(messages),
                timeout=timeout,
            )
        except asyncio.TimeoutError:
            print(f"⏰ [{agent_name}] Timeout (iteration {iteration + 1})")
            # retry مرة واحدة مع timeout أطول
            try:
                response = await asyncio.wait_for(
                    llm_with_tools.ainvoke(messages),
                    timeout=timeout + 15,
                )
            except Exception:
                fallback_text = await _fallback_response(system_prompt, user_message, context, agent_name)
                return fallback_text, messages
        except Exception as e:
            error_msg = str(e).lower()
            print(f"⚠️ [{agent_name}] LLM error: {e}")

            # Rate limit → انتظار ومحاولة
            if "429" in error_msg or "rate" in error_msg:
                await asyncio.sleep(3)
                try:
                    response = await asyncio.wait_for(
                        llm_with_tools.ainvoke(messages),
                        timeout=timeout + 10,
                    )
                except Exception:
                    fallback_text = await _fallback_response(system_prompt, user_message, context, agent_name)
                    return fallback_text, messages
            else:
                fallback_text = await _fallback_response(system_prompt, user_message, context, agent_name)
                return fallback_text, messages

        # === فحص هل فيه tool calls ===
        if hasattr(response, "tool_calls") and response.tool_calls:
            messages.append(response)

            fast_exit_results = []
            can_fast_exit = True
            FAST_EXIT_TOOLS = {"add_to_cart", "remove_from_cart", "clear_cart", "apply_coupon", "get_cart_total"}

            for tool_call in response.tool_calls:
                tool_name = tool_call["name"]
                tool_args = tool_call["args"]
                tool_id = tool_call.get("id", f"call_{iteration}")

                # حقن user_id و session_id في الأدوات اللي محتاجاهم
                tool_args = _inject_context(tool_args, tools, tool_name, user_id, session_id)

                # === NEW: Validation قبل التنفيذ ===
                is_valid, validation_error = _validate_tool_args(tool_name, tool_args)
                if not is_valid:
                    print(f"🚫 [{agent_name}] Tool validation failed for '{tool_name}': {validation_error}")
                    messages.append(ToolMessage(
                        content=validation_error,
                        tool_call_id=tool_id,
                    ))
                    can_fast_exit = False
                    continue

                # تنفيذ الأداة مع قص الناتج لو كان ضخم
                tool_result_str = await _execute_tool(tools, tool_name, tool_args)
                
                # Check for fast exit conditions
                if tool_name not in FAST_EXIT_TOOLS or "❌" in tool_result_str or "⚠️" in tool_result_str:
                    can_fast_exit = False
                else:
                    fast_exit_results.append(tool_result_str)

                if len(tool_result_str) > 2500:
                    tool_result_str = tool_result_str[:2500] + "... [تم قص الباقي للحفاظ على الـ Token Limit]"

                messages.append(ToolMessage(
                    content=tool_result_str,
                    tool_call_id=tool_id,
                ))

            # الخروج السريع لو كل الأدوات كانت من عمليات السلة ونجحت
            if can_fast_exit and fast_exit_results:
                return "\n\n".join(fast_exit_results), messages

            # متابعة الحلقة لرد الـ LLM على نتائج الأدوات
            continue

        # === لو مفيش tool calls → الرد جاهز ===
        if hasattr(response, "content") and response.content:
            final_text = response.content.strip() if isinstance(response.content, str) else str(response.content)
            return final_text, messages

    # وصل لأقصى عدد iterations
    # نحاول نستخرج آخر رد نصي
    for msg in reversed(messages):
        if isinstance(msg, AIMessage) and msg.content:
            final_text = msg.content.strip() if isinstance(msg.content, str) else str(msg.content)
            return final_text, messages

    fallback_text = await _fallback_response(system_prompt, user_message, context, agent_name)
    return fallback_text, messages


def _inject_context(tool_args: dict, tools: list, tool_name: str,
                     user_id: str, session_id: str) -> dict:
    """حقن user_id و session_id في الأدوات اللي محتاجاهم."""
    # البحث عن الأداة لفحص الـ schema
    for tool in tools:
        if tool.name == tool_name:
            try:
                schema = tool.args_schema.schema() if hasattr(tool, "args_schema") and tool.args_schema else {}
                props = schema.get("properties", {})

                if "user_id" in props and ("user_id" not in tool_args or tool_args.get("user_id") == "default"):
                    tool_args["user_id"] = user_id

                if "session_id" in props and "session_id" not in tool_args:
                    tool_args["session_id"] = session_id
            except Exception:
                # لو فشل استخراج الـ schema → نحط user_id لو مطلوب
                if "user_id" in str(tool.description).lower():
                    tool_args.setdefault("user_id", user_id)
            break

    return tool_args


async def _execute_tool(tools: list, tool_name: str, tool_args: dict) -> str:
    """تنفيذ أداة مع معالجة أخطاء شاملة."""
    for tool in tools:
        if tool.name == tool_name:
            try:
                result = await asyncio.wait_for(
                    tool.ainvoke(tool_args),
                    timeout=15.0,
                )
                return str(result)
            except asyncio.TimeoutError:
                return f"⚠️ الأداة '{tool_name}' استغرقت وقتاً طويلاً. حاول تاني."
            except Exception as e:
                print(f"⚠️ Tool '{tool_name}' error: {e}")
                return f"⚠️ حدث خطأ في الأداة '{tool_name}': {str(e)[:100]}"

    return f"⚠️ الأداة '{tool_name}' غير موجودة."


async def _fallback_response(system_prompt: str, user_message: str,
                              context: str, agent_name: str) -> str:
    """رد بديل عبر invoke_with_fallback — بدون أدوات."""
    try:
        # استخراج السطر الأول من الـ System Prompt للحفاظ على الشخصية وتجاهل تعليمات الأدوات
        persona = system_prompt.split('\n')[0]
        prompt = f"{persona}\n\n"
        if context:
            prompt += f"📋 سياق:\n{context}\n\n"
        prompt += f"الرسالة: {user_message}\n\nIMPORTANT: Respond directly in natural language. DO NOT use or return any tools or JSON objects.\nأجب بشكل مختصر ومفيد:"

        return await invoke_with_fallback(prompt, agent=agent_name, temperature=0.7)
    except Exception as e:
        print(f"❌ [{agent_name}] Fallback also failed: {e}")
        return "عذراً، حدث خطأ أثناء المعالجة. حاول تاني بعد شوية! 🙏"
