#!/usr/bin/env bash
# HelpBee DB 논리 백업 — RDS 자동백업의 2차 방어선 (plans/2026-07-07 PR-7)
#
# 목적: 애플리케이션 레이어 실수(오분류 UPDATE/DELETE 등)는 RDS 스냅샷만으로
# 대응이 느리다 — nightly pg_dump 를 S3 에 적재해 두 번째 복구 경로를 만든다.
#
# 실행: EC2 crontab (Terraform user-data 가 등록, 예: 매일 04:10 KST)
#   10 4 * * * /opt/helpbee/scripts/backup-db.sh >> /var/log/helpbee-backup.log 2>&1
#
# 전제:
#   - /opt/helpbee/.env 에 DATABASE_URL, BACKUP_S3_BUCKET (+ AWS_REGION)
#   - docker (pg_dump 는 postgres:16-alpine 컨테이너로 실행 — EC2 에 pg 클라이언트 불필요)
#   - instance profile 에 대상 버킷 PutObject + cloudwatch:PutMetricData
#   - 버킷 lifecycle 14일 (Terraform) — 이 스크립트는 적재만 담당
#
# 성공 시 CloudWatch 커스텀 메트릭 HelpBee/Backup:DbBackupSuccess=1 발행.
# 알람은 "메트릭 결측(missing data) = 백업 미실행/실패" 로 걸어 실패도 잡는다.
set -euo pipefail

ENV_FILE=/opt/helpbee/.env
[ -f "$ENV_FILE" ] || { echo "ERROR: ${ENV_FILE} 없음"; exit 1; }

DATABASE_URL=$(grep '^DATABASE_URL=' "$ENV_FILE" | cut -d= -f2-)
BACKUP_S3_BUCKET=$(grep '^BACKUP_S3_BUCKET=' "$ENV_FILE" | cut -d= -f2-)
AWS_REGION=$(grep '^AWS_REGION=' "$ENV_FILE" | cut -d= -f2- || true)
AWS_REGION=${AWS_REGION:-ap-northeast-2}
[ -n "$DATABASE_URL" ] || { echo "ERROR: DATABASE_URL 없음"; exit 1; }
[ -n "$BACKUP_S3_BUCKET" ] || { echo "ERROR: BACKUP_S3_BUCKET 없음"; exit 1; }

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
KEY="pg/helpbee-${STAMP}.sql.gz"

echo "==> pg_dump → s3://${BACKUP_S3_BUCKET}/${KEY}"
docker run --rm --network host postgres:16-alpine \
  pg_dump --no-owner --no-privileges "$DATABASE_URL" \
  | gzip \
  | aws s3 cp - "s3://${BACKUP_S3_BUCKET}/${KEY}" --region "$AWS_REGION" --expected-size 1073741824

# 빈 덤프 방어: 최소 크기 검증 (스키마만 있어도 수 KB — 1KB 미만이면 실패로 간주)
SIZE=$(aws s3api head-object --bucket "$BACKUP_S3_BUCKET" --key "$KEY" \
  --region "$AWS_REGION" --query ContentLength --output text)
[ "$SIZE" -ge 1024 ] || { echo "ERROR: 덤프가 비정상적으로 작음 (${SIZE}B)"; exit 1; }

aws cloudwatch put-metric-data --region "$AWS_REGION" \
  --namespace HelpBee/Backup --metric-name DbBackupSuccess --value 1

echo "OK: backup 완료 — ${KEY} (${SIZE}B)"
