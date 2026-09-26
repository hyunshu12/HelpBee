# 2026-09-26 — AI v0.2.0 two-stage 서빙·스키마·앱 동기 (계획 2)

> PR: **미생성** · 브랜치: `feature/ai-two-stage-redesign-spec` → develop · 머지일: —
> 계획: `docs/superpowers/plans/2026-09-23-ai-two-stage-plan2-serving-schema.md` · 스펙: `docs/superpowers/specs/2026-09-22-ai-two-stage-redesign-design.md` (v2.2 — 계획 본문의 v2.1과 다르면 v2.2 우선) · 결정: [ADR-0002](../01-development/adr/ADR-0002-two-stage-vdi-redesign.md)
> 학습 단계(계획 1) 기록: [2026-09-25-v020-two-stage-training.md](./2026-09-25-v020-two-stage-training.md) · 원장: `.superpowers/sdd/2026-09-23-ai-two-stage-plan2-serving-schema/progress.md`

## 범위 (Scope)

v0.2.0 two-stage 번들(YOLO11s 1-class @1024 + ResNet-18 320 + `vdi.yaml`)을 AI 서빙 경로에 연결하고, API/DB를 새 계약(VDI·tier 4종·카운트·CI·증거)으로 관용화하고, 모바일·어드민을 이중 출력 기간 계약에 맞췄다.

## 산출물 (Tasks → 커밋)

| Task | 내용 | 커밋 |
|---|---|---|
| 1 | API/DB 관용화: `analyses` `vdi`/`vdi_ci_low`/`vdi_ci_high`/`bee_total`/`bee_infested`(마이그레이션 `0003_cute_unus.sql`), tier 매핑 low/elevated/high/insufficient, 실패 판정 = `engine_used === null`, `ai_models('yolo','helpbee-two-stage','0.2.0')`, `resolveActiveModel(pipeline)`; 리뷰 수정 — 정규화 결과를 `raw_response`에 보존하고 GET/list에 `vdiDisplay/tier/corrected/beeTotal/beeInfested/samplingCi95/quality/modelVersions` 투영 | `c05626d`, `fb8da06` |
| 2 | AI 서빙: `AnalysisResponse` two-stage 필드(이중 출력) + two-stage 전용 축소 우회 `decode_rgb`; `quality.py`(블러·노출); `two_stage_engine.py`(Stage-1 1024, ≥8MP 2×2 타일·IoMin NMS → `crops.py` → Stage-2 64 청크·Platt·τ → CAM top-k); `run_analysis` two-stage 분기(`risk_score = score_mapping(vdi)`, `tier_legacy`, 유료 폴백, OpenAI shim, `AI_ENGINE` 주입); env(`AI_ENGINE`·`TWO_STAGE_MODEL_VERSION`·`TWO_STAGE_CACHE_DIR`·`AI_INTERNAL_BUDGET_S`) | `60a391c`, `b26ae25`, `28661ce`, `a4c7ec1`, `8d81443` |
| 3 | N장 합산: AI `POST /aggregate`(`vdi.aggregate` 단일 소스, counts 1~50) + API `GET /v1/analyses/aggregate?ids=` + `evidence` 새 형태 POST pass-through; 리뷰 수정 — insufficient row 제외, `excluded{legacy,insufficient}` | `a1474e0`, `2498d81`, `600eb3f` |
| 4 | 이미지 패스스루 q95(mozjpeg)·치수 유지; `PORTFOLIO_MODE`(쿼터·이메일 게이트 비활성, engine 항상 yolo, plans `portfolio:true`) | `081a620`, `ffa14f3` |
| 5 | 모바일: two-stage DTO·tier 매핑(insufficient)·분석 95s 타임아웃·원본 해상도 캡처/업로드(q95, >10MB만 4000) / 레포트 화면 VDI 카드·판독 불가 상태·증거 갤러리(원본 크롭) | `68d6e9d`, `49c74d6` |
| 6 | 어드민·API: 진단 상세 dual 뷰에 vdi/CI/벌 수 + two-stage raw 화이트리스트(중첩 `raw_payload.boxes`) | `528df91` |
| 7 | 회귀 fixture v2: 케이스 선정 규칙 `select_cases` + two-stage 생성기, 서빙 경로 매니페스트(경계·저벌수·0마리·블러·숨은응애) | `6b65f04`, `a69618c` |
| 8 | 구 필드 제거 마이그레이션 | **DEFERRED** (아래) |
| 9 | ADR-0002 · CLAUDE.md/frontend-api 정합 · 이 기록 · v0.1.0 태그 | 이 브랜치의 `docs:` 커밋 3개 |

모델 번들: `s3://helpbee-models/two-stage/v0.2.0/{stage1.onnx(38.2MB), stage2.onnx(44.7MB), metadata.json, vdi.yaml}`.

## 주요 결정 (원장 rulings)

- **Stage-2 계약은 metadata.json에서 읽는다**: 계획 본문(ShuffleNet 224, featmap 1024×7×7) 대신 계획 1 결과(ResNet-18 320, featmap 512×10×10) — 엔진이 `backbone`·`img_size`·`feat_channels`·`fc_weight`를 읽음.
- **`evidence` 형태** = `{index, box, crop_region, p_infested, cam}`. `raw_response`에는 저장하지 않고(부피) POST 응답으로만 전달 — 모바일이 이미 가진 원본 이미지에서 크롭(`crop_url` 없음).
- **insufficient row는 N장 합산에서 제외** (`tier === 'insufficient'` 또는 벌 0) → `excluded.insufficient`; 구 row(카운트 null)는 `excluded.legacy`.
- **`PORTFOLIO_MODE`**: `true`/`1`만 활성(엄격 파싱). production+true면 부팅 경고.
- **품질 임계는 보정 필요**: 블러(Laplacian < 100)·노출([40,215]) 스펙 값이 Sample FHD 성충의 47%를 실패시킴 → 값은 `vdi.yaml` `quality`에 두고 실제 폰 사진(Gate 0(a)) 확보 후 보정. 회귀 fixture에 품질 insufficient 케이스 포함.
- **타일링은 ≥8MP** (스펙 §4). 크롭 규칙은 `app/services/crops.py`로 이동(`training/data`는 Docker 미포함), `make_crops`가 재수출.
- **수용 리스크**: FHD 프레임은 벌 5~19마리라 감염 1마리 = `high`; 표본 CI에 반영.
- `capture_floor_px_per_mm` = null (Gate 0 붕괴점 없음) — 품질 게이트는 블러·노출만.

## 배포 순서 (필수)

> **마이그레이션 0003 → api → ai.** ai만 먼저 올리는 배포는 금지다.
> - 구 api + 신 ai 조합이면 구 HEALTH/SEVERITY 매핑에 `low/elevated/high/insufficient`가 없다. 그래서 severity가 undefined가 되고, recommendations NOT NULL insert가 실패한다.
> - api 기동 **전에** `drizzle-kit migrate`(0003: vdi/CI/bee 컬럼)를 먼저 적용한다. 이 순서를 어기면 신 api가 없는 컬럼에 쓰다가 실패한다.
> - 베타(`deploy-beta.yml` → `scripts/deploy-ec2.sh`)는 api와 ai를 **같은 커밋**에서 함께 배포하므로 실무상 안전하다. 수동 롤포워드나 부분 재배포 때 위 순서를 지킨다.
> - 롤백은 역순이다. ai를 `AI_ENGINE=yolo-v1`로 되돌린 뒤 api를 되돌린다. 0003은 순수 `ADD COLUMN`이라 되돌리지 않아도 구 api와 호환된다.
> - ai는 기동할 때 two-stage 번들(≈83 MB)을 prewarm한다(best-effort, `AI_PREWARM=0`이면 끔). 헬스체크 대기 시간에 이 다운로드 시간을 포함한다.

## 검증 (Verification)

- API vitest 251/251, API·DB type-check clean (Task 6 기준); DB itest 24/24 (Task 3 기준).
- AI pytest 기본 249 pass / 25 skip; 회귀 게이트 `-m regression` 25/25 (실번들). 실번들 스모크: 18마리 / 감염 1 / vdi 10.3 / `high` 0.94 s, 9MP 타일 1.7 s.
- 모바일 `flutter test` 50/50, `dart analyze` 0.
- drizzle-kit check clean (Task 1).

## 알려진 제약

- **어드민 빌드 차단**: 기존(pre-existing) zod 3.25.76 / `@hookform/resolvers` 3.3.4 타입 불일치(`(auth)/login`) — lockfile 일관 재설치로도 해결 안 됨, 이번 범위 밖.
- **Bruno 미갱신**: 이 worktree에 `apps/api/bruno/`가 없음.
- 부스 동결 테스트 18 skip(Sample 데이터 경로 필요) — 부스 코드 미변경.
- 모바일 HEIC 분기는 `flutter_image_compress` 네이티브 코덱 의존(호스트 테스트 불가). 로컬 원본 이미지가 없으면 증거 갤러리 숨김.
- `SUBSCRIPTION_WEBHOOK_ENABLED` 불리언 파싱 버그 — 후속 수정.
- 로컬 Postgres에 `helpbee_itest_plan2` DB 잔존(훅이 DROP 차단).

## 후속 작업 (Follow-up)

- **Task 8 (DEFERRED)**: 구 필드 제거 마이그레이션. 전제 = Task 1/2/5/6이 develop에 머지되고 **1회 배포**. 그 전에 제거하면 동결된 부스 경로 소비자가 깨진다.
- PR 생성(→ develop) — 미생성.
- 품질 임계 보정(Gate 0(a) 실사진 5장), 시연 인스턴스 T3 Unlimited/c6i.large 검토.
- Stage-2 벌 단위 recall 0.40 → v0.3 목표 0.90.

## 태그

- `v0.1.0-single-stage` → `8285d62` (`git merge-base origin/develop HEAD`, PR #57 머지 — two-stage 분기 직전 develop 마지막 커밋). **로컬 전용, push 안 함** — `v*` 태그 push가 production 워크플로를 트리거할 수 있어 소유자가 결정.

## 참조

- `apps/ai/CLAUDE.md` §6·§8, `apps/api/CLAUDE.md` §6, `apps/mobile/CLAUDE.md` §8·§9, `packages/database/CLAUDE.md` §4
- `docs/01-development/frontend-api-integration.md` §4.1
- `apps/ai/training/configs/vdi.yaml`, `apps/ai/training/eval_history/v0.2.0-*.json`
