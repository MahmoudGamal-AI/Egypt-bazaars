"""
🚀 AWS Lambda Entry Point for Owner AI Service
Uses Mangum to wrap FastAPI for AWS API Gateway.
"""
from mangum import Mangum
from services.owner.app import app
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ✅ FIX: api_gateway_base_path strips the /prod stage prefix from rawPath
# HTTP API v2 with payload format 2.0 includes the stage in rawPath,
# so Mangum needs to know to strip it before passing to FastAPI.
mangum_handler = Mangum(app, lifespan="off", api_gateway_base_path="/prod")

def lambda_handler(event, context):
    logger.info(f"📥 Event path: {event.get('rawPath', 'N/A')}")
    logger.info(f"📥 Route key: {event.get('routeKey', 'N/A')}")
    return mangum_handler(event, context)
