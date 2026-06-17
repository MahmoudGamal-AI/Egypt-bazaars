"""
📝 DEPRECATED — Conversation Summarizer
✅ HIGH-02: Consolidated into memory/episodic_memory.py
This file remains as a backward-compatible shim to prevent ImportErrors.
"""
import logging

logger = logging.getLogger(__name__)
logger.warning("⚠️ summarizer.py is deprecated. Use memory/episodic_memory.py instead.")

# Re-export for backward compatibility
from memory.episodic_memory import summarize_conversation


def should_summarize(message_count: int) -> bool:
    """DEPRECATED — Use working_memory.should_summarize(session_id) instead."""
    return message_count > 0 and message_count % 15 == 0
