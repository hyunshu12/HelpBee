# HelpBee 테스트 시나리오

## L1: 단위 테스트 시나리오

### Auth Service
- 유효한 이메일/비밀번호로 회원가입 성공
- 중복 이메일로 회원가입 시 409 Conflict 반환
- 올바른 자격증명으로 로그인 시 JWT 토큰 발급
- 잘못된 비밀번호로 로그인 시 401 Unauthorized 반환
- 만료된 JWT 토큰 갱신 성공
- 유효하지 않은 refresh token으로 갱신 시 401 반환

### Analysis Service
- 유효한 이미지 URL로 분석 요청 성공
- risk_level이 low/medium/high/critical 중 하나임을 검증
- confidence_score가 0.0~1.0 범위임을 검증

## L2: 통합 테스트 시나리오

### 회원가입 → 로그인 플로우
1. POST /api/auth/register → 201 Created
2. POST /api/auth/login → 200 OK + tokens
3. GET /api/users/me (Authorization: Bearer {token}) → 200 OK

### 이미지 분석 플로우
1. 인증된 사용자가 벌통 등록
2. S3 Presigned URL 발급 요청
3. 이미지 업로드 (S3)
4. POST /api/analysis/ → 분석 결과 반환
5. 분석 결과 조회

## L3: E2E 시나리오

### 신규 양봉가 온보딩
- 회원가입 → 이메일 인증 → 로그인 → 벌통 등록 → 첫 분석

### 바로아 감염 진단 워크플로우
- 이미지 업로드 → 분석 대기 → 결과 확인 → 리포트 다운로드

## 불변 조건 (Invariants)

- JWT 없이 보호된 API 접근 불가
- 다른 사용자의 벌통/분석 결과 조회 불가
- 분석 결과의 infestation_rate는 항상 0.0~1.0
- 삭제된 사용자의 데이터 접근 불가
