# HelpBee GitHub Workflow 계획

## 📋 개요

HelpBee 모노레포의 자동화 워크플로우입니다.
- **CI (지속적 통합)**: PR 시 린트, 타입 체크, 테스트
- **CD (지속적 배포)**: main 브랜치 머지 시 자동 배포

---

## 🔄 Git 브랜칭 전략

### 브랜치 구조

```
main (프로덕션)
  ↑
  └─ release/* (릴리스 브랜치)
       ↑
       └─ develop (개발 브랜치)
            ↑
            └─ feature/* (기능 브랜치)
            └─ bugfix/* (버그 수정)
            └─ docs/* (문서)
```

### 브랜치 네이밍 규칙

| 유형 | 패턴 | 예시 |
|---|---|---|
| 기능 | `feature/{feature-name}` | `feature/user-authentication` |
| 버그 수정 | `bugfix/{bug-name}` | `bugfix/image-upload-error` |
| 릴리스 | `release/v{version}` | `release/v0.1.0` |
| 긴급 수정 | `hotfix/{issue}` | `hotfix/api-crash` |
| 문서 | `docs/{doc-name}` | `docs/api-guide` |

---

## 🛠 GitHub Actions Workflows

### 1️⃣ CI 워크플로우 (`.github/workflows/ci.yml`)

**트리거**: 
- feature/*, bugfix/* 브랜치에 PR 생성 시
- PR이 develop으로의 머지를 목표할 때

**작업**:
1. **코드 린트** - ESLint 실행
2. **타입 체크** - TypeScript 컴파일 확인
3. **단위 테스트** - Jest 테스트 실행
4. **영향받은 패키지만 테스트** - Turborepo `affected` 활용
5. **테스트 커버리지 리포트** - 코드 커버리지 확인

```yaml
# 구조 (실제 내용은 아래 추가 섹션에)
name: CI
on:
  pull_request:
    branches: [develop, main]
    paths-ignore:
      - '**.md'
      - '.env.example'

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: pnpm/action-setup@v2
      - uses: actions/setup-node@v3
      - run: pnpm install
      - run: pnpm lint

  type-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: pnpm/action-setup@v2
      - uses: actions/setup-node@v3
      - run: pnpm install
      - run: pnpm type-check

  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_PASSWORD: test
      redis:
        image: redis:7-alpine
    steps:
      - uses: actions/checkout@v3
      - uses: pnpm/action-setup@v2
      - uses: actions/setup-node@v3
      - run: pnpm install
      - run: pnpm test

  api-python-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: '3.10'
      - run: pip install -r apps/ai/requirements.txt
      - run: pytest apps/ai/
```

---

### 2️⃣ 병합 전 체크 워크플로우 (`.github/workflows/pre-merge-check.yml`)

**트리거**: 
- PR이 develop 또는 main으로의 머지를 시도할 때

**작업**:
1. 모든 CI 작업 완료 확인
2. 코드 리뷰 승인 수 확인 (최소 1명)
3. 병합 전 상태 체크

```yaml
name: Pre-Merge Check
on:
  pull_request:
    branches: [develop, main]

jobs:
  check-reviews:
    runs-on: ubuntu-latest
    steps:
      - name: Check minimum reviews
        uses: actions/github-script@v6
        with:
          script: |
            const pr = context.payload.pull_request;
            const reviews = await github.rest.pulls.listReviews({
              owner: context.repo.owner,
              repo: context.repo.repo,
              pull_number: pr.number,
            });
            const approvals = reviews.data.filter(r => r.state === 'APPROVED').length;
            if (approvals < 1) {
              core.setFailed('Minimum 1 approval required');
            }
```

---

### 3️⃣ Develop 브랜치 테스트 및 빌드 (`.github/workflows/develop-test.yml`)

**트리거**: 
- develop 브랜치에 푸시될 때 (PR 머지 후)

**작업**:
1. 전체 린트 및 타입 체크
2. 전체 테스트 실행
3. 전체 빌드 테스트
4. 빌드 결과를 `.github/` 아티팩트로 저장

```yaml
name: Develop Test Build
on:
  push:
    branches: [develop]

jobs:
  full-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: pnpm/action-setup@v2
      - uses: actions/setup-node@v3
      - run: pnpm install
      - run: pnpm build
      - run: pnpm test
      - uses: actions/upload-artifact@v3
        with:
          name: build-artifacts
          path: |
            apps/web/.next
            apps/admin/.next
            apps/api/dist
```

---

### 4️⃣ 릴리스 준비 워크플로우 (`.github/workflows/release.yml`)

**트리거**: 
- `release/v*` 브랜치가 생성될 때

**작업**:
1. 버전 번호 추출 (v0.1.0 → 0.1.0)
2. CHANGELOG 자동 생성
3. GitHub Release 생성
4. Docker 이미지 빌드 (프로덕션 준비)
5. 배포 승인 대기

```yaml
name: Release Preparation
on:
  pull_request:
    types: [opened, reopened]
    branches: [main]

jobs:
  prepare-release:
    if: startsWith(github.head_ref, 'release/')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Extract version
        run: |
          VERSION=$(echo ${{ github.head_ref }} | sed 's/release\///')
          echo "VERSION=$VERSION" >> $GITHUB_ENV
      
      - name: Create GitHub Release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: ${{ env.VERSION }}
          release_name: Release ${{ env.VERSION }}
          draft: true
```

---

### 5️⃣ 프로덕션 배포 (`.github/workflows/deploy-prod.yml`)

**트리거**: 
- main 브랜치에 푸시될 때 (release PR이 머지될 때)

**작업**:
1. 전체 빌드 및 테스트
2. Docker 이미지 빌드 & 푸시 (Docker Hub / ECR)
3. 배포 환경에 자동 배포 (Vercel/Railway/EC2)
4. 배포 완료 알림 (Slack/Discord)

```yaml
name: Deploy to Production
on:
  push:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      
      - name: Log in to Container Registry
        uses: docker/login-action@v2
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Build and push API image
        uses: docker/build-push-action@v4
        with:
          context: ./apps/api
          push: true
          tags: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}/api:latest
      
      - name: Build and push AI image
        uses: docker/build-push-action@v4
        with:
          context: ./apps/ai
          push: true
          tags: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}/ai:latest
      
      - name: Deploy to production
        env:
          DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
        run: |
          # 배포 스크립트 실행 (예: Vercel 배포)
          # curl -X POST https://api.vercel.com/v1/deployments \
          #   -H "Authorization: Bearer $DEPLOY_TOKEN" \
          #   -H "Content-Type: application/json" \
          #   -d '{"name": "helpbee"}'
          echo "Deploying to production..."
      
      - name: Notify Slack
        if: always()
        uses: 8398a7/action-slack@v3
        with:
          status: ${{ job.status }}
          text: 'Production deployment ${{ job.status }}'
          webhook_url: ${{ secrets.SLACK_WEBHOOK }}
```

---

### 6️⃣ 코드 품질 체크 (`.github/workflows/quality.yml`)

**트리거**: 
- 모든 PR

**작업**:
1. 보안 취약점 스캔 (Dependabot)
2. 코드 품질 분석 (SonarQube 또는 Codacy)
3. 번들 크기 모니터링
4. 성능 메트릭 추적

```yaml
name: Code Quality
on:
  pull_request:
    branches: [develop, main]

jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: github/super-linter@v4
        env:
          DEFAULT_BRANCH: main
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  
  bundle-size:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: pnpm/action-setup@v2
      - uses: actions/setup-node@v3
      - run: pnpm install
      - run: pnpm build
      - name: Comment bundle size
        uses: actions/github-script@v6
        with:
          script: |
            console.log('Bundle size check would run here');
```

---

## 📝 PR 체크리스트

모든 PR에는 다음을 포함해야 합니다:

```markdown
## 변경 사항 설명
<!-- 무엇을 변경했는가 -->

## 관련 이슈
Closes #123

## 테스트 방법
<!-- 어떻게 테스트했는가 -->

## 스크린샷 (UI 변경 시)
<!-- 변경 전/후 스크린샷 -->

## 체크리스트
- [ ] 로컬에서 테스트했습니다
- [ ] 새 의존성을 추가하지 않았습니다
- [ ] 타입 에러가 없습니다
- [ ] 린트 에러가 없습니다
- [ ] 테스트를 작성했습니다
- [ ] 문서를 업데이트했습니다
```

---

## 🚀 배포 환경 설정

### Staging (develop 브랜치)
- **URL**: https://staging.helpbee.dev
- **트리거**: develop 브랜치 푸시
- **자동 배포**: Yes
- **자동 롤백**: Yes (실패 시)

### Production (main 브랜치)
- **URL**: https://helpbee.dev
- **트리거**: main 브랜치 푸시 (release PR 머지 후)
- **자동 배포**: Yes (수동 승인 후)
- **자동 롤백**: Yes (에러 감지 시)

---

## 🔐 보안 설정

### Protected Branches

#### `main` 브랜치
- ✅ Require a pull request before merging
- ✅ Require 1 approval (최소)
- ✅ Dismiss stale pull request approvals when new commits are pushed
- ✅ Require status checks to pass before merging
  - CI 워크플로우 완료
  - 코드 품질 체크 완료
- ✅ Require branches to be up to date before merging
- ✅ Restrict who can push to matching branches
  - Only admins/maintainers

#### `develop` 브랜치
- ✅ Require a pull request before merging
- ✅ Require 1 approval (권장)
- ✅ Require status checks to pass before merging
- ✅ Require branches to be up to date before merging

---

## 📊 Secrets & Environment Variables

### GitHub Secrets 설정 필요

```
SLACK_WEBHOOK          # Slack 알림용
DEPLOY_TOKEN           # 배포 인증
DOCKER_USERNAME        # Docker Hub 계정
DOCKER_PASSWORD        # Docker Hub 비밀번호
OPENAI_API_KEY         # OpenAI API 키 (테스트용)
DATABASE_URL_TEST      # 테스트용 DB URL
```

---

## 📌 워크플로우 실행 흐름

### 일반적인 개발 사이클

```
1. feature 브랜치 생성
   git checkout -b feature/my-feature

2. 코드 작성 및 커밋
   git add .
   git commit -m "feat: add my feature"

3. PR 생성 (develop으로)
   → CI 자동 실행 (린트, 테스트 등)
   → 코드 리뷰 요청

4. 리뷰 및 개선
   → 피드백 반영
   → CI 재실행

5. PR 승인 및 머지
   → develop 브랜치에 자동 통합

6. 정기 릴리스 (스프린트 끝)
   → release/v0.1.0 브랜치 생성
   → PR 생성 (main으로)
   → Release 노트 생성
   → main 브랜치 머지

7. 프로덕션 배포
   → Deploy 워크플로우 자동 실행
   → Docker 이미지 빌드/푸시
   → 프로덕션 서버 배포
   → Slack 알림
```

---

## 🔄 Turborepo + GitHub Actions 최적화

### 변경된 패키지만 테스트

```bash
# 로컬에서 영향받은 패키지 확인
pnpm turbo run test --filter='...@helpbee/types'

# CI에서는 자동으로:
# - git diff를 통해 변경 감지
# - 변경된 앱/패키지만 빌드/테스트
```

### 빌드 캐싱

```yaml
# .github/workflows/ci.yml
- uses: actions/cache@v3
  with:
    path: |
      .turbo
      node_modules
      .next
    key: ${{ runner.os }}-turbo-${{ github.sha }}
    restore-keys: |
      ${{ runner.os }}-turbo-
```

---

## 📈 모니터링 & 알림

### Slack 알림 설정

```
- PR 생성/리뷰 필요
- CI 실패
- 배포 성공/실패
- 보안 취약점 감지
```

### GitHub Issues 자동화

```yaml
# PR 머지 시 관련 이슈 자동 종료
closes: #123
fixes: #456
```

---

## ✅ 체크리스트 (구현 시)

- [ ] `.github/workflows/ci.yml` 작성 및 테스트
- [ ] `.github/workflows/develop-test.yml` 작성
- [ ] `.github/workflows/deploy-prod.yml` 작성
- [ ] Secret 설정 (SLACK_WEBHOOK, DEPLOY_TOKEN 등)
- [ ] Protected branches 설정 (main, develop)
- [ ] Slack 연동 설정
- [ ] 팀과 워크플로우 공유 및 교육

