# docs/05-implementation — 구현 완료 기록 (Implementation Log)

이 디렉터리는 **PR 머지된 구현의 영구 기록**이다.
cold-pickup AI / 신규 합류한 사람이 "지금까지 무엇이 구현됐는지" 한눈에 보는 인덱스 역할을 한다.

git log를 뒤지지 말고 여기를 먼저 읽자.

---

## 파일명 규칙

```
YYYY-MM-DD-{topic-kebab-case}.md
```

- 날짜: PR 머지된 (또는 머지 예정) 날짜
- topic: 구현 주제. 짧고 검색 가능하게 (예: `database-schema`, `api-auth-hives`, `ui-tokens-core-components`)

## 작성 시점

1. **PR 머지 직후**: 같은 브랜치에서 추가 또는 후속 PR로 작성.
2. **큰 PR은 머지 전 동시 작성**: 구현과 함께 같은 PR에 포함하면 리뷰어가 변경 의도를 빠르게 파악.

## 템플릿

```markdown
# YYYY-MM-DD — {제목}

> PR: #N · 브랜치: feature/xxx → develop · 머지일: YYYY-MM-DD

## 범위 (Scope)

한 줄로 무엇을 했는지.

## 산출물 (Deliverables)

- 파일 경로 + 한 줄 설명
- ...

## 검증 (Verification)

- 어떤 명령으로 통과 확인했는지
- 알려진 제약 / 후속 검증 항목

## 후속 작업 (Follow-up)

- 이 구현으로 풀린 의존성 (다음 가능한 PR)
- 분리한 범위 밖 항목

## 참조

- 권위 가이드: `domain/CLAUDE.md`
- 관련 마이그레이션 / 문서 링크
```

## 작성 의무

각 PR 머지 시 **하나의 기록 파일**을 추가한다.
의무 항목:
- [ ] 산출물 파일 경로 누락 없이 나열
- [ ] 알려진 제약 / 후속 작업 명시 (있다면)
- [ ] 권위 CLAUDE.md 또는 관련 docs 링크
- [ ] 루트 `CLAUDE.md` "참고 문서 가이드" 섹션 갱신 (필요 시)

## 인덱스

| 날짜 | 주제 | PR | 파일 |
|---|---|---|---|
| 2026-05-11 | Database 9-table schema + types 동기화 + impl log 체계 도입 | (TBD) | [2026-05-11-database-schema.md](./2026-05-11-database-schema.md) |
| 2026-06-08 | v0.1.0 YOLO HP 스윕 결과 + 최종 config 결정 (copy_paste no-op 발견 → AIHUB 정정) | (이 PR) | [2026-06-08-hp-sweep.md](./2026-06-08-hp-sweep.md) |

(새 기록 추가 시 위 표 갱신)
