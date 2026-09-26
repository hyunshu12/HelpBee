from fastapi import FastAPI
from fastapi.responses import JSONResponse
import logging
import os

import uvicorn

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

from .routers import aggregate, analyze  # noqa: E402

_log = logging.getLogger("helpbee.ai.startup")


def prewarm_two_stage() -> bool:
    """AI_ENGINE=two-stage 면 번들(≈83 MB S3)·ONNX 세션·vdi.yaml 을 미리 로드한다 — best-effort.

    lazy 로드면 배포 직후 첫 /analyze 가 다운로드+세션 생성을 떠안아 ai-client 90s 를 넘길 수 있다.
    실패(캐시·S3·자격 증명 없음 등)는 로그만 남기고 기동은 계속 — 첫 요청에서 다시 시도된다.
    AI_PREWARM=0 이면 건너뛴다. 반환: 실제로 워밍됐는지.
    """
    if os.getenv("AI_PREWARM", "1") == "0":
        return False
    try:
        from .deps import get_two_stage_engine

        engine = get_two_stage_engine()
        if engine is None:  # AI_ENGINE=yolo-v1 (롤백 경로)
            return False
        engine.prewarm()
        _log.info("two-stage bundle prewarmed: %s", getattr(engine, "version", "?"))
        return True
    except Exception as exc:  # noqa: BLE001 - 기동을 막지 않는다
        _log.warning("two-stage prewarm failed (continuing, lazy load on first request): %s", exc)
        return False


# 기동 시 prewarm — lifespan 은 FastAPI 생성 시점에 넘겨야 해 여기서 router 에 등록한다.
async def _prewarm_on_startup() -> None:
    import asyncio

    # 백그라운드로 — 83 MB S3 다운로드가 /health·첫 요청을 막지 않게 한다(재리뷰 nit).
    asyncio.get_running_loop().create_task(asyncio.to_thread(prewarm_two_stage))


app.router.on_startup.append(_prewarm_on_startup)


app.include_router(analyze.router)
app.include_router(aggregate.router)

if __name__ == "__main__":
    port = int(os.getenv("AI_PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
