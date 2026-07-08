from fastapi import FastAPI
from fastapi.responses import JSONResponse
import uvicorn
import os

# 관측성 (plans/2026-07-07 PR-7): SENTRY_DSN 있을 때만 활성 — 로컬/CI는 no-op.
# import 를 조건부로 둬서 sentry-sdk 미설치 로컬 venv 에서도 앱이 뜬다.
_sentry_dsn = os.getenv("SENTRY_DSN")
if _sentry_dsn:
    import sentry_sdk

    sentry_sdk.init(
        dsn=_sentry_dsn,
        environment=os.getenv("HELPBEE_ENV", "beta"),
        traces_sample_rate=0,  # 에러 가시성만 — 트레이싱은 베타 범위 밖
    )

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

from .routers import analyze  # noqa: E402

app.include_router(analyze.router)

if __name__ == "__main__":
    port = int(os.getenv("AI_PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
