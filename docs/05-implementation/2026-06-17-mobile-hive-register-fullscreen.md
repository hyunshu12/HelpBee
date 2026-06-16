# 2026-06-17 — 벌통 등록 풀스크린 폼 (바텀시트 → 전용 화면)

> PR: (예정) · 브랜치: `feature/mobile-hive-register-fullscreen` → develop · 머지일: (예정)
> 선행: [2026-06-17-mobile-analysis-flow.md](./2026-06-17-mobile-analysis-flow.md)(진단 흐름)

## 범위 (Scope)

벌통 등록을 바텀시트에서 **Figma 풀스크린 폼(15:2)**으로 교체. 히어로 배너 + 이름*(필수) / 위치(+GPS 버튼) / 설치일*(날짜 선택, 필수) / 메모 + 등록하기. 데이터 계층은 `installedAt`를 이미 지원해 **설치일까지 실제 저장**.

## 산출물 (Deliverables)
- `features/hives/presentation/create_hive_screen.dart` (신규) — `CreateHiveScreen`(풀스크린 Form) + `createHiveAndNotify`(라우트 push + 성공 스낵). 필드: 이름(AppTextField·필수 검증) / 위치(주소 텍스트 + 꿀색 GPS 버튼) / 설치일(`showDatePicker`, 미선택 시 인라인 에러) / 메모(멀티라인). 히어로 배너는 honey 그라데이션 + `hive` 아이콘(실사진 에셋은 후속).
- `features/hives/presentation/create_hive_sheet.dart` **삭제**(바텀시트 폐기, `createHiveAndNotify`는 신규 화면으로 이동).
- `core/routing/route_paths.dart`·`app_router.dart` — `hiveCreate = /hives/new`(shell 위 push, `/hives/:id`보다 **먼저** 등록해 `new`가 :id로 안 잡히게).
- `features/hives/presentation/hives_list_controller.dart` — `createHive`에 `installedAt` 파라미터 추가(repo로 pass-through; api/repo는 기존 지원).
- 호출처 import 갱신: `home_screen.dart`(+ 액션), `hives_list_view.dart`(빈 상태 CTA) → 신규 화면. (GPS 버튼은 geolocation 후속이라 현재 `comingSoon`.)
- `l10n/app_ko.arb` — 등록 화면 키(placeholder/위치 힌트/날짜 힌트/메모 placeholder/접근성/설치일 필수 메시지). 하드코딩 없음, 접근성(GPS·날짜 Semantics).

## 검증 (Verification)
- `flutter analyze` **0** · `flutter test` **30 pass** · `flutter build ios --simulator` **성공**.
- 백엔드 `POST /v1/hives`는 `installedAt`(ISO) 수용(기존 계약). 좌표는 미설정(쌍 규칙상 둘 다 생략).

### 알려진 제약 / 후속 (낮음)
- **GPS 버튼 = comingSoon**: 실제 현재 위치 채움은 `geolocator` + 위치 권한 도입(후속). 현재는 위치를 주소 텍스트로 입력.
- **히어로 배너 = 그라데이션+아이콘**(Figma는 벌집 실사진) → 디자인 에셋 번들 후 교체.
- 벌통 **수정(편집)** 화면 미구현(상세 ⋮ 수정은 여전히 comingSoon) — api/repo는 `update(installedAt 포함)` 지원하므로 동일 폼 재사용으로 후속.

## 후속 작업 (Follow-up)
- 벌통 수정 화면(등록 폼 재사용) · geolocator 위치 채움 · 히어로 실사진 에셋.
- 온보딩/로그인 디자인 미세 정합.

## 참조
- 권위 가이드: `apps/mobile/CLAUDE.md` · 백엔드 계약: `docs/01-development/frontend-api-integration.md`(§2 Hives)
- 디자인: Figma `nxpjoTDvnfAAAnsW2iOXcy` 벌통등록(15:2)
