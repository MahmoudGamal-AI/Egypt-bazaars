from core.aws_memory import get_aurora_connection

def check():
    conn = get_aurora_connection()
    if conn:
        with conn.cursor() as cur:
            cur.execute("SELECT attname, atttypmod FROM pg_attribute WHERE attrelid = 'products'::regclass AND attname IN ('embedding', 'image_embedding');")
            print(cur.fetchall())

if __name__ == "__main__":
    check()
