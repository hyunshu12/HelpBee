# 06 · 디자인 핸드오프 (Design Handoff)

디자이너 협업용 화면/페이지 핸드오프 문서를 모읍니다. 각 문서는 **플로우(FigJam) + 화면별 상세 스펙**으로 구성되며, 디자이너가 바로 Figma 시안에 착수할 수 있는 수준으로 작성됩니다.

> 작성 방식: 화면 인벤토리 → 화면/페이지별 상세 스펙(병렬 작성) → 완전성 검증(누락 화면·상태·SEO·법적 요건 탐지) → 보강. 검증 단계에서 발견된 누락은 🆕로 표시.

## 인덱스

| 영역 | 문서 | FigJam | 범위 | 항목 수 |
|---|---|---|---|---|
| 📱 모바일 앱 | [2026-06-09-mobile-app-mvp.md](2026-06-09-mobile-app-mvp.md) | [화면 플로우](https://www.figma.com/board/NDQUiBftF6FyaLEVvBST2D) | MVP / P0 | 18 화면 |
| 🌐 웹사이트 | [2026-06-09-web-mvp.md](2026-06-09-web-mvp.md) | [사이트맵 & 전환 퍼널](https://www.figma.com/board/r76TJR4eVOgl7KqCIVbXaZ) | 마케팅/콘텐츠 Phase 1 | 19 항목 |

## 우선순위 (디자인 착수 순서 제안)

1. **앱 핵심 가치 동선** — 홈 → 촬영할 벌통 선택 → 카메라 → 촬영 확인 → 분석 중 → 진단 결과 (5초 룰)
2. **앱 인증/온보딩** — 스플래시 · 온보딩 · 로그인 · 회원가입
3. **앱 벌통/설정** — 홈(목록) · 벌통 상세 · 등록/수정 · 설정
4. **웹 랜딩 + 전환** — 홈/랜딩 · 작동 원리 · 다운로드 · 문의
5. **웹 콘텐츠/법적** — 블로그 · 회사소개 · 개인정보/약관

## 착수 전 공통 확정 사항 (각 문서 5장 참고)

- **앱**: 이미지 리사이즈 기준 통일 · 진단 실패 표현(≠watch) · quota 차단 단일 컴포넌트 · 오프라인 큐 진입점 · 홈 검색/정렬 · 약관 동의 · 프로필 편집 범위
- **웹**: 색상 토큰 단일화(bee-black hex 충돌 정정) · GA4 이벤트 사전 · 쿠키 동의 게이팅 · SEO 인프라(sitemap/robots/RSS) · en noindex · @helpbee/ui 컴포넌트 분담 · PIPA(문의 동의·필수 고지) · 데모 영상/가격 확정

## 참고

- 앱 상세 도메인 가이드: [apps/mobile/CLAUDE.md](../../apps/mobile/CLAUDE.md)
- 웹 상세 도메인 가이드: [apps/web/CLAUDE.md](../../apps/web/CLAUDE.md)
- 디자인 시스템: [packages/ui/CLAUDE.md](../../packages/ui/CLAUDE.md)
- 요구사항: [docs/00-requirement/PRD.md](../00-requirement/PRD.md)
