import asyncio
import json
from services.analytics_service import compute_platform_analytics

async def main():
    res = await compute_platform_analytics()
    print(json.dumps(res, ensure_ascii=False))

if __name__ == "__main__":
    asyncio.run(main())
