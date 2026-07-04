"""회귀 게이트용 fixture 매니페스트 생성기 (apps/ai/CLAUDE.md §10-2).

무엇을 하나:
    AI Hub 71667 Sample(330장)에서 클래스별로 결정적(seed 고정)으로 ~24장을 골라,
    **서빙 경로 그대로**(preprocess → YOLO(ONNX) → risk) 돌린 현재 출력을
    기대값으로 박제한 매니페스트를 쓴다.

왜 매니페스트만 커밋하나 (라이선스):
    71667 원본 이미지는 재배포 금지(내국인 제약)다. 이미지 자체는 절대 git에 넣지
    않는다. 대신 이미지의 **상대경로 + sha256 + 기대 risk_score/tier**만 커밋한다.
    회귀 테스트는 로컬에 데이터셋/모델이 있을 때만 실제로 돌고, 없으면 skip 한다.

이건 정확도(ground-truth) 테스트가 아니라 **스냅샷/회귀** 테스트다:
    기대값 = "현재 모델의 서빙 출력". 프롬프트/모델핀/risk 가중치가 바뀌어
    출력이 ±10(risk) 또는 tier가 흔들리면 게이트가 잡는다.

결정성:
    - 각 클래스 폴더의 이미지 경로를 정렬 후 seed 고정 셔플 → 앞 N개.
    - created_at 만 실행 시각(메타)이고, 선택/기대값은 재실행해도 동일.
    - 재실행 시 fixtures 배열은 byte-identical (determinism 증명).

사용:
    ./.venv/bin/python -m training.data.make_regression_fixtures \\
        --created-at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import random
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger(__name__)

# training/data/make_regression_fixtures.py → parents[2] = apps/ai
AI_ROOT = Path(__file__).resolve().parents[2]
SAMPLE_ROOT = AI_ROOT / "training" / "datasets" / "Sample" / "01.원천데이터"
MANIFEST_PATH = AI_ROOT / "app" / "tests" / "fixtures" / "regression_manifest.json"

SCRIPT_VERSION = "1.0.0"
SELECTION_SEED = 42
MODEL_VERSION = "v0.1.0"

# (class_folder 상대명, 뽑을 장수). 성충/유충을 섞어 카메라 거리·개체 크기 분포를 다양화.
#   응애 8 / 정상 8 / 기타질병 8 = 24
SELECTION_PLAN: tuple[tuple[str, int], ...] = (
    ("성충/성충_응애", 4),
    ("유충/유충_응애", 4),
    ("성충/성충_정상", 4),
    ("유충/유충_정상", 4),
    ("성충/성충_날개불구바이러스감염증", 3),
    ("유충/유충_부저병", 3),
    ("유충/유충_석고병", 2),
)


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _select_images(folder_rel: str, n: int, seed: int) -> list[Path]:
    """class_folder 안의 모든 jpg를 정렬 후 seed 셔플 → 앞 n개 (결정적)."""
    root = SAMPLE_ROOT / folder_rel
    imgs = sorted(root.rglob("*.jpg"))
    if len(imgs) < n:
        raise SystemExit(f"이미지 부족: {folder_rel} 에 {len(imgs)} < {n}")
    # 폴더별 독립 셔플 — folder_rel 로 seed 를 섞어 폴더마다 다른 순열.
    rng = random.Random(f"{seed}:{folder_rel}")
    picks = imgs[:]
    rng.shuffle(picks)
    return picks[:n]


def build_manifest(created_at: str, seed: int = SELECTION_SEED) -> dict:
    # 서빙 경로 임포트는 여기서 (스크립트 헬프만 볼 때 무거운 의존 로드 방지)
    from app.services.orchestrator import run_analysis
    from app.services.yolo_engine import (
        DEFAULT_CONF,
        DEFAULT_IMGSZ,
        DEFAULT_IOU,
        OnnxYoloEngine,
    )

    os.environ.setdefault("OMP_NUM_THREADS", "1")
    cache_dir = str(Path.home() / ".cache" / "helpbee" / "yolo")
    engine = OnnxYoloEngine(MODEL_VERSION, cache_dir=cache_dir)

    entries: list[dict] = []
    for folder_rel, n in SELECTION_PLAN:
        for img_path in _select_images(folder_rel, n, seed):
            data = img_path.read_bytes()
            # 서빙과 동일 경로: run_analysis(engine="yolo") → preprocess→YOLO→risk
            res = run_analysis(data, engine="yolo", yolo=engine)
            rel = img_path.relative_to(AI_ROOT).as_posix()
            entries.append(
                {
                    "path": rel,
                    "sha256": _sha256(data),
                    "class_folder": folder_rel.split("/")[-1],
                    "expected_risk_score": res.risk_score,
                    "expected_tier": res.tier,
                    # 디버그 보조 (게이트 판정엔 미사용)
                    "bee_total": res.raw_payload.get("bee_total"),
                    "infestation_rate": res.raw_payload.get("infestation_rate"),
                }
            )
            logger.info(
                "%-24s risk=%s tier=%s (bees=%s)",
                Path(rel).name,
                res.risk_score,
                res.tier,
                res.raw_payload.get("bee_total"),
            )

    # fixtures 는 결정적 정렬 (path 기준) — 재실행 byte-identical 보장
    entries.sort(key=lambda e: e["path"])
    return {
        "_comment": (
            "회귀 게이트 매니페스트. 이미지는 라이선스(AI Hub 71667 재배포 금지)로 "
            "커밋하지 않는다 — path/sha256/기대값만. 생성: "
            "python -m training.data.make_regression_fixtures"
        ),
        "metadata": {
            "script_version": SCRIPT_VERSION,
            "model_version": MODEL_VERSION,
            "conf": DEFAULT_CONF,
            "iou": DEFAULT_IOU,
            "imgsz": DEFAULT_IMGSZ,
            "selection_seed": seed,
            "dataset": "AI Hub 71667 Sample",
            "serving_path": "run_analysis(engine='yolo') → preprocess→yolo→risk",
            "count": len(entries),
            "created_at": created_at,
        },
        "fixtures": entries,
    }


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    p = argparse.ArgumentParser()
    p.add_argument(
        "--created-at",
        default=None,
        help="ISO8601 생성 시각 (미지정 시 현재 UTC). 예: $(date -u +%Y-%m-%dT%H:%M:%SZ)",
    )
    p.add_argument("--seed", type=int, default=SELECTION_SEED)
    p.add_argument("--out", type=Path, default=MANIFEST_PATH)
    args = p.parse_args()

    created_at = args.created_at or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    manifest = build_manifest(created_at, seed=args.seed)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    tiers: dict[str, int] = {}
    scores = [e["expected_risk_score"] for e in manifest["fixtures"]]
    for e in manifest["fixtures"]:
        tiers[e["expected_tier"]] = tiers.get(e["expected_tier"], 0) + 1
    logger.info("\n===== 매니페스트 =====")
    logger.info("%d fixtures → %s", len(manifest["fixtures"]), args.out)
    logger.info("tier 분포: %s", tiers)
    if scores:
        srt = sorted(scores)
        logger.info(
            "risk_score min/median/max: %s / %s / %s",
            srt[0],
            srt[len(srt) // 2],
            srt[-1],
        )


if __name__ == "__main__":
    main()
