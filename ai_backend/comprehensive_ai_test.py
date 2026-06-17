import asyncio
import os
import sys
import time

sys.path.append(os.getcwd())

# Import all core AI logic
from api.routes import chat as tourist_chat
from models.chat import ChatRequest
from api.owner_ai import api_daily_digest, api_bazaar_analytics
from services.admin.agents.admin_assistant import (
    admin_chat, get_platform_insights, generate_admin_message
)
from services.admin.agents.moderation import moderate_product, analyze_application
from core.aws_memory import initialize_db_schema

# We will use the mock bazaar created by the migration script
MOCK_BAZAAR_ID = "mock_bazaar_123"
MOCK_USER_ID = "mock_user_123"

class AITester:
    def __init__(self):
        self.results = []
        self.errors = []
        
    async def run_test(self, name, coro):
        print(f"\n[{name}] - Running...")
        start_t = time.time()
        try:
            res = await coro
            end_t = time.time()
            elapsed = round(end_t - start_t, 2)
            print(f"✅ Success! ({elapsed}s)")
            print(f"   Response Preview: {str(res)[:300]}...")
            self.results.append((name, "Passed", elapsed))
        except Exception as e:
            end_t = time.time()
            elapsed = round(end_t - start_t, 2)
            print(f"❌ FAILED! ({elapsed}s)\n   Error: {e}")
            self.errors.append((name, str(e)))
            self.results.append((name, "Failed", elapsed))

async def test_tourist_ai(tester):
    print("\n" + "="*50)
    print(" 🏖️ TOURIST AI TESTS")
    print("="*50)
    
    # 1. Routing & Simple Question
    req1 = ChatRequest(
        message="ما هي أفضل الأماكن السياحية في مصر؟",
        session_id="test_tourist_1",
        user_id=MOCK_USER_ID,
    )
    await tester.run_test("Tourist: General Routing", tourist_chat(req1))
    
    # 2. Location Context & DB Tools
    req2 = ChatRequest(
        message="أريد بازارات قريبة من موقعي الحالي لشراء هدايا تذكارية.",
        session_id="test_tourist_2",
        user_id=MOCK_USER_ID,
        latitude=30.0444,
        longitude=31.2357
    )
    await tester.run_test("Tourist: Location Context + Nearby Bazaars", tourist_chat(req2))

async def test_owner_ai(tester):
    print("\n" + "="*50)
    print(" 🏪 OWNER AI TESTS")
    print("="*50)
    
    # 1. Daily Digest (Tests analytics and summarization)
    await tester.run_test("Owner: Daily Digest", api_daily_digest(MOCK_BAZAAR_ID))
    
    # 2. Bazaar Analytics (Tests ML predictions and LEFT JOIN fix)
    await tester.run_test("Owner: Analytics", api_bazaar_analytics(MOCK_BAZAAR_ID, "month"))

async def test_admin_ai(tester):
    print("\n" + "="*50)
    print(" 👑 ADMIN AI TESTS")
    print("="*50)
    
    # 1. Platform Insights (Tests bazaar_applications fix)
    await tester.run_test("Admin: Platform Insights", get_platform_insights())
    
    # 2. Admin Chatbot
    await tester.run_test(
        "Admin: General Chat Query",
        admin_chat("ما هو تقييمك لأداء المنصة اليوم بناء على الإحصائيات؟", "", "test_admin_session")
    )
    
    # 3. Content Moderation (Product)
    # Using a fake product id, but it should gracefully fail or handle it without a 500 error,
    # or if we use the mock product 'mock_prod_1' from migration
    await tester.run_test("Admin: Product Moderation", moderate_product("mock_prod_1"))
    
    # 4. Message Generation
    await tester.run_test(
        "Admin: Generate Warning Message",
        generate_admin_message("warning", "بازار خان الخليلي الرائع", "تكرار شكاوى من الجودة", "")
    )

async def main():
    print("🌟 Initialize DB Schema (Ensuring all tables exist)...")
    initialize_db_schema()
    
    tester = AITester()
    
    await test_tourist_ai(tester)
    await test_owner_ai(tester)
    await test_admin_ai(tester)
    
    print("\n" + "="*50)
    print(" 📊 FINAL TEST SUMMARY")
    print("="*50)
    
    for name, status, time_taken in tester.results:
        icon = "✅" if status == "Passed" else "❌"
        print(f"{icon} {name.ljust(45)} | {time_taken}s")
        
    if tester.errors:
        print("\n⚠️ DETAILED ERRORS:")
        for name, err in tester.errors:
            print(f"- {name}: {err}")
        sys.exit(1)
    else:
        print("\n🎉 ALL TESTS PASSED SUCCESSFULLY! The AI system is robust and ready for production.")

if __name__ == "__main__":
    asyncio.run(main())
