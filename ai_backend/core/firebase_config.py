"""
🔥 Firebase Configuration
Provides Firestore client for services that need Firebase access.
Used by tourist and owner services for real-time data sync.
"""
import os
import logging

logger = logging.getLogger(__name__)

_db = None


def get_firestore_client():
    """Get or create a Firestore client singleton.
    Returns None if Firebase cannot be initialized.
    """
    global _db
    if _db is not None:
        return _db

    try:
        import firebase_admin
        from firebase_admin import credentials, firestore

        if not firebase_admin._apps:
            cred_path = os.environ.get("FIREBASE_CREDENTIALS", "secrets/firebase_credentials.json")
            if os.path.exists(cred_path):
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
                logger.info("Firebase Admin initialized using credentials file.")
            else:
                # Fallback — works in AWS if role has access or if emulator is used
                firebase_admin.initialize_app()
                logger.info("Firebase Admin initialized with default credentials.")

        _db = firestore.client()
        return _db
    except ImportError:
        logger.warning("firebase-admin package not installed — Firestore unavailable")
        return None
    except Exception as e:
        logger.error(f"Failed to initialize Firestore client: {e}")
        return None
