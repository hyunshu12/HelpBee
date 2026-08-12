# 2026-08-12 — 한국어 어절 중간 줄바꿈 수정 (web + mobile)

> PR: #52 · 브랜치: bugfix/korean-text-wrapping → develop · 머지일: (머지 시 기입)

## 범위 (Scope)

`word-break` 기본값이 한글을 음절 단위로 끊어 어절 중간이 갈라지던 문제를 웹·모바일 양쪽에서 잡았다.

## 배경 (Why)

랜딩 홈의 인용 문단이 `... 벌통 건강을 쉽 / 고 정확하게 ... 서비스입니 / 다.` 로 렌더링되고 마지막 줄에 "다." 두 글자만 남는 고아 줄이 생겼다. 브라우저에서 실측한 결과 **홈 화면에서만 6개 문단**이 같은 증상이었다 — 특정 문단이 아니라 사이트 전반에 한국어 줄바꿈 기준이 없던 것. 모바일 온보딩도 `... 여부를 즉 / 시 확인해 드립니다`로 동일했다.

## 산출물 (Deliverables)

- `apps/web/src/app/globals.css` — body에 `word-break: keep-all` + `overflow-wrap: break-word`. 후자는 keep-all이 끊지 못하는 긴 URL 등이 컨테이너를 넘치지 않게 하는 안전판.
- `apps/web/src/app/[locale]/page.tsx` — 홈 인용 문단에 `text-balance`(줄 길이 균등 분배) 추가, 줄 간격 1.625 → 1.5.
- `apps/mobile/lib/core/text/korean_wrap.dart` (신규) — `keepAll()`. 연속된 한글 음절 사이에 WORD JOINER(U+2060)를 삽입해 어절 중간 줄바꿈을 막는다.
- `apps/mobile` 9개 화면 호출부에 `keepAll()` 적용 — onboarding, analyzing, photo_review, capture, hives_list, analysis_history, quota_banner, hive_detail, report.
- `apps/mobile/lib/features/hives/presentation/hive_detail_screen.dart` — **실패 분석 행 가로 오버플로 수정**(아래 별도 항목).
- `apps/mobile/test/hive_detail_timeline_test.dart` (신규) — 그 오버플로 회귀 테스트.

### 곁다리로 잡은 버그 — 실패 분석 행 오버플로 233px

시뮬레이터에서 확인하다 발견했다. 타임라인 행의 값 텍스트는 성공이면 `"90점 (위험)"`처럼 짧지만
실패면 `errAiUnavailable` **문장 전체**가 들어간다. 이게 라벨과 같은 `Row`에 **폭 제한 없이**
놓여 있어서, flex 없는 자식이 폭을 먼저 다 가져가고 `Expanded` 라벨이 0으로 밀렸다. 그 결과
"AI 자동 정밀 판독"이 한 글자씩 세로로 쌓이고 행이 233px 넘쳤다.

실패일 때만 `Column`으로 바꿔 문장을 라벨 아래 줄로 내렸다. 성공 행의 `라벨 ─ 점수` 좌우 배치는 유지.
이 PR과 무관하게 원래 있던 버그다(2026-07-04자 실패 행에서도 재현).

## 주요 결정 (Decisions)

- **웹은 전역, 모바일은 호출부.** 웹은 CSS 한 줄로 전 페이지에 적용되지만, 모바일은 공유 위젯(`EmptyState` 등) 내부에 넣으면 렌더링 텍스트에 조이너가 섞여 기존 `find.text()` 단언 12개가 깨진다. 그래서 호출부에만 적용했다.
- **Flutter에는 keep-all 대응 API가 없다.** SDK를 확인했고 `LineBreakStrictness` 류의 노출된 API가 없어 WORD JOINER 삽입이 유일한 실용적 우회다.
- **긴 덩어리 가드.** 한글이 20음절 넘게 이어지면 조이너를 넣지 않는다. 끊을 자리를 전부 없애면 줄 폭보다 긴 덩어리가 잘리지 못하고 넘치기 때문.
- **`md:leading-*`은 중복이 아니다.** Tailwind의 `md:text-3xl`이 자체 line-height(36px)를 함께 지정하고 미디어쿼리가 우선하므로, 비반응형 `leading-*`만으로는 데스크톱에서 덮인다. 기존 코드의 `md:leading-relaxed`가 있던 이유.

## 검증 (Verification)

- web: `pnpm --filter @helpbee/web lint / type-check / build` 통과, 25 SSG green.
- web: 1440px·390px에서 어절 중간 잘림 **6건 → 0건** (DOM Range로 줄별 폭 실측). `keep-all`이 전역이라 pricing / contact / blog / blog[slug] / terms 를 모바일 폭에서 확인 — 가로 넘침 없음.
- mobile: `dart analyze` 0 issues, `flutter test` 33/33 통과, iOS 26.5 시뮬레이터 육안 확인.

### 알려진 제약

- `dart format`을 돌리지 않았다. develop 기준이 미포맷 상태라(루트 CLAUDE.md에서 CI 제외 명시) 실행하면 무관한 파일 22개가 재포맷된다.
- 모바일은 조이너가 실제 문자열에 섞이므로, 앞으로 해당 텍스트를 `find.text()`로 단언하려면 `keepAll()`을 거쳐 비교해야 한다.

## 후속 작업 (Follow-up)

- 모바일의 짧은 라벨들은 줄바꿈이 일어나지 않아 미적용 — 새 화면 추가 시 본문 성격 문구면 `keepAll()`을 함께 쓸 것.
- `packages/ui` / `apps/admin`에도 같은 기준이 필요한지 검토 (admin은 한국어 본문이 적어 우선순위 낮음).

## 참조

- `apps/web/CLAUDE.md` §6 디자인 톤 (본문 18px+, 장년층 가독성)
- `apps/mobile/CLAUDE.md` §3 UX 원칙, §13 i18n
