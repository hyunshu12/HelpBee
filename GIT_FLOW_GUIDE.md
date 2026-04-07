# HelpBee Git Flow 가이드

## 브랜치 구조

```
main        → 프로덕션 (배포된 코드)
develop     → 개발 통합 (기능 PR을 여기로)
feature/*   → 기능 개발
bugfix/*    → 버그 수정
release/*   → 릴리스 준비
hotfix/*    → 긴급 버그 수정
```

> `main`과 `develop`은 직접 push 금지. 반드시 PR을 통해 머지.

---

## 처음 시작할 때 (최초 1회)

```bash
# 저장소 클론
git clone https://github.com/hyunshu12/HelpBee.git
cd HelpBee

# develop 브랜치 가져오기
git checkout develop
```

---

## 기능 개발 (가장 자주 쓰는 흐름)

### 1. develop 최신 상태로 업데이트
```bash
git checkout develop
git pull origin develop
```

### 2. feature 브랜치 생성
```bash
git checkout -b feature/기능이름

# 예시
git checkout -b feature/user-auth
git checkout -b feature/image-upload
git checkout -b feature/hive-dashboard
```

### 3. 작업 후 커밋
```bash
git add .
git commit -m "feat: 로그인 기능 추가"
```

### 4. 원격에 push
```bash
git push origin feature/기능이름
```

### 5. GitHub에서 PR 생성
- `feature/기능이름` → `develop` 으로 PR 생성
- 팀원 리뷰 요청 → 승인 → 머지

---

## 커밋 메시지 규칙

```
feat: 새 기능
fix: 버그 수정
docs: 문서 수정
style: 코드 포맷 (기능 변경 없음)
refactor: 리팩토링
test: 테스트 추가/수정
chore: 빌드, 설정 변경
```

**예시**
```bash
git commit -m "feat: 벌통 이미지 업로드 기능 추가"
git commit -m "fix: API 토큰 만료 오류 수정"
git commit -m "docs: README 설치 방법 업데이트"
```

---

## 버그 수정

```bash
git checkout develop
git pull origin develop
git checkout -b bugfix/버그이름

# 예시
git checkout -b bugfix/login-error

# 수정 후
git push origin bugfix/버그이름
# → develop으로 PR
```

---

## 릴리스 (배포 시)

```bash
# develop → release 브랜치 생성
git checkout develop
git pull origin develop
git checkout -b release/v0.1.0

# 버전 관련 수정 후
git push origin release/v0.1.0
# → main으로 PR 생성 → 머지 → 배포
```

---

## 긴급 버그 수정 (Hotfix)

프로덕션에서 심각한 버그 발생 시 `main`에서 직접 분기

```bash
git checkout main
git pull origin main
git checkout -b hotfix/버그이름

# 수정 후 main으로 PR
git push origin hotfix/버그이름

# main 머지 후, develop에도 반영
git checkout develop
git merge main
git push origin develop
```

---

## 브랜치 네이밍 규칙

| 유형 | 패턴 | 예시 |
|---|---|---|
| 기능 | `feature/설명` | `feature/user-auth` |
| 버그 | `bugfix/설명` | `bugfix/image-upload-fail` |
| 릴리스 | `release/v버전` | `release/v0.1.0` |
| 긴급 | `hotfix/설명` | `hotfix/api-crash` |

---

## 자주 쓰는 명령어 모음

```bash
# 현재 상태 확인
git status
git branch -a

# 최신 코드 받기
git pull origin develop

# 브랜치 목록 보기
git branch

# 브랜치 삭제 (머지 완료 후)
git branch -d feature/기능이름

# 원격 브랜치 삭제
git push origin --delete feature/기능이름

# 변경사항 임시 저장 (작업 중 브랜치 이동 시)
git stash
git stash pop
```

---

## PR 체크리스트

PR 올리기 전 확인:

- [ ] `develop` 최신 상태를 내 브랜치에 반영했나?
- [ ] 로컬에서 정상 동작 확인했나?
- [ ] 커밋 메시지 규칙 지켰나?
- [ ] 관련 이슈 번호 PR 본문에 적었나? (`closes #123`)

---

## 문제 상황별 해결

### "이미 다른 브랜치에서 작업 중인데 브랜치를 바꿔야 해요"
```bash
git stash          # 현재 작업 임시 저장
git checkout 다른브랜치
# 작업 후 돌아올 때
git checkout 원래브랜치
git stash pop      # 임시 저장 복원
```

### "develop이 업데이트됐는데 내 브랜치에 반영하고 싶어요"
```bash
git checkout develop
git pull origin develop
git checkout feature/내브랜치
git merge develop
```

### "실수로 develop에 커밋했어요"
팀원에게 바로 알리고 함께 해결하세요.
