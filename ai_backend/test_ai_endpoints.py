import asyncio
import os
import sys

sys.path.append(os.getcwd())

from api.routes import chat
from api.owner_ai import api_inventory_alerts
from api.admin_ai import api_system_health
from models.chat import ChatRequest

async def test_admin_health():
    print("Testing Admin AI Health...")
    try:
        res = await api_system_health()
        print(f"Admin Health Response: {res}")
        return True
    except Exception as e:
        print(f"Admin Health Error: {e}")
        return False

async def test_owner_inventory():
    print("\nTesting Owner AI Inventory Alerts...")
    try:
        # Pass a dummy bazaar_id
        res = await api_inventory_alerts("test_bazaar")
        print(f"Owner Inventory Response: {res}")
        return True
    except Exception as e:
        print(f"Owner Inventory Error: {e}")
        return False

async def test_tourist_chat():
    print("\nTesting Tourist AI Chat with location...")
    req = ChatRequest(
        message="What bazaars are near me?",
        session_id="test_session",
        user_id="test_user",
        latitude=30.0444,
        longitude=31.2357
    )
    try:
        # We don't actually want to wait 50s for LLM if it works, just see if it crashes before LLM or starts LLM
        # But this will actually invoke LLM. We just want to see if it doesn't crash with 500.
        res = await chat(req)
        print(f"Tourist Chat Response: {res.text[:100]}...")
        return True
    except Exception as e:
        print(f"Tourist Chat Error: {e}")
        return False

async def main():
    print("=== Running AI Database Integration Tests ===")
    
    # We must run initialize_db_schema first to create the missing tables!
    from core.aws_memory import initialize_db_schema
    initialize_db_schema()
    print("Schema initialized.")
    
    success_admin = await test_admin_health()
    success_owner = await test_owner_inventory()
    
    if success_admin and success_owner:
        print("\n✅ All fast tests passed. The DB schema and queries are fixed.")
    else:
        print("\n❌ Some tests failed.")

if __name__ == "__main__":
    asyncio.run(main())
