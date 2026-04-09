# HelpBee 운영 런북 (Runbook)

## 서비스 포트 맵

| 서비스 | 로컬 포트 | 클러스터 포트 |
|--------|-----------|--------------|
| auth | 8001 | 8001 |
| user | 8002 | 8002 |
| analysis | 8003 | 8003 |
| PostgreSQL | 5432 | 5432 |
| Redis | 6379 | 6379 |

## 장애 대응 (Incident Response)

### auth-service 응답 없음
```bash
kubectl get pods -n helpbee -l app=auth-service
kubectl logs -n helpbee -l app=auth-service --tail=100
kubectl rollout restart deployment/auth-service -n helpbee
```

### DB 연결 실패
```bash
kubectl get secret helpbee-secrets -n helpbee -o yaml
# DB URL 확인 후 연결 테스트
kubectl exec -it <pod-name> -n helpbee -- python -c "import asyncpg; print('ok')"
```

### 분석 실패율 급증
```bash
# Sentry에서 analysis-service 에러 확인
# OpenAI API 상태 확인: https://status.openai.com
kubectl logs -n helpbee -l app=analysis-service --tail=200
```

## 배포 절차

### Staging 배포
```bash
kubectl apply -k infra/k8s/overlays/staging
kubectl rollout status deployment -n helpbee
```

### Production 배포 (수동 승인 필요)
```bash
# ArgoCD UI에서 Manual Sync 실행
# 또는:
kubectl apply -k infra/k8s/overlays/production
kubectl rollout status deployment -n helpbee
```

## 모니터링 URL

| 도구 | URL |
|------|-----|
| Grafana | http://grafana.helpbee.internal |
| Sentry | https://sentry.io/helpbee |
| ArgoCD | http://argocd.helpbee.internal |
