# 2-Stage 재설계 — 계획 2: 서빙·스키마·앱 동기 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 스펙 §8·§9의 8~10단계 — 계획 1이 만든 `stage1.onnx`·`stage2.onnx`·`vdi.yaml`·`app/services/vdi.py`를 서빙에 연결하고, `vdi` 계약을 API/DB/모바일/어드민에 **이중 출력 → 이전 → 제거** 순서로 무중단 전파한다. 모바일 캡처·업로드 해상도(B1)와 API 이미지 패스스루도 이 계획에 포함.

**Architecture:** AI 서버에 `two_stage_engine.py`(Stage-1 ONNX 타일 검출 → 원본 크롭 → Stage-2 ONNX 64청크 → CAM)와 `vdi.py` 집계를 붙이고 `AnalysisResponse`를 확장한다. 배포 순서는 **① API/DB 관용화 → ② AI 이중 출력 → ③ 소비자 이전 → ④ 구 필드 제거**. `risk.py`/`risk.yaml`은 OpenAI 폴백·부스 앱용 shim으로 동결. N장 합산은 저장하지 않고 AI의 `POST /aggregate`(vdi.py 단일 소스)를 API가 읽기 시 호출한다.

**Tech Stack:** FastAPI + Pydantic v2 + onnxruntime + numpy/cv2 (AI), Hono + zod + Drizzle + vitest (API/DB), Flutter/dio (mobile, 수기 DTO — freezed 미사용), Next.js (admin).

**Spec:** `docs/superpowers/specs/2026-09-22-ai-two-stage-redesign-design.md` (v2.1 ACCEPTED). 계획 1: `2026-09-23-ai-two-stage-plan1-data-training.md`.

**실행 규칙(프로젝트):** 본체(Fable)가 계획·평가, 각 태스크 구현은 Opus 서브에이전트. 구현자는 자기 태스크·스펙·계획 1의 Interfaces만 보고 작업하고, 완료 보고에 테스트 출력을 첨부한다.

## Global Constraints

- **배포 순서 고정**: Task 1(API/DB 관용화)이 머지되기 전에 Task 2(AI 새 계약)를 배포하지 않는다. 이중 출력 기간에 `risk_score`는 **`risk.py score_mapping(vdi)` 점수 단위**(10% → 70)로 채운다. `round(vdi)`를 `risk_score`에 넣지 않는다.
- 새 tier 이름 `low / elevated / high / insufficient`. 매핑: `overall_health` low→healthy, elevated→warning, high→critical, insufficient→null; recommendation `severity` low→info, elevated→warn, high→danger, **insufficient→info**. `tier_legacy` low→safe, elevated→watch, high→danger, insufficient→unknown.
- tier는 **`vdi_display`(AI가 `ROUND_HALF_UP` 1자리로 한 번 만든 문자열)에서만** 계산한다. 클라이언트는 재반올림·재계산 금지.
- `bee_total == 0` 또는 `quality.ok == false` → `tier = insufficient`, `vdi`는 계산 가능하면 채운다(0마리면 `vdi: null`).
- 해상도: 모바일 캡처 `ResolutionPreset.max`, HEIC→JPEG **무축소**, GPS strip 유지, 업로드 ≤10MB(초과 시만 긴 변 4000). API sharp는 **치수 유지, JPEG q95**. AI `MAX_EDGE=1024` 축소는 **two-stage 경로에서만 우회**(v0.1.0 YOLO·OpenAI 경로는 그대로).
- 타임아웃 체인: 모바일 `receiveTimeout` ≥ 95s(분석 POST) ≥ ai-client two-stage 90s ≥ AI 내부. Stage-2는 64개 청크, 소프트 크롭 상한 1,500(초과 시 랜덤 샘플 + `raw_payload.sampled: true`).
- `risk.py`·`risk.yaml`·`make_booth_cases.py`·부스 JSON은 **변경 금지**(동결). OpenAI 폴백은 `risk.py` shim으로 rate→`vdi_raw`(보정 없음, `corrected:false`, `bee_total/bee_infested/sampling_ci95 = null`).
- DB 마이그레이션은 `drizzle-kit generate` 산출물만 커밋, 머지된 마이그레이션 수정 금지. 컬럼 추가는 nullable, 구 컬럼 제거는 Task 8에서만.
- 응답 봉투 `{data, meta}`, 에러 RFC 7807, zod 검증, `@helpbee/database` 쿼리 함수만 사용(직접 SQL 금지), Bruno 요청 동시 갱신, 변경 라우트는 vitest.
- 모바일: 사용자 노출 문자열은 ARB(`app_ko.arb`) 경유, freezed/build_runner 미사용(수기 DTO), 토큰은 secure storage만.
- 삭제는 휴지통 이동만, 파괴적 git 명령 금지, `feature/*` → PR → develop.

## Review Focus

1. **AI가 새 계약을 보내는데 API가 구 버전인 상태(롤아웃 순서 어긋남)** — `risk_score`가 있어야 `success`로 저장돼야 하고, 없더라도 `engine_used`로만 실패 판정해야 한다. → Task 1 `test_success_when_risk_score_missing_but_engine_used`.
2. **`bee_total == 0` 응답** — API는 `vdi:null`·`overallHealth:null`·severity `info`로 저장하고 500이 나면 안 된다. → Task 1 `test_store_insufficient_tier_zero_bees`, Task 2 `test_engine_zero_bees_insufficient`.
3. **1,600마리 밀집 프레임** — 크롭 상한 1,500 초과 시 랜덤 샘플하고 `sampled:true`, 청크 64로 메모리 상한을 지켜야 한다. → Task 2 `test_crop_cap_and_chunking`.
4. **OpenAI 폴백 응답이 새 계약을 채우지 못하는 경우** — `bees:[]`, `bee_total:null`이어도 Pydantic 검증·API 저장이 통과해야 한다. → Task 2 `test_openai_shim_contract`.
5. **HEIC 갤러리 업로드** — 모바일이 JPEG로 변환하되 축소하지 않아야 하고 API allowlist(jpeg/png/webp)에 걸리지 않아야 한다. → Task 5 `test_heic_converted_without_downscale`.

---

### Task 1: API/DB 관용화 (§8-1) — 새 컬럼·새 tier 매핑·실패 판정·모델 row·트렌드 분리

**Files:**
- Modify: `packages/database/src/schema/analyses.ts` (컬럼 5개 추가)
- Create: `packages/database/migrations/NNNN_analyses_vdi_columns.sql` (`drizzle-kit generate` 산출물)
- Modify: `packages/database/src/seeds/dev.ts` (ai_models row 추가)
- Modify: `packages/database/src/queries/hives.ts:150` (`getHiveTrend` — `avgVdi` 시리즈 추가)
- Modify: `apps/api/src/services/ai-client.ts:67-81` (`AiAnalysisResult` 확장, two-stage 타임아웃 90s)
- Modify: `apps/api/src/routes/analyses.ts:80-86,141,149,180-182`
- Modify: `apps/api/bruno/analyses/*.bru`
- Test: `apps/api/src/tests/analyses.test.ts` (기존 파일에 케이스 추가)

**Interfaces:**
- Produces (DB): `analyses.vdi numeric(6,3) NULL`, `vdi_ci_low numeric(6,3) NULL`, `vdi_ci_high numeric(6,3) NULL`, `bee_total integer NULL`, `bee_infested integer NULL`. `ai_models` row `('yolo','helpbee-two-stage','0.2.0')`.
- Produces (API 타입):
```ts
export type Tier = 'safe' | 'watch' | 'danger' | 'low' | 'elevated' | 'high' | 'insufficient';
export type AiAnalysisResult = {
  risk_score: number | null; tier: Tier; tier_legacy?: 'safe'|'watch'|'danger'|'unknown';
  vdi?: number | null; vdi_display?: string | null; vdi_raw?: number | null; corrected?: boolean;
  sampling_ci95?: [number, number] | null; bee_total?: number | null; bee_infested?: number | null;
  bees?: { box: [number, number, number, number]; p_infested: number; infested: boolean }[];
  evidence?: { crop_url: string; p_infested: number }[]; quality?: { ok: boolean; blur_score: number; exposure_mean: number; px_per_mm_est: number | null };
  estimated_count?: number | null; confidence?: number; recommendations: string[]; model_version: string;
  model_versions?: { stage1: string; stage2: string; vdi_config: string }; prompt_version?: string | null; latency_ms?: number;
  cost_estimate_usd?: number | null; engine_used: string | null; fallback_reason?: string | null; raw_payload?: Record<string, unknown>;
};
```
- `getHiveTrend` 반환에 `avgVdi: number | null` 추가(두-stage row만 평균), `avgRisk`는 구 row만.

- [ ] **Step 1: 실패 테스트 작성** (`apps/api/src/tests/analyses.test.ts`에 추가 — 기존 헬퍼 `makeApp`/`fakeDeps` 패턴을 따른다)

```ts
it('stores success when risk_score is missing but engine_used is set (new contract)', async () => {
  const deps = fakeDeps({ analyze: async () => ({
    engine_used: 'yolo', tier: 'elevated', vdi: 4.2, vdi_display: '4.2', bee_total: 310, bee_infested: 14,
    sampling_ci95: [2.4, 6.9], recommendations: ['가루설탕법으로 확인하세요'], model_version: 'two-stage-v0.2.0',
    risk_score: null,
  }) });
  const res = await makeApp(deps).request('/v1/analyses', post({ hiveId: HIVE, imageId: IMAGE }));
  expect(res.status).toBe(201);
  const stored = deps.stored[0].analysis;
  expect(stored.status).toBe('success');
  expect(stored.overallHealth).toBe('warning');
  expect(stored.vdi).toBe(4.2); expect(stored.beeTotal).toBe(310); expect(stored.beeInfested).toBe(14);
  expect(deps.stored[0].recommendations[0].severity).toBe('warn');
});

it('stores insufficient tier with zero bees without error', async () => {
  const deps = fakeDeps({ analyze: async () => ({
    engine_used: 'yolo', tier: 'insufficient', vdi: null, vdi_display: null, bee_total: 0, bee_infested: 0,
    recommendations: ['벌이 보이도록 다시 촬영해 주세요'], model_version: 'two-stage-v0.2.0', risk_score: null,
  }) });
  const res = await makeApp(deps).request('/v1/analyses', post({ hiveId: HIVE, imageId: IMAGE }));
  expect(res.status).toBe(201);
  const stored = deps.stored[0].analysis;
  expect(stored.status).toBe('success'); expect(stored.overallHealth).toBeNull(); expect(stored.vdi).toBeNull();
  expect(deps.stored[0].recommendations[0].severity).toBe('info');
});

it('still accepts the legacy contract (risk_score + safe/watch/danger)', async () => {
  const deps = fakeDeps({ analyze: async () => ({ engine_used: 'yolo', tier: 'watch', risk_score: 55, recommendations: [], model_version: 'v0.1.0' }) });
  const res = await makeApp(deps).request('/v1/analyses', post({ hiveId: HIVE, imageId: IMAGE }));
  expect(res.status).toBe(201);
  expect(deps.stored[0].analysis.overallHealth).toBe('warning');
  expect(deps.stored[0].analysis.varroaInfectionRisk).toBe(55);
});
```

- [ ] **Step 2: 실패 확인** — `pnpm --filter api test -- analyses` → 3 FAIL (`failed` 판정·tier 매핑·컬럼 없음)

- [ ] **Step 3: DB 스키마·시드·마이그레이션**

```ts
// packages/database/src/schema/analyses.ts — 컬럼 추가 (기존 컬럼 뒤)
vdi: numeric('vdi', { precision: 6, scale: 3 }),
vdiCiLow: numeric('vdi_ci_low', { precision: 6, scale: 3 }),
vdiCiHigh: numeric('vdi_ci_high', { precision: 6, scale: 3 }),
beeTotal: integer('bee_total'),
beeInfested: integer('bee_infested'),
```
`numeric` import 추가. `pnpm --filter @helpbee/database drizzle-kit generate` → SQL 커밋. `seeds/dev.ts`의 ai_models 배열에 `{ provider: 'yolo', name: 'helpbee-two-stage', version: '0.2.0', isActive: true }` 추가(기존 `helpbee-yolov11s` row 유지). 시드 재실행 idempotent 확인.

- [ ] **Step 4: API 라우트 수정**

```ts
// apps/api/src/routes/analyses.ts
type Tier = 'safe'|'watch'|'danger'|'low'|'elevated'|'high'|'insufficient';
const HEALTH: Record<Tier, string | null> = { safe: 'healthy', watch: 'warning', danger: 'critical', low: 'healthy', elevated: 'warning', high: 'critical', insufficient: null };
const SEVERITY: Record<Tier, string> = { safe: 'info', watch: 'warn', danger: 'danger', low: 'info', elevated: 'warn', high: 'danger', insufficient: 'info' };
// ...
const failed = !result || result.engine_used === null;              // risk_score 조건 제거
// ⑤-b 성공 저장 객체
const analysis = {
  status: 'success',
  varroaInfectionRisk: result!.risk_score ?? null,                   // 이중 출력 기간: AI가 score_mapping으로 채움
  estimatedVarroaCount: result!.estimated_count ?? null,
  overallHealth: HEALTH[tier] ?? null,
  vdi: result!.vdi ?? null,
  vdiCiLow: result!.sampling_ci95?.[0] ?? null,
  vdiCiHigh: result!.sampling_ci95?.[1] ?? null,
  beeTotal: result!.bee_total ?? null,
  beeInfested: result!.bee_infested ?? null,
  rawResponse: result!.raw_payload ?? null,
  latencyMs: result!.latency_ms ?? null,
  error: null,
  analyzedAt,
};
```
`resolveModelId(provider)`는 `model_versions`가 있으면 `('yolo','helpbee-two-stage')` row를, 없으면 기존 row를 고르도록 `deps.resolveModelId(provider, result.model_versions ? 'two-stage' : 'v1')`로 확장. `ai-client.ts`의 `timeout`을 `engine`별로: two-stage 응답을 받는 경로는 `timeoutMs: 90_000`(설정 `AI_TIMEOUT_MS_TWO_STAGE`). `getHiveTrend`에 `avgVdi: avg(analyses.vdi).mapWith(Number)` 추가(같은 쿼리, 두 컬럼 모두 반환; 프론트가 구분).

- [ ] **Step 5: 통과 확인** — `pnpm --filter api test` 전체 PASS, `pnpm --filter api type-check` PASS, `pnpm --filter @helpbee/database drizzle-kit check` clean. Bruno `analyses/create.bru` 응답 예시에 새 필드 추가.

- [ ] **Step 6: 커밋** — `git add packages/database apps/api && git commit -m "feat(api,db): analyses vdi/bee 컬럼·새 tier 매핑·engine_used 기반 실패 판정·two-stage 모델 row (관용화, 계약 양립)"`

---

### Task 2: AI 서빙 — `two_stage_engine.py` · `AnalysisResponse` 확장 · 이중 출력 · OpenAI shim · 품질 체크

**Files:**
- Create: `apps/ai/app/services/two_stage_engine.py`
- Create: `apps/ai/app/services/quality.py`
- Modify: `apps/ai/app/schemas/analysis.py`
- Modify: `apps/ai/app/services/orchestrator.py` (`run_analysis` 분기, `_needs_fallback`, OpenAI shim)
- Modify: `apps/ai/app/services/preprocess.py` (`preprocess_image(jpeg, max_edge=None)` — `None`이면 축소 안 함)
- Modify: `apps/ai/app/core/config.py` (`AI_ENGINE=two-stage|yolo-v1`, `TWO_STAGE_MODEL_VERSION`, `AI_INTERNAL_BUDGET_S=80`)
- Modify: `apps/ai/app/deps.py` (엔진 주입)
- Test: `apps/ai/app/tests/unit/test_two_stage_engine.py`, `test_orchestrator_two_stage.py`, `test_quality.py`, `test_schemas.py`(확장)

**Interfaces:**
- Consumes (계획 1): `app/services/vdi.py`(`VdiConfig`, `load_vdi_config`, `aggregate`, `display`, `tier_from_display`), `s3://helpbee-models/two-stage/<ver>/{stage1.onnx,stage2.onnx,vdi.yaml,metadata.json}`, Stage-2 ONNX 출력 `["logit","featmap"]`, `risk.py score_mapping` = `score_from_rate`.
- Produces:
```python
@dataclass
class BeeDet: box: tuple[float,float,float,float]; p_infested: float; infested: bool
@dataclass
class TwoStageResult: bees: list[BeeDet]; bee_total: int; bee_infested: int; sampled: bool; evidence: list[dict]; model_versions: dict; stage_latency_ms: dict
class TwoStageEngine(Protocol):
    def analyze(self, image: np.ndarray, cfg: VdiConfig) -> TwoStageResult: ...
class OnnxTwoStageEngine:  # stage1(1024, tiles if long side ≥ 3500px) → crops → stage2 chunks(64) → CAM top-k
def detect_bees(sess1, img: np.ndarray, imgsz=1024, conf=0.15, max_det=1500, tile: bool=False) -> list[box]
def classify_crops(sess2, crops: np.ndarray[N,3,224,224], chunk=64) -> tuple[np.ndarray logits, np.ndarray featmaps]
def cam_from_featmap(featmap: np.ndarray[1024,7,7], fc_w: np.ndarray[1024]) -> np.ndarray[7,7]
def cap_crops(boxes: list, cap=1500, rng) -> tuple[list, bool]
# quality.py
def assess_quality(img: np.ndarray, boxes: list[box] | None, floor_px_per_mm: float | None) -> dict  # {ok, blur_score, exposure_mean, px_per_mm_est, reasons}
```
- `AnalysisResponse` 새 필드(모두 optional, 기본 None/[]): `tier: Literal["safe","watch","danger","low","elevated","high","insufficient"]`, `tier_legacy`, `vdi`, `vdi_display`, `vdi_raw`, `corrected`, `sampling_ci95`, `bee_total`, `bee_infested`, `bees`, `evidence`, `quality`, `model_versions`.

- [ ] **Step 1: 실패 테스트 작성**

```python
# apps/ai/app/tests/unit/test_two_stage_engine.py
import numpy as np
from app.services.two_stage_engine import cap_crops, cam_from_featmap, chunk_indices, letterbox_tiles

def test_crop_cap_and_chunking():
    boxes = [(i, i, i + 10, i + 10) for i in range(1600)]
    kept, sampled = cap_crops(boxes, cap=1500, rng=np.random.default_rng(0))
    assert len(kept) == 1500 and sampled is True
    assert [len(c) for c in chunk_indices(1500, 64)][-1] == 1500 % 64 and sum(len(c) for c in chunk_indices(1500, 64)) == 1500

def test_cam_shape_and_normalized():
    cam = cam_from_featmap(np.random.rand(1024, 7, 7).astype(np.float32), np.random.rand(1024).astype(np.float32))
    assert cam.shape == (7, 7) and cam.min() >= 0.0 and cam.max() <= 1.0

def test_tiles_cover_image_with_overlap():
    tiles = letterbox_tiles((3000, 4000), n=2, overlap=0.1)   # (h, w)
    assert len(tiles) == 4 and tiles[0] == (0, 0, 2200, 1650)   # (x, y, w, h), 10% overlap

# apps/ai/app/tests/unit/test_orchestrator_two_stage.py
from app.services.orchestrator import run_analysis
from app.services.vdi import VdiConfig
class FakeTwoStage:
    def __init__(self, bees): self.bees = bees
    model_versions = {"stage1": "s1-test", "stage2": "s2-test", "vdi_config": "v-test"}
    def analyze(self, image, cfg):
        from app.services.two_stage_engine import TwoStageResult, BeeDet
        b = [BeeDet(box=(0, 0, 10, 10), p_infested=p, infested=p > cfg.tau) for p in self.bees]
        return TwoStageResult(bees=b, bee_total=len(b), bee_infested=sum(x.infested for x in b), sampled=False, evidence=[], model_versions=self.model_versions, stage_latency_ms={})
CFG = VdiConfig(tau=0.6, tpr=0.9, fpr=0.01, corrected=True)

def test_engine_zero_bees_insufficient(jpeg_bytes):
    r = run_analysis(jpeg_bytes, engine="yolo", two_stage=FakeTwoStage([]), vdi_cfg=CFG)
    assert r.tier == "insufficient" and r.vdi is None and r.bee_total == 0 and r.engine_used == "yolo"

def test_engine_dual_output_risk_score_is_score_mapping(jpeg_bytes):
    r = run_analysis(jpeg_bytes, engine="yolo", two_stage=FakeTwoStage([0.9] * 12 + [0.1] * 88), vdi_cfg=CFG)  # raw 12% → corrected ≈ 12.4
    assert r.tier == "high" and r.tier_legacy == "danger"
    from app.services.risk import score_from_rate
    assert r.risk_score == score_from_rate(r.vdi)          # 점수 단위 (≈ 77), round(vdi) 아님
    assert r.vdi_display == "12.4" and r.bee_total == 100 and r.bee_infested == 12

def test_openai_shim_contract(jpeg_bytes, fake_openai_rate_7):
    r = run_analysis(jpeg_bytes, engine="auto", two_stage=FakeTwoStage([]), openai=fake_openai_rate_7, vdi_cfg=CFG)
    assert r.engine_used == "openai" and r.fallback_reason == "insufficient"
    assert r.vdi_raw == 7.0 and r.corrected is False and r.bee_total is None and r.bees == [] and r.tier == "elevated"

# apps/ai/app/tests/unit/test_quality.py
import numpy as np
from app.services.quality import assess_quality
def test_blur_and_exposure_fail():
    flat = np.full((1080, 1920, 3), 20, np.uint8)     # 어둡고 평탄 → 블러·노출 실패
    q = assess_quality(flat, boxes=None, floor_px_per_mm=None)
    assert q["ok"] is False and {"blur", "exposure"} <= set(q["reasons"])
def test_px_per_mm_estimate_from_boxes_is_warning_only():
    img = np.random.randint(0, 255, (1080, 1920, 3), np.uint8)
    q = assess_quality(img, boxes=[(0, 0, 60, 60)] * 20, floor_px_per_mm=12.0)   # 벌 폭 60px/12mm = 5 px/mm < 12
    assert q["px_per_mm_est"] == 5.0 and "resolution" in q["warnings"] and q["ok"] is True
```
`jpeg_bytes`·`fake_openai_rate_7` fixture는 기존 `test_orchestrator.py`의 패턴(작은 JPEG 생성, `OpenAIVisionClient` 스텁 `analyze()`가 `infestation_rate=7.0, confidence=0.9`)을 conftest로 옮겨 공유.

- [ ] **Step 2: 실패 확인** — `pytest -q app/tests/unit/test_two_stage_engine.py app/tests/unit/test_orchestrator_two_stage.py app/tests/unit/test_quality.py` → FAIL

- [ ] **Step 3: 구현**

```python
# apps/ai/app/services/two_stage_engine.py (핵심)
from __future__ import annotations
from dataclasses import dataclass, field
from pathlib import Path
import numpy as np

@dataclass
class BeeDet: box: tuple[float, float, float, float]; p_infested: float; infested: bool
@dataclass
class TwoStageResult:
    bees: list[BeeDet]; bee_total: int; bee_infested: int; sampled: bool
    evidence: list[dict] = field(default_factory=list); model_versions: dict = field(default_factory=dict); stage_latency_ms: dict = field(default_factory=dict)

def chunk_indices(n: int, chunk: int) -> list[range]:
    return [range(i, min(i + chunk, n)) for i in range(0, n, chunk)]

def cap_crops(boxes: list, cap: int = 1500, rng=None) -> tuple[list, bool]:
    if len(boxes) <= cap: return boxes, False
    rng = rng or np.random.default_rng(0); idx = np.sort(rng.choice(len(boxes), cap, replace=False))
    return [boxes[i] for i in idx], True

def letterbox_tiles(hw: tuple[int, int], n: int = 2, overlap: float = 0.1) -> list[tuple[int, int, int, int]]:
    h, w = hw; tw, th = int(w / n * (1 + overlap)), int(h / n * (1 + overlap)); out = []
    for j in range(n):
        for i in range(n):
            x, y = int(i * w / n * (1 - overlap * 0)), int(j * h / n)
            x = min(x, w - tw); y = min(y, h - th); out.append((max(0, x), max(0, y), tw, th))
    return out

def cam_from_featmap(featmap: np.ndarray, fc_w: np.ndarray) -> np.ndarray:
    cam = np.tensordot(fc_w, featmap, axes=(0, 0)); cam = np.maximum(cam, 0)
    return (cam - cam.min()) / (cam.max() - cam.min() + 1e-6)

def iomin_nms(boxes: np.ndarray, scores: np.ndarray, thr: float = 0.7) -> list[int]:
    """타일 경계에서 잘린 박스 병합용: intersection / min(area)."""
    order = scores.argsort()[::-1]; keep = []
    areas = (boxes[:, 2] - boxes[:, 0]) * (boxes[:, 3] - boxes[:, 1])
    while len(order):
        i = order[0]; keep.append(int(i)); rest = order[1:]
        xx1 = np.maximum(boxes[i, 0], boxes[rest, 0]); yy1 = np.maximum(boxes[i, 1], boxes[rest, 1])
        xx2 = np.minimum(boxes[i, 2], boxes[rest, 2]); yy2 = np.minimum(boxes[i, 3], boxes[rest, 3])
        inter = np.maximum(0, xx2 - xx1) * np.maximum(0, yy2 - yy1); iomin = inter / np.minimum(areas[i], areas[rest])
        order = rest[iomin < thr]
    return keep

class OnnxTwoStageEngine:
    def __init__(self, version: str, cache_dir: str, s3_bucket: str | None, vdi_cfg, imgsz=1024, conf=0.15, max_det=1500, chunk=64, crop_cap=1500, topk=6):
        self.version, self.cache_dir, self.bucket = version, Path(cache_dir), s3_bucket
        self.vdi_cfg, self.imgsz, self.conf, self.max_det, self.chunk, self.crop_cap, self.topk = vdi_cfg, imgsz, conf, max_det, chunk, crop_cap, topk
        self._s1 = self._s2 = None; self._fc_w = None
        self.model_versions = {"stage1": f"{version}/stage1", "stage2": f"{version}/stage2", "vdi_config": version}
    def _ensure(self):  # S3 lazy-load: two-stage/<ver>/{stage1.onnx,stage2.onnx,vdi.yaml,metadata.json} — 기존 OnnxYoloEngine._ensure_model 패턴 재사용
        ...
    def analyze(self, image: np.ndarray, cfg) -> TwoStageResult:
        import time, cv2; self._ensure(); t = {}
        t0 = time.monotonic(); tile = max(image.shape[:2]) >= 3500
        boxes = self._detect(image, tile=tile); t["stage1"] = int((time.monotonic() - t0) * 1000)
        boxes, sampled = cap_crops(boxes, self.crop_cap)
        if not boxes: return TwoStageResult([], 0, 0, sampled, model_versions=self.model_versions, stage_latency_ms=t)
        from training.data.make_crops import crop_pad_224   # 계획 1 Task 8 — 학습과 동일 크롭 규칙
        crops = np.stack([crop_pad_224(image, b)[0] for b in boxes]).transpose(0, 3, 1, 2).astype(np.float32) / 255.0
        crops = (crops - np.array([0.485, 0.456, 0.406])[None, :, None, None]) / np.array([0.229, 0.224, 0.225])[None, :, None, None]
        t1 = time.monotonic(); logits, feats = [], []
        for idx in chunk_indices(len(crops), self.chunk):
            lo, fm = self._s2.run(["logit", "featmap"], {"image": crops[idx].astype(np.float32)}); logits.append(lo); feats.append(fm)
        logits = np.concatenate(logits); feats = np.concatenate(feats); t["stage2"] = int((time.monotonic() - t1) * 1000)
        a, b = cfg.platt if hasattr(cfg, "platt") else (1.0, 0.0)
        p = 1 / (1 + np.exp(-(a * logits + b)))
        bees = [BeeDet(tuple(map(float, bx)), float(pi), bool(pi > cfg.tau)) for bx, pi in zip(boxes, p)]
        top = np.argsort(-p)[: self.topk]
        evidence = [{"index": int(i), "p_infested": float(p[i]), "cam": cam_from_featmap(feats[i], self._fc_w).tolist()} for i in top if p[i] > cfg.tau]
        return TwoStageResult(bees, len(bees), int(sum(x.infested for x in bees)), sampled, evidence, self.model_versions, t)
```
`_detect`: `letterbox`(기존 yolo_engine 재사용)로 1024 추론 → `decode_detections` → 타일이면 각 타일 좌표를 원본으로 되돌린 뒤 `iomin_nms(0.7)` → 원본 좌표 박스. `_ensure`는 `OnnxYoloEngine._ensure_model`을 일반화해 4개 파일을 받고, `metadata.json`의 `fc_weight` 또는 stage2.onnx의 initializer에서 `fc_w`를 읽는다(계획 1 Task 9 export 시 `metadata.json`에 `fc_weight: list[float]`와 `platt: {a,b}`를 함께 기록하도록 계획 1 구현자에게 전달 — 이미 `vdi.yaml`에 `platt`가 있으므로 `VdiConfig`에 `platt: tuple[float,float]` 필드 추가).

`quality.py`:
```python
def assess_quality(img, boxes, floor_px_per_mm, blur_min=100.0, exposure=(40, 215)):
    import cv2
    small = cv2.resize(img, (1024, int(1024 * img.shape[0] / img.shape[1]))) if img.shape[1] > 1024 else img
    gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY); blur = float(cv2.Laplacian(gray, cv2.CV_64F).var()); mean = float(gray.mean())
    reasons, warnings = [], []
    if blur < blur_min: reasons.append("blur")
    if not (exposure[0] <= mean <= exposure[1]): reasons.append("exposure")
    px = None
    if boxes:
        med_w = float(np.median([b[2] - b[0] for b in boxes])); px = round(med_w / 12.0, 2)   # 벌 폭 ≈ 12mm
        if floor_px_per_mm and px < floor_px_per_mm: warnings.append("resolution")
    return {"ok": not reasons, "blur_score": blur, "exposure_mean": mean, "px_per_mm_est": px, "reasons": reasons, "warnings": warnings}
```
`orchestrator.run_analysis(jpeg, *, engine, yolo=None, two_stage=None, openai=None, vdi_cfg=None, ...)`: `two_stage`가 주어지면 `preprocess_image(jpeg, max_edge=None)`(축소 없음) → `assess_quality` → `two_stage.analyze` → `vdi.aggregate([(k, n)], cfg, quality_ok)` → `AnalysisResponse(tier=agg["tier"], tier_legacy=LEGACY[tier], vdi=agg["vdi"] if n else None, vdi_display=..., vdi_raw=agg["raw"], corrected=cfg.corrected, sampling_ci95=..., bee_total=n, bee_infested=k, bees=[...], evidence=[...], quality=q, risk_score=score_from_rate(agg["vdi"]) if n else None, recommendations=recs_for_tier(tier), model_version=f"two-stage-{ver}", model_versions=..., raw_payload={"sampled": sampled, "stage_latency_ms": ...})`. `_needs_fallback` = `tier == "insufficient" or n < 30` → 사유 `"insufficient"|"low_count"`; OpenAI shim은 기존 `_openai_response`를 유지하되 새 필드를 `vdi_raw=rate, vdi=rate, vdi_display=display(rate), corrected=False, bee_total=None, bee_infested=None, sampling_ci95=None, bees=[], tier=tier_from_display(display(rate), cfg, bee_total=1, quality_ok=True)`로 채운다. `recs_for_tier`는 `vdi.yaml`의 `recommendations` 섹션(low/elevated/high/insufficient + `next_check_windows`)에서 읽는다 — 계획 1 Task 9의 `vdi.yaml`에 이 섹션을 추가(문구는 스펙 §3).

- [ ] **Step 4: 통과 확인** — 위 3 파일 + 기존 `test_orchestrator.py`·`test_schemas.py`·`test_risk.py`(shim 동결 확인) PASS. `pytest -q` 전체 PASS.

- [ ] **Step 5: 실제 ONNX로 로컬 E2E** — `AI_ENGINE=two-stage TWO_STAGE_MODEL_VERSION=v0.2.0` 로 uvicorn 기동, Sample 이미지 1장 `POST /analyze` → 응답에 `vdi_display`·`bees`·`evidence`·`risk_score`(점수) 확인, `latency_ms` 기록.

- [ ] **Step 6: 커밋** — `git add apps/ai && git commit -m "feat(ai): two-stage 엔진(타일·청크·CAM) + AnalysisResponse vdi 계약 이중 출력 + 품질 체크 + OpenAI shim"`

---

### Task 3: N장 합산 — AI `POST /aggregate` + API `GET /v1/analyses/aggregate`

**Files:**
- Create: `apps/ai/app/routers/aggregate.py`
- Modify: `apps/ai/app/main.py` (라우터 등록)
- Modify: `apps/api/src/services/ai-client.ts` (`aggregate(counts)`)
- Modify: `apps/api/src/routes/analyses.ts` (`GET /aggregate`), `apps/api/src/schemas/analyses.ts` (`aggregateQuerySchema`)
- Modify: `packages/database/src/queries/analyses.ts` (`getCountsByIdsForUser`)
- Modify: `apps/api/bruno/analyses/aggregate.bru`
- Test: `apps/ai/app/tests/unit/test_aggregate_router.py`, `apps/api/src/tests/analyses.test.ts`

**Interfaces:**
- AI: `POST /aggregate` body `{counts: [{bee_infested:int, bee_total:int}], quality_ok: bool=true}` (내부 HMAC bearer, 기존 `/analyze`와 동일) → `{vdi, vdi_display, vdi_raw, sampling_ci95, bee_total, bee_infested, tier, corrected}`.
- API: `GET /v1/analyses/aggregate?ids=<uuid>,<uuid>...`(최대 10, 모두 내 소유·`status=success`·two-stage row) → 봉투 `{data: {...AI 응답, analysisIds}}`. 구 row(`beeTotal null`)가 섞이면 `400 VALIDATION_ERROR`.

- [ ] **Step 1: 테스트**

```python
# apps/ai/app/tests/unit/test_aggregate_router.py
def test_aggregate_sums_counts(client_with_internal_token):
    r = client_with_internal_token.post("/aggregate", json={"counts": [{"bee_infested": 1, "bee_total": 40}, {"bee_infested": 9, "bee_total": 900}]})
    assert r.status_code == 200 and r.json()["bee_total"] == 940 and r.json()["tier"] == "low"
def test_aggregate_rejects_empty(client_with_internal_token):
    assert client_with_internal_token.post("/aggregate", json={"counts": []}).status_code == 422
```
```ts
it('aggregate returns pooled vdi for owned two-stage rows', async () => {
  const deps = fakeDeps({ countsByIds: async () => [{ beeInfested: 1, beeTotal: 40 }, { beeInfested: 9, beeTotal: 900 }],
                          aggregate: async () => ({ vdi: 0.06, vdi_display: '0.1', tier: 'low', bee_total: 940, bee_infested: 10, sampling_ci95: [0.5, 1.9] }) });
  const res = await makeApp(deps).request(`/v1/analyses/aggregate?ids=${A},${B}`, get());
  expect(res.status).toBe(200); expect((await res.json()).data.bee_total).toBe(940);
});
it('aggregate rejects legacy rows without bee counts', async () => {
  const deps = fakeDeps({ countsByIds: async () => [{ beeInfested: null, beeTotal: null }] });
  expect((await makeApp(deps).request(`/v1/analyses/aggregate?ids=${A}`, get())).status).toBe(400);
});
```

- [ ] **Step 2: 실패 확인 → Step 3: 구현** — AI 라우터는 `vdi.aggregate`를 그대로 호출(`counts` 길이 1~50, Pydantic). API는 `ids` zod(`z.string().transform(s => s.split(',')).pipe(z.array(uuid).min(1).max(10))`), `deps.countsByIds(ids, userId)`(소유·success 필터, `beeTotal`/`beeInfested` 반환), null 포함 시 `problem(c, 'VALIDATION_ERROR')`, `deps.aggregate(counts)` 호출 후 `ok(c, {...})`. `ai-client.aggregate`는 `/aggregate`에 HMAC bearer로 POST, 재시도 없음.
- [ ] **Step 4: PASS → Step 5: Bruno 추가 → Step 6: 커밋** `feat(ai,api): N장 합산 — AI /aggregate + API GET /v1/analyses/aggregate`

---

### Task 4: API 이미지 패스스루 (sharp q95·치수 유지) + portfolio 모드

**Files:**
- Modify: `apps/api/src/services/s3-client.ts:75` (`jpeg({ quality: 95 })`, 리사이즈 없음 확인, `limitInputPixels` 50MP)
- Modify: `apps/api/src/config/env.ts` (`PORTFOLIO_MODE: boolean`, `AI_TIMEOUT_MS_TWO_STAGE`)
- Modify: `apps/api/src/routes/analyses.ts` (`PORTFOLIO_MODE`면 quota reserve/refund·이메일 검증 게이트 우회, engine은 항상 `auto`가 아닌 `yolo`), `apps/api/src/routes/subscriptions.ts` (`plans`에 `portfolio: true` 플래그)
- Modify: `.env.example`, `apps/api/CLAUDE.md` 환경 섹션
- Test: `apps/api/src/tests/images.test.ts`(q95·치수), `analyses.test.ts`(portfolio 모드)

- [ ] **Step 1: 테스트** — `confirm` 경로에서 4000×3000 JPEG 업로드 → 재인코딩 결과의 `width/height` 동일, JPEG 품질 마커(`sharp(...).metadata()` 대신 파일 크기 비교: q95 결과가 q85보다 큼) 검증; `PORTFOLIO_MODE=true`에서 `reserveQuota`가 호출되지 않고 `emailVerifiedAt=null`이어도 201.
- [ ] **Step 2~4: 구현·통과** — `.jpeg({ quality: 95, mozjpeg: true })`; env zod `PORTFOLIO_MODE: z.coerce.boolean().default(false)`; 라우트 분기.
- [ ] **Step 5: 커밋** `feat(api): 이미지 패스스루 q95 + PORTFOLIO_MODE(유료 플랜·쿼터·이메일 게이트 비활성)`

---

### Task 5: 모바일 — 캡처 max · 원본 업로드 · HEIC 무축소 · 타임아웃 · DTO · 결과 화면(`elevated`/`insufficient`/증거 갤러리)

**Files:**
- Modify: `apps/mobile/lib/features/analyses/presentation/capture_screen.dart:83` (`ResolutionPreset.max`)
- Modify: `apps/mobile/lib/features/analyses/data/capture_preprocess.dart` (축소 제거, HEIC→JPEG q95 무축소, GPS strip 유지, >10MB면 긴 변 4000)
- Modify: `apps/mobile/lib/core/api/dio_client.dart:25` (`receiveTimeout` 95s — 분석 POST 전용 `Options`)
- Modify: `apps/mobile/lib/features/analyses/data/analysis_dto.dart` (새 필드 + `tier` 서버 우선), `apps/mobile/lib/core/risk/risk_tier.dart` (`RiskTier.insufficient` 추가, `riskTierFromServer(String?)`)
- Modify: `apps/mobile/lib/features/analyses/presentation/result_screen.dart` (VDI·CI·벌 수·증거 갤러리·고정 문구), `apps/mobile/lib/l10n/app_ko.arb` (문구 6개)
- Test: `apps/mobile/test/analyses/capture_preprocess_test.dart`, `analysis_dto_test.dart`, `result_screen_test.dart`

**Interfaces:**
- DTO: `Analysis`에 `double? vdi; String? vdiDisplay; double? vdiCiLow; double? vdiCiHigh; int? beeTotal; int? beeInfested; String? tierRaw`(서버 `tier`; 목록 응답엔 컬럼이 없으므로 `overallHealth`로 폴백). `RiskTier get tier` 우선순위: `tierRaw`(low/elevated/high/insufficient) → `overallHealth` → `riskTierFromScore`.
- `capturePreprocess(File) -> Future<File>`: 출력 JPEG, EXIF GPS 제거, 축소 없음(단 바이트 > 10MB이면 긴 변 4000).

- [ ] **Step 1: 테스트**

```dart
// test/analyses/capture_preprocess_test.dart
test('HEIC is converted to JPEG without downscale', () async {
  final out = await capturePreprocess(fixtureHeic4032x3024());
  final decoded = img.decodeImage(await out.readAsBytes())!;
  expect(decoded.width, 4032); expect(decoded.height, 3024);
});
test('over 10MB falls back to long side 4000', () async {
  final out = await capturePreprocess(fixtureJpeg8000x6000q100());
  final decoded = img.decodeImage(await out.readAsBytes())!;
  expect(math.max(decoded.width, decoded.height), 4000);
});
// test/analyses/analysis_dto_test.dart
test('server tier wins over overallHealth and score', () {
  final a = Analysis.fromJson({...base, 'tier': 'insufficient', 'overallHealth': 'healthy', 'varroaInfectionRisk': 80});
  expect(a.tier, RiskTier.insufficient);
});
test('legacy rows still derive tier from overallHealth', () {
  final a = Analysis.fromJson({...base, 'overallHealth': 'critical'});
  expect(a.tier, RiskTier.danger);
});
```

- [ ] **Step 2: 실패 확인 → Step 3: 구현** — `capture_preprocess.dart`: `FlutterImageCompress.compressWithFile(path, minWidth: 8000, minHeight: 8000, quality: 95, keepExif: false, format: CompressFormat.jpeg)`(min 값을 원본 이상으로 두면 축소 없음), 결과 > 10MB이면 `minWidth/minHeight: 4000`으로 재실행. `dio_client.dart`: `Options(receiveTimeout: const Duration(seconds: 95))`를 분석 POST 호출에만 전달. `risk_tier.dart`: `enum RiskTier { safe, watch, danger, insufficient, unknown }`, 색 토큰 `tierInsufficient`(회색), 배지 문구 `badgeInsufficient`("판독 불가 — 다시 촬영"); `riskTierFromServer`: `low→safe, elevated→watch, high→danger, insufficient→insufficient`. 결과 화면: 헤더에 `vdiDisplay% (표본 신뢰구간 lo~hi, 벌 N마리)`, `beeTotal < 30`이면 "표본 적음" 배지, 고정 문구 `resultDisclaimer`("보정 전 시험 지표 — 사진은 봉개 유충방 속 응애를 볼 수 없습니다"), `evidence[]`가 있으면 가로 스크롤 갤러리(크롭 이미지는 `raw_payload.evidence[i].crop_url` — Task 2에서 S3 presigned 또는 base64 썸네일로 제공; MVP는 base64 ≤ 40KB × 6).
- [ ] **Step 4: `dart format` · `dart analyze` 0 issues · `flutter test` PASS → Step 5: 커밋** `feat(mobile): 최대 해상도 캡처·원본 업로드·HEIC 무축소·95s 타임아웃·vdi DTO·insufficient tier·증거 갤러리`

---

### Task 6: 어드민 진단 상세 — vdi·벌 수·CI 표시 + 부스 동결 확인

**Files:**
- Modify: `apps/admin/src/lib/types.ts:65` (`vdi`, `vdiCiLow`, `vdiCiHigh`, `beeTotal`, `beeInfested` 추가)
- Modify: `apps/admin/src/app/(dashboard)/analyses/[imageId]/page.tsx:82-84` (VDI 필드 3개 추가, `HEALTH_LABEL`에 null → "판독 불가")
- Test: `apps/admin/tests/analyses-detail.spec.ts`(Playwright — 상세 페이지에 "VDI" 라벨 렌더), `apps/ai/app/tests/unit/test_make_booth_cases.py`(기존 — 동결 확인만 실행)

- [ ] **Step 1~4**: 타입·페이지 수정, `pnpm --filter admin typecheck && build` PASS, `pytest app/tests/unit/test_make_booth_cases.py` PASS(부스 경로가 `risk.py`를 그대로 쓰는지 확인 — 변경 없음).
- [ ] **Step 5: 커밋** `feat(admin): 진단 상세 vdi/CI/벌 수 표시`

---

### Task 7: 회귀 fixture v2 (two-stage 서빙 경로 스냅샷)

**Files:**
- Modify: `apps/ai/training/data/make_regression_fixtures.py` (엔진을 `two-stage`로, 케이스 선정 규칙 교체)
- Modify: `apps/ai/app/tests/regression/test_regression.py` (기대값 `vdi_display`·`tier`, 허용 오차 `|Δvdi| ≤ 1.0`, tier 변동 0)
- Create(커밋): `apps/ai/app/tests/fixtures/regression_manifest.json` v2
- Test: 위 회귀 테스트 자체

**Interfaces:**
- manifest v2 항목: `{path, sha256, expected_vdi_display, expected_tier, expected_bee_total, case: "boundary|low_count|healthy|dense|zero_bees|blur|varroa_visible_no"}`; 메타 `model_versions`, `vdi_config_sha`.

- [ ] **Step 1: 케이스 선정 규칙 테스트** — `select_cases(df) `가 각 `case` 라벨을 최소 3개씩 뽑는지(합성 DataFrame으로).
- [ ] **Step 2~4: 구현** — 71667 Sample + EV2(`varroa_visible=false` 프레임) + 합성(0마리: 벌 없는 소비판 셀 이미지, 블러: Sample에 GaussianBlur 적용본을 `training/datasets/Sample_derived/`에 생성, gitignore)에서 24~30장; 회귀 테스트는 ONNX 두 개 + Sample 있을 때만 실행, 없으면 skip(기존 규칙).
- [ ] **Step 5: 커밋** `test(ai): 회귀 fixture v2 — two-stage 서빙 경로, 경계·저벌수·0마리·블러·숨은응애 케이스`

---

### Task 8: 구 필드 제거 (§8-4) — 소비자 이전 완료 후

**Files:**
- Modify: `apps/ai/app/schemas/analysis.py` (`risk_score`·`estimated_count`·`tier_legacy` 제거, `tier` Literal을 새 4개로), `orchestrator.py` (이중 출력 제거)
- Modify: `apps/api/src/routes/analyses.ts` (`varroaInfectionRisk`·`overallHealth` 쓰기 제거 — 컬럼은 다음 마이그레이션까지 유지), `apps/api/src/services/ai-client.ts`
- Modify: `packages/database/src/schema/analyses.ts` + 마이그레이션(`varroa_infection_risk`, `estimated_varroa_count` DROP — PR 설명에 데이터 보존 계획 명시: 기존 row는 `vdi`로 역산 불가하므로 `raw_response`에 보관)
- Modify: `apps/mobile` DTO에서 `varroaInfectionRisk` 폴백 제거, `apps/admin/src/lib/types.ts`
- Test: 각 앱 기존 테스트 갱신

- [ ] **Step 1: 사전 조건 확인** — Task 1·2·5·6이 develop에 머지되고 최소 한 번 배포된 뒤에만 시작(체크리스트에 PR 번호 기록).
- [ ] **Step 2~4**: 제거·마이그레이션 generate·전 앱 테스트 PASS.
- [ ] **Step 5: 커밋** `refactor: risk_score/tier_legacy 이중 출력 제거 + 구 컬럼 DROP (계약 v0.2.0 단일화)`

---

### Task 9: ADR-0002 · 문서 정합 · v0.1.0 태그

**Files:**
- Create: `docs/01-development/adr/ADR-0002-two-stage-vdi-redesign.md` (결정·근거·대체 관계·비영리 전제·검증 기록 링크)
- Modify: `apps/ai/CLAUDE.md` §6·§8(응답 스키마·엔진·데이터·위험도 정의를 스펙 v2.1로 교체, `risk.py` shim 명시), `apps/api/CLAUDE.md` §6(계약·타임아웃), `apps/mobile/CLAUDE.md` §8·§9, `packages/database/CLAUDE.md` 테이블 목록, `docs/01-development/frontend-api-integration.md` 분석 응답 예시
- Create: `docs/05-implementation/2026-XX-XX-two-stage-v020.md` (계획 1·2 산출물·게이트 결과·PR 목록)
- Git: `git tag v0.1.0-single-stage <develop의 마지막 v0.1.0 커밋>`

- [ ] **Step 1**: ADR-0002 작성(ADR-0001 형식 준수, Status ACCEPTED, "Supersedes: ADR-0001").
- [ ] **Step 2**: 각 CLAUDE.md의 낡은 문장을 스펙 §3·§4·§8 문구로 교체(자동 gitignore 훅 주의 — CLAUDE.md는 이 레포에서 추적 대상이므로 커밋 전 `.gitignore`에 추가되지 않았는지 `git status`로 확인하고, 추가됐으면 되돌린다).
- [ ] **Step 3**: 태그 생성·push(사용자 승인 후).
- [ ] **Step 4: 커밋** `docs: ADR-0002 two-stage/VDI 재설계 + CLAUDE.md 정합 + v0.1.0 태그`

---

## Self-Review

1. **스펙 커버리지**: §3 출력 계약(T2, T5) · §4 캡처/API/AI 축소 우회(T4, T5, T2) · §8-1~4 이행 순서(T1 → T2 → T5/T6 → T8) · §8 서빙 세부(청크·상한·CAM·타임아웃 체인: T2, T5, T1) · N장 합산(T3) · OpenAI shim·부스 동결(T2, T6) · portfolio 모드(T4) · 회귀 fixture v2(T7) · ADR-0002·문서(T9). **갭**: 증거 크롭 전달 방식(base64 vs presigned)은 T5에 MVP=base64로 고정; `evidence` 크기 상한 40KB×6은 T2 구현자가 `raw_payload` 대신 `evidence[].crop_b64`로 넣도록 Interfaces에 명시됨.
2. **플레이스홀더**: `_ensure` 본문은 "기존 `OnnxYoloEngine._ensure_model` 패턴 재사용"으로 지시 — 해당 코드가 레포에 있어 구현자가 읽을 수 있음. `docs/05-implementation/2026-XX-XX`의 날짜는 실행 시점.
3. **타입 일관성**: `AiAnalysisResult`(T1) ↔ `AnalysisResponse` 새 필드(T2) ↔ 모바일 DTO(T5) ↔ admin types(T6) 필드명 동일(`vdi`, `vdi_display`/`vdiDisplay`, `sampling_ci95`/`vdiCiLow·High`, `bee_total`/`beeTotal`, `bee_infested`/`beeInfested`). `VdiConfig.platt` 추가는 계획 1 Task 9·10 구현자에게 전달(계획 1 Interfaces 갱신 필요 — 실행 시 첫 조치).
4. **Review Focus**: 1→T1, 2→T1·T2, 3→T2, 4→T2, 5→T5. 모두 테스트로 배치됨.
