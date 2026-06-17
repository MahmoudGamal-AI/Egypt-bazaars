"""
⚙️ Core Config — Shared configuration for all microservices.
Each service imports this and can override via environment variables.
"""
import os
import logging
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

# --- Logging ---
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s | %(levelname)-7s | %(name)s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

# --- Paths ---
BASE_DIR = Path(__file__).parent.parent  # ai_backend/

# --- API Keys ---
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
GROQ_API_KEY = os.getenv("GROQ_API_KEY")              # Tourist App (fallback)
TOURIST_GROQ_API_KEYS_ENV = os.getenv("TOURIST_GROQ_API_KEYS", "")
TOURIST_GROQ_API_KEYS = [k.strip() for k in TOURIST_GROQ_API_KEYS_ENV.split(",") if k.strip()]
GROQ_API_KEY_OWNER = os.getenv("GROQ_API_KEY2")       # Owner App
GROQ_API_KEY_ADMIN = os.getenv("GROQ_API_KEY3")       # Admin Web

TAVILY_API_KEY = os.getenv("TAVILY_API_KEY")

# --- Model Config ---
LLM_PROVIDER = os.getenv("LLM_PROVIDER", "groq")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.0-flash")
GROQ_MODEL = os.getenv("GROQ_MODEL", "openai/gpt-oss-120b")
GROQ_FAST_MODEL = os.getenv("GROQ_FAST_MODEL", "openai/gpt-oss-20b")
GEMINI_EMBEDDING_MODEL = os.getenv("GEMINI_EMBEDDING_MODEL", "models/gemini-embedding-001")

# --- AWS Region ---
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

# --- Security ---
ADMIN_API_KEY = os.getenv("ADMIN_API_KEY", "")
ALLOWED_ORIGINS_ENV = os.getenv("ALLOWED_ORIGINS", "*")
ALLOWED_ORIGINS = [o.strip() for o in ALLOWED_ORIGINS_ENV.split(",") if o.strip()]
RATE_LIMIT = os.getenv("RATE_LIMIT", "30/minute")

# --- Timeouts ---
LLM_TIMEOUT = float(os.getenv("LLM_TIMEOUT", "45.0"))
DB_QUERY_TIMEOUT = float(os.getenv("DB_QUERY_TIMEOUT", "15.0"))

# --- Caching ---
ANALYTICS_CACHE_TTL = int(os.getenv("ANALYTICS_CACHE_TTL", "300"))  # 5 minutes

# --- Operational ---
DEBUG = os.getenv("DEBUG", "false").lower() == "true"


def validate_config(service_name: str = "unknown"):
    """Validate required config for a given service."""
    logger = logging.getLogger(__name__)
    errors = []
    warnings = []

    if LLM_PROVIDER == "gemini" and not GEMINI_API_KEY:
        errors.append("GEMINI_API_KEY is not set")
    if LLM_PROVIDER == "groq" and not GROQ_API_KEY:
        errors.append("GROQ_API_KEY is not set")

    # Service-specific validation
    if service_name == "AdminService":
        if LLM_PROVIDER == "groq" and not GROQ_API_KEY_ADMIN:
            warnings.append("GROQ_API_KEY3 (admin-specific) not set — using shared key")
        if not ADMIN_API_KEY:
            warnings.append("ADMIN_API_KEY not set — API authentication disabled")

    if not TAVILY_API_KEY:
        warnings.append("TAVILY_API_KEY not set — web search unavailable")

    for w in warnings:
        logger.warning(f"[{service_name}] {w}")

    if errors:
        raise ValueError(f"[{service_name}] Config errors: " + ", ".join(errors))
    logger.info(f"[{service_name}] Configuration validated ✓")
