from fastapi import FastAPI
from fastapi.responses import JSONResponse
import uvicorn
import os

app = FastAPI(
    title="HelpBee AI Server",
    description="AI-powered beehive analysis service",
    version="0.1.0"
)

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "ok",
        "service": "HelpBee AI Server",
        "version": "0.1.0"
    }

# Routers will be imported here
# from .routers import analyze
# app.include_router(analyze.router, prefix="/api")

if __name__ == "__main__":
    port = int(os.getenv("AI_PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
