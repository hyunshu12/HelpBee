#!/usr/bin/env bash
# HelpBee beta 배포 스크립트 — 단일 EC2 (plans/2026-07-07_배포인프라-절감모드.md PR-6)
#
# 실행 주체: deploy-beta.yml 이 SSM Run Command(AWS-RunShellScript)로 EC2 에서 실행.
#   curl -fsSL https://raw.githubusercontent.com/hyunshu12/HelpBee/<sha>/scripts/deploy-ec2.sh \
#     | bash -s -- <image_tag> <git_sha>
#
# 전제 (Terraform user-data 가 준비):
#   - /opt/helpbee/.env         SSM Parameter Store 렌더링 (ECR_REGISTRY, AWS_REGION,
#                               DATABASE_URL 등 — docker-compose.beta.yml 헤더 참조)
#   - /opt/helpbee/certs/       Cloudflare Origin CA
#   - /opt/helpbee/cache/yolo/  모델 캐시 (chown 1001)
#   - docker + compose plugin + awscli, instance profile(ECR pull/SSM)
#
# 멱등: 같은 태그로 재실행해도 안전. 마이그레이션 실패 시 기존 컨테이너 유지한 채 중단.
set -euo pipefail

TAG="${1:?usage: deploy-ec2.sh <image_tag> <git_sha>}"
SHA="${2:?usage: deploy-ec2.sh <image_tag> <git_sha>}"
DIR=/opt/helpbee
RAW="https://raw.githubusercontent.com/hyunshu12/HelpBee/${SHA}"

cd "$DIR"
[ -f .env ] || { echo "ERROR: ${DIR}/.env 없음 — user-data(SSM 렌더링) 선행 필요"; exit 1; }

echo "==> compose/Caddyfile 동기화 (sha=${SHA})"
curl -fsSL "${RAW}/docker-compose.beta.yml" -o docker-compose.yml
curl -fsSL "${RAW}/infra/docker/caddy/Caddyfile" -o Caddyfile

echo "==> IMAGE_TAG=${TAG}"
if grep -q '^IMAGE_TAG=' .env; then
  sed -i "s|^IMAGE_TAG=.*|IMAGE_TAG=${TAG}|" .env
else
  echo "IMAGE_TAG=${TAG}" >> .env
fi

ECR_REGISTRY=$(grep '^ECR_REGISTRY=' .env | cut -d= -f2-)
AWS_REGION=$(grep '^AWS_REGION=' .env | cut -d= -f2- || true)
AWS_REGION=${AWS_REGION:-ap-northeast-2}
[ -n "$ECR_REGISTRY" ] || { echo "ERROR: .env 에 ECR_REGISTRY 없음"; exit 1; }

echo "==> ECR 로그인 (instance profile)"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

echo "==> 이미지 pull"
docker compose pull --quiet

echo "==> DB 마이그레이션 (실패 시 배포 중단 — 기존 컨테이너 유지)"
docker compose run --rm --no-deps api \
  ./node_modules/.bin/tsx ../../packages/database/src/migrate.ts

echo "==> 컨테이너 재기동"
docker compose up -d --remove-orphans

echo "==> 헬스 대기 (api, ai — Dockerfile HEALTHCHECK 기준)"
for svc in api ai; do
  status=starting
  for _ in $(seq 1 36); do # 최대 3분
    cid=$(docker compose ps -q "$svc")
    status=$(docker inspect --format='{{.State.Health.Status}}' "$cid" 2>/dev/null || echo starting)
    [ "$status" = "healthy" ] && break
    sleep 5
  done
  if [ "$status" != "healthy" ]; then
    echo "ERROR: ${svc} unhealthy (status=${status}) — 최근 로그:"
    docker compose logs --tail 60 "$svc" || true
    exit 1
  fi
  echo "    ${svc}: healthy"
done

echo "==> 미사용 이미지 정리"
docker image prune -f > /dev/null

echo "OK: deploy 완료 — tag=${TAG} sha=${SHA}"
