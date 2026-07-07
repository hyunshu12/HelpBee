# syntax=docker/dockerfile:1
# HelpBee AI (FastAPI + YOLO ONNX CPU 추론) — beta 단일 EC2용 이미지
# (plans/2026-07-07_배포인프라-절감모드.md PR-4)
#
# requirements.txt = CPU 추론 전용(torch 없음, onnxruntime). 학습 스택
# (requirements-gpu.txt)은 절대 포함하지 않는다 — 이미지 400~600MB대 유지.
#
# 빌드 컨텍스트 = 모노레포 루트:
#   docker build -f apps/ai/Dockerfile -t helpbee-ai .

FROM python:3.12-slim AS builder
WORKDIR /build
COPY apps/ai/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim AS runner
ENV PYTHONUNBUFFERED=1 \
    YOLO_CACHE_DIR=/var/cache/helpbee/yolo
# uid 1001 고정 — EC2 호스트의 캐시 볼륨(bind mount) chown 1001 과 짝 (user-data)
RUN useradd --system --uid 1001 --create-home appuser \
    && mkdir -p /var/cache/helpbee/yolo \
    && chown -R appuser:appuser /var/cache/helpbee
COPY --from=builder /install /usr/local
WORKDIR /srv/helpbee
# 런타임 필요 파일만 복사:
#   - app/                  FastAPI 앱 본체
#   - training/configs/     risk.py 가 risk.yaml 을 로드 (services/risk.py:_CONFIG_PATH
#                           = parents[2]/training/configs/risk.yaml → /srv/helpbee 기준 정합)
#   datasets/·runs/ 등 학습 산출물은 절대 미포함 (.dockerignore 로도 차단)
COPY --chown=appuser:appuser apps/ai/app ./app
COPY --chown=appuser:appuser apps/ai/training/configs ./training/configs
USER appuser
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).status==200 else 1)"
# workers 기본 1 — ONNX 세션이 워커당 메모리를 차지하므로 t3.medium(4GB)에선 1이 안전.
# 스케일업 시 UVICORN_WORKERS 환경변수로 조정.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers ${UVICORN_WORKERS:-1}"]
