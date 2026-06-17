"""
Background Script: Sync Product Image Embeddings
This script fetches all products from the Aurora database that do not have an embedding,
downloads their images, generates a 1536-dimensional embedding using gemini-embedding-2,
and saves the embedding back to the database.

It ensures ZERO impact on live app performance.
"""
import os
import sys
import logging
import psycopg2
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv

# Add parent directory to path to allow absolute imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from core.aws_memory import get_aurora_connection, release_aurora_connection
from services.gemini_multimodal_service import generate_image_embedding

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

def sync_embeddings():
    logger.info("Starting Product Image Embedding Sync...")
    
    conn = get_aurora_connection()
    if not conn:
        logger.error("Could not connect to database.")
        return

    try:
        # Get products missing image embeddings
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT id, image_url, name_ar FROM products WHERE image_embedding IS NULL AND image_url IS NOT NULL;")
            products = cur.fetchall()
            
        logger.info(f"Found {len(products)} products without embeddings.")
        
        updated_count = 0
        for product in products:
            p_id = product['id']
            image_url = product['image_url']
            name = product['name_ar']
            
            logger.info(f"Processing product: {name} ({p_id})")
            
            # Generate Embedding
            embedding = generate_image_embedding(image_url, output_dimensionality=1536)
            
            if embedding:
                # Update DB
                with conn.cursor() as cur:
                    cur.execute(
                        "UPDATE products SET image_embedding = %s::vector WHERE id = %s",
                        (embedding, p_id)
                    )
                conn.commit()
                updated_count += 1
                logger.info(f"✅ Successfully updated embedding for {name}")
            else:
                logger.warning(f"⚠️ Failed to generate embedding for {name} ({image_url})")
                
        logger.info(f"Sync complete. Updated {updated_count} products.")
        
    except Exception as e:
        logger.error(f"Error during sync: {e}")
        if conn:
            conn.rollback()
    finally:
        release_aurora_connection(conn)

if __name__ == "__main__":
    load_dotenv()
    sync_embeddings()
