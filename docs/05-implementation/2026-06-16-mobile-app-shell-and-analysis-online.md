# 2026-06-16 — 모바일 앱 셸(네비/설정) + 디자인 정합(홈·벌통상세) + 분석 백엔드 온라인화

> PR: (예정) · 브랜치: `feature/mobile-app-shell-and-analysis` → develop · 머지일: (예정)
> 선행: [2026-06-16-mobile-hives-integration.md](./2026-06-16-mobile-hives-integration.md)(PR #28, 머지됨 — 벌통 CRUD)

## 범위 (Scope)

PR #28(벌통 CRUD) 이후 작업. **하단 네비게이션 셸 + 용어/설정/이력/프로필**, **분석 백엔드(AI 서버+S3)를 실제 동작까지 온라인화**, **Figma 디자인에 맞춘 홈·벌통 상세 재구성 + 분석 데이터 계층**, 그리고 **적대적 리뷰로 검증·수정**.

## 산출물 (Deliverables)

### 1. 앱 셸 / 네비게이션 (Phase 1)
- `core/routing/app_shell.dart` + `app_router.dart` — **StatefulShellRoute 하단 탭 3개**(벌통/진단 이력/설정). 인증·스플래시·`/hives/:id`는 셸 위 top-level.
- 용어 정정: **양봉장 → 벌통**(전체 l10n). 단 홈 타이틀은 디자인대로 **"양봉장 현황"**.
- `features/settings/presentation/` — 설정(계정·요금제/무료 진단 허용량·화면 테마·앱 버전·로그아웃) + 프로필 편집(조회).
- `features/analyses/presentation/analysis_history_screen.dart` — 진단 이력 탭(placeholder; 백엔드가 hiveId별 조회라 전역 이력은 후속).
- `core/theme/theme_mode_controller.dart` + `core/storage/app_prefs.dart`(themeMode) — 시스템/밝게/어둡게 저장.
- `features/subscriptions/`(dto/api/provider) — `/v1/subscriptions/me`.

### 2. 분석 백엔드 온라인화 (인프라/운영 — 코드 산출물 아님, 기록용)
- **S3 이미지 버킷 생성**: `helpbee-images-dev`(ap-northeast-2). 모델 버킷 `helpbee-models`는 기존.
- **AI 서버(apps/ai, :8000)** 기동: requirements 설치(pillow-heif/openai 제외 — 핀 충돌/선택적), `best.onnx`(36MB) S3→`~/.cache/helpbee/yolo/`, `apps/ai/.env`(api와 동일 HMAC). `apps/ai/app/deps.py`에 **`YOLO_CACHE_DIR` env 오버라이드 추가**(macOS `/var/cache` root 회피, 커밋됨).
- **E2E 실검증 성공**: login→presign→S3 PUT(200)→confirm→`POST /analyses` → `status:success` + 실제 YOLO ONNX 추론(latency ~226ms, engine=yolo). 무료 사용자=yolo(OpenAI 키 불필요), 무료는 email_verified 필요(시드 계정은 verified).

### 3. 디자인 정합 + 분석 데이터 계층
- `features/analyses/data/` — `Analysis` DTO + `AnalysesApi`(목록/상세/추이/생성) + `latestAnalysisProvider`/`hiveAnalysesProvider`. tier 매핑은 `core/risk/risk_tier.dart`(RiskTier + 색/배지 라벨).
- **홈 재구성**(`features/home/presentation/home_screen.dart`): "양봉장 현황" + 우상단 `+`(벌통 등록) + **무료 진단 쿼터 배너**(`subscriptions/presentation/quota_banner.dart`) + **풍부한 벌통 카드**(`hives/presentation/hive_summary_card.dart`: 이름·위치·최근 측정일·tier 배지·큰 점수) + **📷 진단하기 FAB**.
- **벌통 상세 재구성**(`hives/presentation/hive_detail_screen.dart`): 위험 요약 카드 · 벌통 위치 · 설치날짜/상태 · 메모 · **과거 진단 이력 타임라인** · ⋮(수정/삭제) · "벌통 다시 촬영하기" CTA. (실제 Figma는 추이 차트가 아니라 타임라인.)
- 공유: `shared/widgets/risk_badge.dart`.
- **디자인 소스**: Figma(`nxpjoTDvnfAAAnsW2iOXcy`)를 cursor-talk-to-figma 로컬 브릿지로 직접 읽어 정합(공식 Figma MCP는 Starter 한도).

### 4. 적대적 리뷰 + 수정
4-렌즈(계약/아키텍처/런타임/디자인) 리뷰 → 발견별 적대적 재검증 → 확정 22건 중 실결함 12건 수정:
tier 매핑 순서(overallHealth 우선) · 홈 카드 로딩/에러를 "진단 없음"으로 오표시 · 새 진단 후 stale(새로고침 invalidate) · 쿼터 "남음" 오표기→허용량 · 상세 상대날짜 타임존 · "더보기" dead-end 제거 · 배지/배너 폰트(16/18sp)·UPGRADE ARB화·48dp 타깃 · 테마 로드 경합 · 토큰화.

## 검증 (Verification)
- `flutter analyze` **0** · `flutter test` **27 pass**(DTO/tier/위젯/컨트롤러) · `flutter build ios --simulator` **성공**.
- 분석 백엔드 **라이브 E2E**(curl) 통과(§2).
- 적대적 워크플로우 통과(false positive 제외, 실결함 수정).

### 알려진 제약 / 후속
- **홈 N+1**: 벌통당 최신분석 1콜 → 정석 = `GET /v1/hives` 응답에 `latestAnalysis` 포함(백엔드 후속). 현재 lazy 리스트라 동작엔 문제 없음.
- 쿼터 **remaining 미제공**(API는 allowance만) → 디자인의 "N회 남음" 정확 구현엔 백엔드 remaining 카운트 필요.
- 설정 **사용량 카드(주인공)·약관 링크·package_info 버전** 미구현.
- **진단 이력 탭**(전역) 미구현 — hiveId별 조회 한계.
- **분석 흐름 화면**(촬영할 벌통 선택→카메라→검토→분석중→레포트) 미구현 — 다음 단계(백엔드는 준비됨).
- AI 서버/이미지 버킷은 **로컬/dev** 환경 — staging/prod는 인프라 후속.

## 후속 작업 (Follow-up)
- 분석 흐름 5화면(camera/image 패키지 + iOS 권한) → 레포트(원형 게이지) — 백엔드 E2E 완료라 바로 연동 가능.
- 벌통 등록 풀스크린 폼(위치/설치일)·벌통 수정·온보딩/로그인 디자인 미세 정합.
- `GET /v1/hives` latestAnalysis 포함(홈 N+1 해소) + `/subscriptions/me` remaining 카운트.

## 참조
- 권위 가이드: `apps/mobile/CLAUDE.md` · 백엔드 계약: `docs/01-development/frontend-api-integration.md`
- 디자인 핸드오프: `docs/06-design-handoff/2026-06-09-mobile-app-mvp.md` (단, 픽셀은 Figma 우선)
- AI 도메인: `apps/ai/CLAUDE.md`
