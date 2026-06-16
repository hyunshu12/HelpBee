# 2026-06-16 — YOLO 추론 파이프라인 수정 (ONNX decode + 전처리 skew)

> PR: **#24**(decode) · **#25**(전처리 q95, #24에 stacked) · 브랜치: `bugfix/yolo-onnx-postprocess`, `bugfix/yolo-preprocess-quality` → develop · 상태: **둘 다 OPEN(미머지, 2026-06-16)**
>
> ⚠️ 이 문서는 **머지 전 핸드오프**다. 두 PR이 머지되면 머지일/최종 상태로 갱신할 것. cold-pickup AI는 §6(현황/후속)부터 보면 빠르다.

---

## 1. 배경 — 왜 이 작업이 시작됐나

사용자가 "AWS에 있는 v0.1.0 모델로 벌통 사진 1장을 추론해 달라"고 요청. 추론을 준비하는 과정에서
**프로덕션 YOLO 추론이 실제로는 깨져 있었음**이 드러났고, 검증 중 **두 번째(더 중요한) 버그**까지
발견되어 두 개의 수정 PR로 분리했다.

상태 진단 결과(2026-06-16 기준):
- v0.1.0 YOLO 모델은 **학습 완료**되어 S3에만 존재(`s3://helpbee-models/yolo/v0.1.0/{best.pt,best.onnx,metadata.json}`).
- **추론 서버(ECS)는 아직 미배포** — 인프라는 Terraform 골격 단계. 즉 "AWS에 떠 있는 추론 엔드포인트"는 없고 가중치만 있음.
- 추론은 S3의 `best.onnx`를 받아 **로컬 CPU ONNX**로 수행(~0.3s).

---

## 2. 발견한 버그 2개

### 버그 A — ONNX decode 포맷 불일치 (PR #24)
- v0.1.0 `best.onnx`는 `export(format='onnx', dynamic=True, simplify=True, imgsz=640)` 즉 **`nms=False`** 로 산출됨
  → 출력이 **raw 텐서 `[1, 4+nc, N]`(=`[1,7,8400]`, 3-class)**.
- 그런데 `apps/ai/app/services/yolo_engine.py:_infer`는 **NMS 적용본 `[N,6]`(`[x1,y1,x2,y2,score,class_id]`)을 가정** +
  `Image.resize((640,640))` naive 리사이즈로 **종횡비까지 왜곡** → 디코드 결과가 사실상 garbage.
- 추가로 `requirements.txt`에 **`numpy`/`onnxruntime`/`boto3` 누락** → clean 배포 시 numpy 부재로 **FastAPI 부팅 자체가 실패**
  (numpy가 모듈 top import이며 부팅 체인 `main.py→routers/analyze→deps→yolo_engine`에 있음), onnxruntime/boto3 부재로 추론 1회도 불가.

### 버그 B — 서빙 전처리 train/serve skew (PR #25)
- `apps/ai/app/services/preprocess.py`의 **JPEG q85 재압축**이 응애의 미세 시각 신호를 약화시켜,
  YOLO 검출 앵커의 **클래스 argmax를 `bee_with_varroa` → `bee_normal` 로 뒤집어 false negative(SAFE 오진)** 를 유발.
  - 원인은 **q85 재압축**임이 분해 측정으로 확인됨(긴변 1024 다운스케일·리샘플링 단독으로는 안 뒤집힘; 둘 다 + q85 필요).
- `apps/ai/training/eval.py`(golden 평가)는 **원본 이미지를 ultralytics에 직접 letterbox** 하여 이 전처리를 **거치지 않음**
  → golden varroa recall 0.95 / mAP 0.9159가 **서빙 경로 정확도를 과대평가**(= train/serve skew, golden 게이트가 이 결함을 못 잡음).
- 빈도: 적대적 검증 결과 **드문 경계 케이스**(측정상 varroa 95장 중 검출 flip 1장 / tier flip 2장). 처음 요청 이미지가 하필 그 케이스였음.

---

## 3. 수정 내용

### PR #24 — `bugfix/yolo-onnx-postprocess` (base develop)
| 파일 | 변경 |
|---|---|
| `apps/ai/app/services/yolo_engine.py` | `letterbox()`(aspect-preserving 640 + 회색114 패딩), `decode_detections()`(argmax→conf0.25→**per-class NMS** iou0.5, `[1,4+nc,N]`/`[1,N,4+nc]` 모두 처리), `_xywh_to_xyxy`/`_iou`/`_nms` 추가. `_infer` 재배선(letterbox→session→decode). `OnnxYoloEngine`에 `iou_threshold` 추가. numpy top import. |
| `apps/ai/requirements.txt` | `numpy(>=1.24,<2.0)`/`onnxruntime==1.23.2`/`boto3==1.43.30` 추가. numpy 핀 단일 소스화. |
| `apps/ai/requirements-gpu.txt` | 중복 numpy 핀 제거(requirements.txt에서 상속). |
| `apps/ai/app/tests/unit/test_yolo_decode.py` | 신규 8종 (orientation 전치, per-class 보존, NMS 억제, conf 필터, row-major, empty). |

### PR #25 — `bugfix/yolo-preprocess-quality` (base #24, stacked)
| 파일 | 변경 |
|---|---|
| `apps/ai/app/services/preprocess.py` | `QUALITY_CASCADE (85,80,75) → (95,90,85)`. 공유 전처리라 OpenAI 경로도 q95. |
| `apps/ai/app/tests/unit/test_yolo_serving_regression.py` | 신규. 알려진 응애 양성이 **서빙 전 파이프라인**(preprocess→letterbox→ONNX→decode→compute_risk)에서 검출되고 `tier != 'safe'` 임을 보장. 모델/샘플 git-ignored라 부재 시 `skip`. |
| `apps/ai/pytest.ini` | `regression` 마커 등록(CLAUDE.md §10-3에서 사용 전제였으나 미등록 상태였음). |
| `apps/ai/CLAUDE.md` | §7-4 전처리 q85→q95 동기화. |

---

## 4. 검증 (Verification)

```bash
# 추론 venv (CPU): onnxruntime, numpy, pillow, pyyaml, boto3
PY=apps/ai/.venv/bin/python   # 로컬 기준; CI는 requirements.txt 설치
$PY -m pytest apps/ai/app/tests/unit -q
```

- **PR #24**: 단위 **65 PASS**. 부팅 체인 `import app.services.yolo_engine` OK. 실모델(best.onnx)로 **검증 경로(원본 직접 letterbox)** 재현 → `class_counts {normal:8, varroa:1, other:0}`, infestation 11.1%, **risk 73, tier DANGER** (eval/golden 경로와 일치).
- **PR #25**: 단위 **66 PASS**(회귀 테스트 RED→GREEN). 서빙 경로 측정(샘플 `성충_응애/012`):

  | JPEG q | varroa | tier | bytes |
  |---|---|---|---|
  | q85 (기존) | 0 | **safe (오진)** | 135KB |
  | **q95 (수정)** | **1** | **watch (회복)** | 235KB |

  normal 30장에서 **false positive 증가 0**.
- **적대적 검증 워크플로**(16 에이전트): decode/NMS/letterbox 정확성 독립 확정, 오탐 3건 기각("LANCZOS가 원인"·"nms=True 오독"·"EXIF/타입 nit").

---

## 5. 로컬에서 추론 재현하는 법 (다른 AI/사람용)

```bash
# 1) AWS 자격증명 — IAM user claude_helpBee (루트 아님), region ap-northeast-2
#    helpbee-models 에 s3:GetObject + s3:ListBucket(prefix yolo/v0.1.0/*) 권한 필요
aws s3 cp s3://helpbee-models/yolo/v0.1.0/best.onnx /tmp/hbcache/v0.1.0/best.onnx

# 2) 추론 패키지 (CPU)
pip install onnxruntime numpy boto3 pyyaml pillow

# 3) 정식 서빙 경로로 추론
python - <<'PY'
import sys; from pathlib import Path
sys.path.insert(0, "apps/ai")
from app.services.yolo_engine import OnnxYoloEngine
from app.services.orchestrator import run_analysis
eng = OnnxYoloEngine(model_version="v0.1.0", cache_dir="/tmp/hbcache")
resp = run_analysis(Path("<image.jpg>").read_bytes(), engine="yolo", yolo=eng, openai=None)
print(resp.risk_score, resp.tier, resp.raw_payload)
PY
```
- ⚠️ 위는 **PR #24+#25가 적용된 코드** 기준. develop 머지 전이면 해당 브랜치/worktree에서 실행할 것.
- 클래스 id: `0=bee_normal, 1=bee_with_varroa, 2=bee_other_disease`. risk/tier 정의는 `training/configs/risk.yaml` + `app/services/risk.py`.

---

## 6. 현황 / 후속 작업 (Follow-up) ★ cold-pickup 우선

- [ ] **PR #24 → develop 머지** (리뷰 후). 그 다음 **#25 base를 develop로 재타겟** → 머지 (그래야 #25 diff가 q95 변경만 깔끔).
      - 2026-06-16 현재 둘 다 OPEN/MERGEABLE. develop은 #26(mobile) 머지로 343b344까지 진전됨 — 충돌 없음.
- [ ] **(중요) golden eval을 서빙 전처리로 정렬** — 현재 `eval.py`는 원본 직접 letterbox라 q85/q95 같은 전처리 결함을 **못 잡는다**.
      `eval.py`가 `preprocess_image`를 거치게 하거나 "서빙경로 golden" 변형을 추가해 q85↔q95 **varroa recall delta를 정량화**하고,
      `test_yolo_serving_regression.py`를 라벨 기반 평가로 격상할 것. **q95가 충분한지는 이 평가로만 판정 가능.**
- [ ] **q95 충분성 미검증** — 이번엔 **golden 셋이 로컬에 없어** 라벨 기반 정식 recall 검증을 못 함.
      폴더명 ≠ 라벨(`성충_응애` 폴더에도 정상벌 다수, `AIHUB_71667.md §3`)이라 폴더 기준 recall은 신뢰 불가.
      현재 근거는 **단일 이미지 회복 + normal 30장 FP-무증가 스모크** 뿐.
- [ ] **decode/NMS는 정상이므로 절대 NMS를 건드려 "고치지" 말 것** — false negative의 진짜 원인은 전처리(q)다. (미래 오진 방지)
- [ ] (운영, 본 작업 무관) **AWS ROOT 키 회전 P0** 여전히 미해결 — v0.1.0 업로드에 root 키 사용됨(`2026-06-08-v010-yolo-baseline.md` 후속 참조).
- 작업 격리용 worktree 3개 사용: `yolo-onnx-fix`(#24), `yolo-preprocess-quality`(#25), `yolo-docs-handoff`(이 문서). 머지 후 정리 가능.

---

## 7. 참조

- 권위 가이드: [`apps/ai/CLAUDE.md`](../../apps/ai/CLAUDE.md) — §7-4 전처리, §8 YOLO, §13 회귀 게이트
- 코드: `apps/ai/app/services/yolo_engine.py`(decode), `preprocess.py`(q), `orchestrator.py`(run_analysis), `risk.py`(infestation_rate)
- 모델/데이터: [`2026-06-08-v010-yolo-baseline.md`](./2026-06-08-v010-yolo-baseline.md)(학습·export·S3·sign-off), [`AIHUB_71667.md`](../../apps/ai/training/datasets/AIHUB_71667.md)(라벨 특성), [ADR-0001](../01-development/adr/ADR-0001-yolo-engine-architecture.md)
- 모델 메타: `s3://helpbee-models/yolo/v0.1.0/metadata.json`(classes/imgsz/conf/iou/golden_eval)
