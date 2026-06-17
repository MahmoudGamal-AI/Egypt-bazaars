"""
Langfuse Tracing Configuration
Provides dynamic callback handler for deep tracing of Langchain & Langgraph executions.
Used by tourist and owner services for monitoring AI agent performance.
"""
import os
import logging

logger = logging.getLogger(__name__)

# --- Langfuse Config (loaded from environment) ---
LANGFUSE_SECRET_KEY = os.getenv("LANGFUSE_SECRET_KEY", "")
LANGFUSE_PUBLIC_KEY = os.getenv("LANGFUSE_PUBLIC_KEY", "")
LANGFUSE_BASE_URL = os.getenv("LANGFUSE_HOST", "https://cloud.langfuse.com")


def get_langfuse_handler():
    """Get Langfuse callback handler for tracing LLM executions.
    Returns None if Langfuse credentials are not configured.
    """
    if not LANGFUSE_SECRET_KEY or not LANGFUSE_PUBLIC_KEY:
        logger.debug("Langfuse not configured — tracing disabled")
        return None

    try:
        from langfuse.langchain import CallbackHandler

        os.environ["LANGFUSE_SECRET_KEY"] = LANGFUSE_SECRET_KEY
        os.environ["LANGFUSE_PUBLIC_KEY"] = LANGFUSE_PUBLIC_KEY
        os.environ["LANGFUSE_HOST"] = LANGFUSE_BASE_URL

        return CallbackHandler()
    except ImportError:
        logger.warning("langfuse package not installed — tracing disabled")
        return None
    except Exception as e:
        logger.warning(f"Failed to initialize Langfuse handler: {e}")
        return None
