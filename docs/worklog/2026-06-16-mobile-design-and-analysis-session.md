# 2026-06-16 작업 정리 — 모바일 디자인 정합 + 분석 백엔드 온라인화

> 한 줄 결론: PR #28(벌통 CRUD) 머지 이후, **하단 네비 셸 + 설정/이력/프로필**, **분석 백엔드를 실제 동작까지 온라인화**(AI 서버+S3, E2E 검증), **홈·벌통상세를 Figma에 맞춰 재구성 + 분석 데이터 계층**, **적대적 리뷰로 검증·수정**까지. 새 PR로 올림.

## 진행 순서
1. **로컬 스택 기동** — brew Postgres/Redis(Docker 미설치) + `helpbee` DB 생성·마이그레이션·시드, `apps/api/.env`(강시크릿), API :3001 라이브 검증(로그인→벌통→생성).
2. **Phase 1** — StatefulShellRoute 하단 탭(벌통/이력/설정), 양봉장→벌통 용어, 설정/프로필/이력 화면, 테마 토글, subscriptions.
3. **사용자 피드백** — "네비바 없음/디자인 다름/벌통 용어/분석까지". Figma 디자인 파일 수령.
4. **Figma 브릿지** — 공식 Figma MCP가 Starter 한도 → `cursor-talk-to-figma` 로컬 소켓 브릿지(:3055) + MCP 등록 + 재시작 → 채널 join 후 디자인 직접 read.
5. **분석 백엔드 온라인화** — AWS 자격증명 확인, `helpbee-images-dev` 버킷 생성, AI 의존성 설치, best.onnx 다운로드, `apps/ai/.env`, uvicorn :8000, **E2E 실검증**(presign→S3→confirm→analyze=success, 실제 YOLO).
6. **디자인 정합** — 홈(양봉장 현황/쿼터배너/풍부한 카드/진단하기 FAB) + 벌통 상세(위험요약/위치/이력 타임라인/⋮/다시촬영) Figma대로 재구성. 분석 데이터 계층 추가.
7. **적대적 리뷰** — 4렌즈 + 발견별 재검증 → 확정 22건 중 실결함 12건 수정.

## 주요 결정
| 결정 | 근거 |
|---|---|
| 홈 타이틀 "양봉장 현황" 유지, 카드/등록은 "벌통" | Figma 디자인(양봉장=화면, 벌통=개체) |
| 분석 추이 = **타임라인**(차트 아님) | 실제 Figma 벌통상세가 타임라인. 핸드오프 문서(차트)와 차이 → Figma 우선 |
| 쿼터 "남음"→허용량 표현 | API가 remaining 미제공(allowance만). 오정보 방지 |
| 홈 N+1(벌통당 최신분석) 수용 + 후속 | 정석은 `/hives`에 latestAnalysis 포함(백엔드). lazy 리스트라 현재 동작 OK |
| Figma 읽기 = cursor-talk-to-figma 브릿지 | 공식 MCP Starter 한도 우회(로컬 소켓) |

## 검증
- `flutter analyze` 0 / `flutter test` 27 / iOS 시뮬 빌드 성공
- 분석 백엔드 라이브 E2E(curl) 성공
- 적대적 워크플로우 통과(실결함 수정)

## 현재 서버/환경 (테스트용)
- brew Postgres/Redis · API :3001 · AI :8000 (세션 종료 시 API/AI는 재기동 필요; 런북 = `docs/05-implementation/...online.md` §2 + 메모리 local-dev-stack)
- 모바일: `cd apps/mobile && flutter run` → `beekeeper1@helpbee.local` / `helpbee-dev-2026`

## 다음 단계
1. **분석 흐름 5화면**(촬영할 벌통 선택→카메라→검토→분석중→레포트) — camera/image 패키지 + iOS 권한. 백엔드는 준비됨.
2. 벌통 등록 풀스크린·수정·온보딩/로그인 디자인 정합.
3. (백엔드) `/hives` latestAnalysis 포함 + `/subscriptions/me` remaining.

## 참조
- 기술 기록: `docs/05-implementation/2026-06-16-mobile-app-shell-and-analysis-online.md`
- 계약: `docs/01-development/frontend-api-integration.md` · 디자인: `docs/06-design-handoff/2026-06-09-mobile-app-mvp.md`
