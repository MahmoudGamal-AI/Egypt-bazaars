"""
Gemini Multimodal Service for Image Search using `gemini-embedding-2`.
Implements a Round-Robin API Key Manager to bypass rate limits.
"""
import logging
import random
import requests
from io import BytesIO
from google import genai
from google.genai import types

logger = logging.getLogger(__name__)

# The 3 keys provided for rotation to avoid Rate Limit
GEMINI_MULTIMODAL_KEYS = [
    "AQ.Ab8RN6LwiWkpHWHP7N1j1gh3MEP6gl0ACOjgWk1yOaPbXfA_Yg",
    "AQ.Ab8RN6Kvul_j6Gz6SSMMsPaY4nDfduG9HOzeVHl5yyrONnSviw",
    "AQ.Ab8RN6Lkdgwq4srT3UdujJTrPSbT9y-mwkMMbSUMVAzZhpNpFg",
]

class GeminiKeyManager:
    """Round-robin API Key Manager for Gemini."""
    def __init__(self, keys: list[str]):
        self.keys = keys
        self.current_index = random.randint(0, len(keys) - 1)

    def get_client(self) -> genai.Client:
        key = self.keys[self.current_index]
        self.current_index = (self.current_index + 1) % len(self.keys)
        return genai.Client(api_key=key)

_key_manager = GeminiKeyManager(GEMINI_MULTIMODAL_KEYS)

def download_image_bytes(url: str) -> bytes | None:
    """Downloads an image from a URL as bytes."""
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        return response.content
    except Exception as e:
        logger.error(f"Failed to download image from {url}: {e}")
        return None

def generate_image_embedding(image_url: str, output_dimensionality: int = 1536) -> list[float] | None:
    """
    Downloads an image from Cloudinary (or any URL) and generates a 1536-dimensional
    embedding using gemini-embedding-2 to perfectly match the pgvector schema.
    """
    image_bytes = download_image_bytes(image_url)
    if not image_bytes:
        return None

    # Determine mime_type roughly from URL or fallback
    mime_type = "image/jpeg"
    if image_url.lower().endswith(".png"):
        mime_type = "image/png"
    elif image_url.lower().endswith(".webp"):
        mime_type = "image/webp"

    try:
        client = _key_manager.get_client()
        result = client.models.embed_content(
            model="gemini-embedding-2",
            contents=[
                types.Part.from_bytes(
                    data=image_bytes,
                    mime_type=mime_type,
                ),
            ],
            config=types.EmbedContentConfig(
                output_dimensionality=output_dimensionality
            )
        )
        # Returns a list of floats matching the output_dimensionality (1536)
        if result and result.embeddings:
            return result.embeddings[0].values
        return None
    except Exception as e:
        logger.error(f"Failed to generate Gemini embedding: {e}")
        return None

async def hybrid_image_search(image_url: str) -> tuple[list[float] | None, list[float] | None]:
    """
    V3 Hybrid Visual Search: Semantic Text (Flash) + Visual Image (gemini-embedding)
    Returns (text_embedding, image_embedding)
    """
    import asyncio
    image_bytes = await asyncio.to_thread(download_image_bytes, image_url)
    if not image_bytes:
        return None, None

    mime_type = "image/jpeg"
    if image_url.lower().endswith(".png"):
        mime_type = "image/png"
    elif image_url.lower().endswith(".webp"):
        mime_type = "image/webp"

    try:
        client = _key_manager.get_client()
        
        # Task 1: Fast Image Analysis using Flash (Semantic)
        def analyze_image():
            return client.models.generate_content(
                model="gemini-2.5-flash",
                contents=[
                    "أنت خبير في المنتجات المصرية السياحية. تجاهل الإضاءة والخلفية تماماً (مثل طاولة أو غرفة)، ركز فقط على المنتج الأساسي (مثل تمثال، عقد، بردية). استخرج اسم المنتج ومادته بدقة في سطر واحد ولا تزد عن 10 كلمات (مثال: تمثال فرعوني حورس حجر أسود).",
                    types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
                ]
            ).text

        # Task 2: Visual Image Embedding using gemini-embedding-2 (Visual Pixel Matching)
        def embed_image():
            result = client.models.embed_content(
                model="gemini-embedding-2",
                contents=[types.Part.from_bytes(data=image_bytes, mime_type=mime_type)],
                config=types.EmbedContentConfig(output_dimensionality=1536)
            )
            if result and result.embeddings:
                return result.embeddings[0].values
            return None
            
        # Run both tasks concurrently to save time
        description_task = asyncio.to_thread(analyze_image)
        image_emb_task = asyncio.to_thread(embed_image)
        
        description, image_embedding = await asyncio.gather(description_task, image_emb_task, return_exceptions=True)
        
        text_embedding = None
        if isinstance(description, str):
            logger.info(f"Hybrid Semantic Query: {description}")
            from services.gemini_service import get_query_embeddings
            embedder = get_query_embeddings()
            text_embedding = await embedder.aembed_query(description)
        else:
            logger.error(f"Hybrid analyze_image failed: {description}")

        import typing
        final_image_embedding: list[float] | None = None
        if isinstance(image_embedding, Exception):
            logger.error(f"Hybrid embed_image failed: {image_embedding}")
        else:
            final_image_embedding = typing.cast(list[float] | None, image_embedding)
            
        return text_embedding, final_image_embedding
    except Exception as e:
        logger.error(f"Hybrid Image Search failed: {e}")
        return None, None
