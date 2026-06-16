# 2026-06-17 — 모바일 진단 흐름 5화면 (촬영→검토→분석중→레포트)

> PR: (예정) · 브랜치: `feature/mobile-app-shell-and-analysis` → develop · 머지일: (예정)
> 선행: [2026-06-16-mobile-app-shell-and-analysis-online.md](./2026-06-16-mobile-app-shell-and-analysis-online.md)(앱 셸 + 분석 백엔드 온라인화)

## 범위 (Scope)

사진 한 장 → 진단 결과까지의 **엔드투엔드 사용자 흐름**을 Figma에 맞춰 구현. 홈 FAB(진단하기)·벌통 상세(다시 촬영하기)에서 진입 → **카메라 → 사진 검토 → 분석중(업로드+추론) → 레포트**. 백엔드는 이미 온라인(라이브 E2E 검증됨, 선행 PR)이라 실제 진단까지 동작.

## 산출물 (Deliverables)

### 1. 이미지 업로드 파이프라인 (신규 데이터 계층)
- `features/analyses/data/images_api.dart` — `ImagesApi`: `presign`(POST /v1/images/presign) → `uploadToS3`(presigned PUT, **bareDio = 인증헤더 없음**, Content-Type=presign과 일치) → `confirm`(POST /v1/images/confirm) → `AnalysisImage{id}`. `PresignResult`/`AnalysisImage` 수기 DTO.
- `features/analyses/data/capture_preprocess.dart` — `preprocessForUpload`: `flutter_image_compress`로 longest≲1920 / JPEG q85 / **EXIF(GPS) strip** / orientation 베이크. HEIC 입력도 네이티브 처리.
- `features/analyses/presentation/analysis_run_controller.dart` — `runAnalysisProvider`(`FutureProvider.autoDispose.family<Analysis, ({hiveId, imagePath})>`): preprocess→presign→PUT→confirm→`analyses.create`. **레코드 키 값동등성으로 1회만 실행**(중복 업로드/과금 방지). 성공 시 `latestAnalysisProvider`/`hiveAnalysesProvider` invalidate(홈 카드·상세 타임라인 갱신). `status:'failed'`(graceful 200)는 에러가 아닌 결과로 반환.

### 2. 화면 5개 (Figma 정합)
- `presentation/capture_screen.dart` — 카메라(49:538): 미리보기 + 꿀색 코너 가이드 오버레이(CustomPainter) + 캡션 + 갤러리/셔터/플래시(off→auto→on). **시뮬레이터(카메라 없음)·일시적 init 실패(탭 재시도)·정상** 3상태 구분, 앱 생명주기에서 컨트롤러 dispose/재획득(disposed 컨트롤러 렌더 방지).
- `presentation/photo_review_screen.dart` — 카메라검토(49:571): 촬영 사진 + "이 사진으로 분석하기"/"다시 찍기".
- `presentation/analyzing_screen.dart` — 분석중(19:315): 꿀색 링+벌 + 진행 카피. `runAnalysisProvider` 구동 → data면 레포트로 `pushReplacement`, 에러면 인라인 재시도/취소(에러 시 시스템 백 허용).
- `presentation/report_screen.dart` — 레포트(24:12): **RiskGauge**(점수/tier) + "응애 감염 위험 단계" + 분석된 사진 카드(로컬 썸네일·확대 뷰어) + 권장 조치 카드 + 홈으로/상세 이력에 기록. `failed`는 "완료 못함" 상태로 graceful 표시.
- `shared/widgets/risk_gauge.dart` — 0–100 원형 게이지(CustomPainter, tier 색 arc, 중앙 점수, null→"—").
- 진입: `features/home/presentation/capture_launcher.dart`(`launchCapture`) — 벌통 0개=등록 안내 / 1개=바로 카메라 / 2개+=선택 바텀시트.

### 3. 공통/라우팅/i18n
- `shared/widgets/{primary,secondary}_button.dart` — 선택적 `icon`, SecondaryButton `foreground`(사진 위 흰색).
- `core/routing/route_paths.dart` + `app_router.dart` — `capture`/`review`/`analyzing`/`report` 풀스크린 라우트(shell 위 push, args=`state.extra`, 누락 시 `_FlowMissing`→홈). 흐름: capture(push)→review(push)→analyzing(pushReplacement)→report(pushReplacement).
- `core/risk/recommendations.dart` — tier별 권장 조치 + 게이지 캡션(⚠️ **백엔드가 recommendations 미반환** → 클라 폴백 + 면책 문구).
- `core/errors/error_code.dart`·`error_messages.dart` — 업로드 에러코드(UNSUPPORTED_MEDIA/IMAGE_TOO_LARGE/IMAGE_INVALID/IMAGE_NOT_FOUND_IN_STORAGE) 매핑 + 한국어 메시지.
- `l10n/app_ko.arb` — 흐름/에러/접근성 키 다수(하드코딩 없음). 접근성: 셔터/갤러리/플래시 Semantics(button)+플래시 모드 라벨, 이미지 Semantics, 닫기 tooltip.

### 4. 플랫폼 설정 / 패키지
- `pubspec.yaml` — **camera ^0.12 / image_picker ^1.2 / flutter_image_compress ^2.4** 추가(전처리는 flutter_image_compress 단일 사용 → dart `image` 패키지 생략).
- `ios/Runner/Info.plist` — NSCameraUsageDescription / NSPhotoLibraryUsageDescription.
- `android/.../AndroidManifest.xml` — CAMERA 권한. `build.gradle.kts` — `minSdk=24`(flutter_image_compress).

### 5. 적대적 리뷰 반영
4-렌즈(계약/런타임/디자인/i18n) + 발견별 재검증 워크플로우 → 확정 결함 수정: 카메라 생명주기(dispose/재획득/일시실패 재시도) · 분석중 에러 시 백 허용 · 공유 tooltip 오라벨 · 이미지뷰어 닫기/이미지 Semantics · 갤러리·플래시 Semantics+모드 라벨 · 분석중 제목 크기.

## 검증 (Verification)
- `flutter analyze` **0** · `flutter test` **30 pass**(신규: 추천 폴백·게이지 위젯) · `flutter build ios --simulator` **성공**(camera/image_picker/flutter_image_compress pod 통합).
- 백엔드는 선행 PR에서 라이브 E2E(presign→S3→confirm→analyses=success) 검증 완료.

### 알려진 제약 / 후속 (낮음)
- **분석중 벌 아이콘 = 이모지(🐝)** → 디자인 벌 SVG/asset로 교체 권장(플랫폼별 글리프 차이·tint 불가).
- **레포트 시각 포맷 수기 조립**(am/pm + 상대일, ko 전용) → en(Phase 2) 도입 시 intl `DateFormat`로.
- **재시도 시 S3 고아 이미지**: 재시도마다 새 presign/confirm(새 imageId) → 실패 전 업로드분이 고아로 남음(S3 lifecycle로 정리). 쿼터 중복 소진은 없음(create 도달 전 실패 시 quota 미소모).
- **capturedAt = confirm 시점 now**(갤러리 원본 촬영시각 미보존).
- recommendations·remaining은 백엔드 보강 선행 필요(클라 폴백/허용량 표기로 대응 중).

## 후속 작업 (Follow-up)
- 벌통 등록 풀스크린 폼·수정, 온보딩/로그인 디자인 미세 정합.
- `GET /v1/hives` latestAnalysis 포함(홈 N+1) · `/subscriptions/me` remaining · analysis recommendations 반환.
- 전역 진단 이력 탭(현재 hiveId별 조회 한계).

## 참조
- 권위 가이드: `apps/mobile/CLAUDE.md`(§8 카메라/이미지, §17 패키지) · 백엔드 계약: `docs/01-development/frontend-api-integration.md`(§3 이미지, §4 분석)
- 디자인: Figma `nxpjoTDvnfAAAnsW2iOXcy`(카메라 49:538 / 검토 49:571 / 분석중 19:315 / 레포트 24:12) · 핸드오프 `docs/06-design-handoff/2026-06-09-mobile-app-mvp.md`
