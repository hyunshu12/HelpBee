# 2026-06-17 — 벌통 수정 화면 (등록 폼 재사용) + ⋮수정 dead-end 제거

> PR: (예정) · 브랜치: `feature/mobile-hive-edit` → develop · 머지일: (예정)
> 선행: [2026-06-17-mobile-hive-register-fullscreen.md](./2026-06-17-mobile-hive-register-fullscreen.md)

## 범위 (Scope)

벌통 상세 ⋮ "수정"이 `comingSoon` dead-end였던 것을 실제 **수정 화면**으로 연결. 직전 등록 화면을 **등록/수정 공용 폼**으로 일반화해 재사용.

## 산출물 (Deliverables)
- `features/hives/presentation/hive_form_screen.dart` (신규, `create_hive_screen.dart`를 일반화·대체) — `HiveFormScreen({Hive? initial})`: `initial` null=등록 / 있으면 **수정**(컨트롤러 prefill·CTA "저장"·title "벌통 수정"). 헬퍼 `createHiveAndNotify(context)` + `editHive(context, hive)`(수정된 Hive 반환).
- `create_hive_screen.dart` **삭제**(공용 폼으로 대체).
- `features/hives/presentation/hives_list_controller.dart` — `updateHive(id, {...})` 추가(repo.updateHive 호출 후 리스트 내 해당 row 교체, 미로드 시 재fetch).
- `core/routing/route_paths.dart`·`app_router.dart` — `hiveEdit = /hives/edit`(extra=Hive, `/hives/:id`보다 먼저 등록). 등록 라우트는 `HiveFormScreen()`, 수정은 `HiveFormScreen(initial: extra as Hive)`(누락 시 `_FlowMissing`→홈).
- `features/hives/presentation/hive_detail_screen.dart` — ⋮ "수정" → `editHive` push → 성공 시 `hiveDetailProvider` invalidate + "벌통 정보를 수정했어요" 스낵. `_comingSoon` 제거(미사용).
- 호출처 import 갱신: home_screen, hives_list_view (create_hive_screen→hive_form_screen).
- `l10n/app_ko.arb` — `hiveEditTitle`("벌통 수정"), `hiveUpdated`. 기존 `commonSave`("저장") 재사용.

## 검증 (Verification)
- `flutter analyze` **0** · `flutter test` **30 pass** · `flutter build ios --simulator` **성공**.
- 수정은 `PATCH /v1/hives/:id`(부분 업데이트, installedAt 포함) 기존 계약 사용.

### 알려진 제약 / 후속 (낮음)
- 등록 화면과 동일한 후속 공유: GPS 버튼 geolocation(현재 comingSoon), 히어로 실사진 에셋.
- 좌표(lat/lng)는 폼에서 미편집(주소 텍스트만) — geolocator 도입 시 함께.

## 후속 작업 (Follow-up)
- geolocator 위치 채움 · 히어로 실사진 · 온보딩/로그인 디자인 미세 정합.

## 참조
- 권위 가이드: `apps/mobile/CLAUDE.md` · 백엔드 계약: `docs/01-development/frontend-api-integration.md`(§2 Hives PATCH)
- 디자인: Figma `nxpjoTDvnfAAAnsW2iOXcy` 벌통등록(15:2) 폼 재사용
