from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from api.owner_ai import router as owner_ai_router

app = FastAPI(
    title="Egyptian Tourism - Owner AI Backend",
    description="Dedicated AI Services for Bazaar Owners",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount the owner AI router — it already has prefix="/api/owner/ai" defined,
# so we include it without an extra prefix to avoid doubling the path.
app.include_router(owner_ai_router)

@app.get("/health")
def health_check():
    return {"status": "ok", "service": "owner-ai"}
