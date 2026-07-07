#!/usr/bin/env bash
# HelpBee 백업 복원 드릴 — "테스트 안 된 백업은 백업이 아니다" (plans/2026-07-07 PR-7)
#
# 최신 pg_dump 를 S3 에서 받아 임시 postgres 컨테이너에 복원하고 핵심 테이블
# 행 수를 출력한다. 월 1회 이상 수동 실행 후 결과를 docs/04-operation/runbook.md
# 실행 기록에 남길 것 (infra/CLAUDE.md §15 — RTO 4h/RPO 1h 근사 검증).
#
# 실행 (EC2 또는 docker 가 있는 어디서든):
#   BACKUP_S3_BUCKET=helpbee-db-backups ./scripts/restore-drill.sh
set -euo pipefail

BACKUP_S3_BUCKET=${BACKUP_S3_BUCKET:-$(grep '^BACKUP_S3_BUCKET=' /opt/helpbee/.env 2>/dev/null | cut -d= -f2- || true)}
AWS_REGION=${AWS_REGION:-ap-northeast-2}
[ -n "$BACKUP_S3_BUCKET" ] || { echo "ERROR: BACKUP_S3_BUCKET 필요"; exit 1; }

LATEST=$(aws s3api list-objects-v2 --bucket "$BACKUP_S3_BUCKET" --prefix pg/ \
  --region "$AWS_REGION" \
  --query 'sort_by(Contents,&LastModified)[-1].Key' --output text)
[ "$LATEST" != "None" ] || { echo "ERROR: 백업 없음 (s3://${BACKUP_S3_BUCKET}/pg/)"; exit 1; }
echo "==> 대상 백업: ${LATEST}"

WORK=$(mktemp -d)
CONTAINER="helpbee-restore-drill-$$"
cleanup() {
  docker stop "$CONTAINER" > /dev/null 2>&1 || true # --rm 이라 stop 시 자동 제거
  trash "$WORK" 2>/dev/null || true
}
trap cleanup EXIT

aws s3 cp "s3://${BACKUP_S3_BUCKET}/${LATEST}" "${WORK}/dump.sql.gz" --region "$AWS_REGION"
gunzip "${WORK}/dump.sql.gz"

echo "==> 임시 postgres 기동"
docker run -d --rm --name "$CONTAINER" \
  -e POSTGRES_USER=drill -e POSTGRES_PASSWORD=drill -e POSTGRES_DB=helpbee_drill \
  postgres:16-alpine > /dev/null
for _ in $(seq 1 30); do
  docker exec "$CONTAINER" pg_isready -U drill -d helpbee_drill > /dev/null 2>&1 && break
  sleep 2
done

echo "==> 복원"
docker exec -i "$CONTAINER" psql -q -U drill -d helpbee_drill -v ON_ERROR_STOP=1 \
  < "${WORK}/dump.sql" > /dev/null

echo "==> 검증 (핵심 테이블 행 수)"
docker exec "$CONTAINER" psql -U drill -d helpbee_drill -t -A -c "
  SELECT 'users: '          || count(*) FROM users
  UNION ALL SELECT 'hives: '           || count(*) FROM hives
  UNION ALL SELECT 'analyses: '        || count(*) FROM analyses
  UNION ALL SELECT 'analysis_images: ' || count(*) FROM analysis_images
  UNION ALL SELECT 'audit_log: '       || count(*) FROM audit_log;"

echo "OK: restore drill 완료 — ${LATEST}"
