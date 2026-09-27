"""회귀 게이트 fixture 매니페스트 v2 생성기 — two-stage 서빙 경로 스냅샷 (apps/ai/CLAUDE.md §10-2).

무엇을 하나:
    AI Hub 71667 Sample(330장) 전부 + 합성 파생 이미지(0마리 3장, 블러 3장)를 **서빙 경로
    그대로**(run_analysis(engine="yolo", two_stage=OnnxTwoStageEngine) → decode→Stage-1→Stage-2→VDI)
    돌린 뒤, 케이스 선정 규칙(select_cases)으로 24~30장을 골라 현재 출력(vdi_display/tier/bee_total)을
    기대값으로 박제한다.

케이스 (스펙 §7 회귀 row, v2.2 — EV2 는 이 Mac 에 없어 Sample 기반으로 대체):
    boundary           vdi_display 가 tier 경계(3.0/10.0)에 가장 가까운 것 (±0.5 우선, 부족하면 최근접)
    low_count          bee_total 1~5
    healthy            성충_정상 폴더 + bee_infested 0
    dense              bee_total 상위
    zero_bees          합성(벌 없는 소비판 텍스처·노이즈 1920×1080) → bee_total 0
    blur               Sample 에 GaussianBlur → quality.ok false
    varroa_visible_no  성충_응애 폴더인데 bee_infested 0 (숨은 응애 — 모델이 못 보는 케이스)

라이선스:
    71667 원본/파생 이미지는 재배포 금지 — 이미지는 절대 커밋하지 않는다. 매니페스트에는
    datasets 디렉터리 기준 상대경로 + sha256 + 기대값만. 파생 이미지는
    training/datasets/Sample_derived/ (gitignored, `training/datasets/*`) 에 결정적으로 생성.

결정성:
    seed 42 고정. 파생 이미지는 numpy RNG(seed) + PIL 고정 품질 → 같은 환경에서 byte-identical.
    created_at 은 metadata 에 넣지 않는다 → 재실행 시 매니페스트 전체가 byte-identical.

datasets 디렉터리 탐색 (Sample/ 이 있는 첫 번째):
    $HELPBEE_DATASETS_DIR → apps/ai/training/datasets → (git worktree 면) 메인 체크아웃의 같은 경로.

사용:
    ./.venv/bin/python -m training.data.make_regression_fixtures
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import subprocess
import unicodedata
from pathlib import Path

import numpy as np

logger = logging.getLogger(__name__)

# training/data/make_regression_fixtures.py → parents[2] = apps/ai
AI_ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = AI_ROOT / "app" / "tests" / "fixtures" / "regression_manifest.json"
BUNDLE_VERSION = "v0.2.0"
BUNDLE_CACHE = Path(os.getenv("TWO_STAGE_CACHE_DIR") or Path.home() / ".cache" / "helpbee" / "two-stage")
# stage2 학습 런 이름 (training/eval_history/v0.2.0-stage2.json 의 weights 경로) — 번들 metadata 엔 없음.
STAGE2_RUN = "v0.2.0-stage2v3-E3"

SCRIPT_VERSION = "2.0.0"
SELECTION_SEED = 42
DERIVED_DIRNAME = "Sample_derived"
SAMPLE_IMG_SUBDIR = "Sample/01.원천데이터"
# 회귀 게이트는 예산 초과(→graceful)로 스냅샷이 흔들리지 않게 넉넉한 예산을 쓴다 (서빙 기본 80s).
REGRESSION_BUDGET_S = 600.0

# 선정 우선순위 = 튜플 순서 (한 이미지는 한 케이스에만). 합계 25.
CASES: tuple[str, ...] = (
    "zero_bees",
    "blur",
    "boundary",
    "varroa_visible_no",
    "healthy",
    "low_count",
    "dense",
)
CASE_QUOTA: dict[str, int] = {
    "zero_bees": 3,
    "blur": 3,
    "boundary": 4,
    "varroa_visible_no": 4,
    "healthy": 4,
    "low_count": 4,
    "dense": 3,
}
TIER_BOUNDARIES = (3.0, 10.0)  # vdi.yaml thresholds.elevated / high
BLUR_SOURCES = 3
ZERO_BEE_SOURCES = 3


# ── 경로 탐색 ─────────────────────────────────────────────────────────────────
def _main_checkout_datasets() -> Path | None:
    """git worktree 라면 메인 체크아웃의 apps/ai/training/datasets (Sample 은 거기에만 있을 수 있다)."""
    try:
        common = subprocess.run(
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
            cwd=AI_ROOT, capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    return Path(common).parent / "apps" / "ai" / "training" / "datasets"


def find_datasets_dir() -> Path | None:
    """Sample/ 을 가진 datasets 디렉터리 (없으면 None)."""
    cands: list[Path] = []
    if os.getenv("HELPBEE_DATASETS_DIR"):
        cands.append(Path(os.environ["HELPBEE_DATASETS_DIR"]))
    cands.append(AI_ROOT / "training" / "datasets")
    main = _main_checkout_datasets()
    if main is not None:
        cands.append(main)
    for c in cands:
        if (c / SAMPLE_IMG_SUBDIR).is_dir():
            return c
    return None


def bundle_dir(version: str = BUNDLE_VERSION) -> Path:
    return BUNDLE_CACHE / version


def _nfc(s: str) -> str:
    """macOS(APFS)는 한글 경로를 NFD 로 돌려준다 — 비교/기록은 NFC 로 통일 (APFS 는 조회 시 정규화 무관)."""
    return unicodedata.normalize("NFC", s)


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# ── 케이스 선정 (순수) ────────────────────────────────────────────────────────
def _boundary_distance(vdi_display) -> float:
    if vdi_display is None or (isinstance(vdi_display, float) and np.isnan(vdi_display)):
        return float("inf")
    v = float(vdi_display)
    return min(abs(v - b) for b in TIER_BOUNDARIES)


def select_cases(df, seed: int = SELECTION_SEED, quota: dict[str, int] | None = None):
    """후보 DataFrame → case 컬럼이 붙은 선정 DataFrame (path 정렬).

    df 컬럼: path, source("sample"|"zero_bees"|"blur"), class_folder, bee_total, bee_infested,
             vdi_display(str|None), tier, quality_ok.
    입력 순서와 무관하게 결정적 (path 정렬 후 seed 순열 / 키 정렬).
    """
    import pandas as pd

    quota = quota or CASE_QUOTA
    pool = df.assign(
        path=df["path"].map(_nfc), class_folder=df["class_folder"].map(_nfc)
    ).sort_values("path", kind="mergesort").reset_index(drop=True)
    taken: set[str] = set()
    picked: list = []

    def _avail(mask):
        sub = pool[mask]
        return sub[~sub["path"].isin(taken)]

    def _seeded(sub, case_i: int, n: int):
        if len(sub) <= n:
            return sub
        rng = np.random.default_rng(seed + case_i)
        idx = np.sort(rng.permutation(len(sub))[:n])
        return sub.iloc[idx]

    sample_ok = (pool["source"] == "sample") & pool["quality_ok"].astype(bool) & (pool["bee_total"] > 0)
    for i, case in enumerate(CASES):
        n = quota[case]
        if case == "zero_bees":
            sel = _seeded(_avail((pool["source"] == "zero_bees") & (pool["bee_total"] == 0)), i, n)
        elif case == "blur":
            sel = _seeded(_avail((pool["source"] == "blur") & ~pool["quality_ok"].astype(bool)), i, n)
        elif case == "boundary":
            sub = _avail(sample_ok & pool["vdi_display"].notna()).copy()
            sub["_d"] = sub["vdi_display"].map(_boundary_distance)
            sel = sub.sort_values(["_d", "path"], kind="mergesort").head(n).drop(columns="_d")
        elif case == "varroa_visible_no":
            sel = _seeded(_avail(sample_ok & (pool["class_folder"] == "성충_응애") & (pool["bee_infested"] == 0)), i, n)
        elif case == "healthy":
            sel = _seeded(_avail(sample_ok & (pool["class_folder"] == "성충_정상") & (pool["bee_infested"] == 0)), i, n)
        elif case == "low_count":
            sel = _seeded(_avail(sample_ok & pool["bee_total"].between(1, 5)), i, n)
        elif case == "dense":
            sub = _avail(sample_ok).copy()
            sub["_neg"] = -sub["bee_total"]
            sel = sub.sort_values(["_neg", "path"], kind="mergesort").head(n).drop(columns="_neg")
        else:  # pragma: no cover
            raise ValueError(case)
        sel = sel.assign(case=case)
        taken.update(sel["path"])
        picked.append(sel)
    out = pd.concat(picked, ignore_index=True)
    return out.sort_values("path", kind="mergesort").reset_index(drop=True)


# ── 파생 이미지 (합성 0마리 / 블러) ───────────────────────────────────────────
def _encode_jpeg(arr: np.ndarray) -> bytes:
    import io

    from PIL import Image

    buf = io.BytesIO()
    Image.fromarray(np.ascontiguousarray(arr, dtype=np.uint8)).save(buf, format="JPEG", quality=92, optimize=False)
    return buf.getvalue()


def _synthetic_zero_bee(kind: int, rng: np.random.Generator, hw=(1080, 1920)) -> np.ndarray:
    """벌 없는 이미지: 0=빈 소비판(육각 셀 격자) 1=균일 노이즈 2=평탄 밀랍색 + 약한 노이즈."""
    h, w = hw
    if kind == 0:
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        r = 28.0  # 셀 반경 px
        # 육각 격자 근사: 두 방향 코사인 간섭 → 셀 벽 패턴
        a = np.cos(2 * np.pi * xx / (r * 1.732)) + np.cos(2 * np.pi * (xx / 2 + yy * 0.866) / (r * 1.732))
        a += np.cos(2 * np.pi * (xx / 2 - yy * 0.866) / (r * 1.732))
        wall = (a > 1.2).astype(np.float32)
        base = np.stack([205 + 30 * wall, 160 + 30 * wall, 70 + 20 * wall], -1)
        img = base + rng.normal(0, 6, (h, w, 3))
    elif kind == 1:
        img = rng.uniform(0, 255, (h, w, 3))
    else:
        img = np.array([196, 150, 62], np.float32) + rng.normal(0, 10, (h, w, 3))
    return np.clip(img, 0, 255).astype(np.uint8)


def _blurred(jpeg: bytes, radius: float = 12.0) -> bytes:
    import io

    from PIL import Image, ImageFilter

    im = Image.open(io.BytesIO(jpeg)).convert("RGB").filter(ImageFilter.GaussianBlur(radius))
    return _encode_jpeg(np.asarray(im))


def make_derived(datasets: Path, blur_sources: list[Path], seed: int = SELECTION_SEED) -> list[tuple[Path, str]]:
    """Sample_derived/ 에 합성 0마리·블러 이미지를 결정적으로 쓴다 → [(path, source)]."""
    out_dir = datasets / DERIVED_DIRNAME
    out_dir.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(seed)
    made: list[tuple[Path, str]] = []
    for k in range(ZERO_BEE_SOURCES):
        p = out_dir / f"zero_bees_{k}.jpg"
        p.write_bytes(_encode_jpeg(_synthetic_zero_bee(k, rng)))
        made.append((p, "zero_bees"))
    for src in blur_sources:
        p = out_dir / f"blur_{src.stem}.jpg"
        p.write_bytes(_blurred(src.read_bytes()))
        made.append((p, "blur"))
    return made


def _pick_blur_sources(sample_dir: Path, seed: int) -> list[Path]:
    """성충_정상에서 seed 순열로 블러 원본 선택 (정렬 후 → 결정적)."""
    imgs = sorted((sample_dir / "성충" / "성충_정상").rglob("*.jpg"))
    rng = np.random.default_rng(seed)
    return [imgs[i] for i in sorted(rng.permutation(len(imgs))[:BLUR_SOURCES])]


# ── 실행 ─────────────────────────────────────────────────────────────────────
def load_engine():
    from app.services.two_stage_engine import OnnxTwoStageEngine

    # 서빙(app/deps.get_two_stage_engine)과 같은 생성 — S3 미사용(로컬 캐시만).
    return OnnxTwoStageEngine(BUNDLE_VERSION, cache_dir=str(BUNDLE_CACHE), s3_bucket=None)


def analyze(engine, data: bytes):
    from app.services.orchestrator import run_analysis

    # 서빙과 동일: engine="yolo"(무료·폴백 금지) + two_stage 엔진 → vdi_cfg/extras 는 엔진 번들.
    return run_analysis(data, engine="yolo", two_stage=engine, budget_s=REGRESSION_BUDGET_S)


def scan(datasets: Path, engine, seed: int = SELECTION_SEED):
    import pandas as pd

    sample_dir = datasets / SAMPLE_IMG_SUBDIR
    items: list[tuple[Path, str]] = [(p, "sample") for p in sorted(sample_dir.rglob("*.jpg"))]
    items += make_derived(datasets, _pick_blur_sources(sample_dir, seed), seed)
    rows = []
    for n, (p, source) in enumerate(items, 1):
        data = p.read_bytes()
        res = analyze(engine, data)
        folder = _nfc(p.parent.parent.name) if source == "sample" else "synthetic" if source == "zero_bees" else "성충_정상"
        rows.append(
            {
                "path": _nfc(p.relative_to(datasets).as_posix()),
                "sha256": _sha256(data),
                "source": source,
                "class_folder": folder,
                "bee_total": int(res.bee_total or 0),
                "bee_infested": int(res.bee_infested or 0),
                "vdi_display": res.vdi_display,
                "tier": res.tier,
                "quality_ok": bool((res.quality or {}).get("ok", True)),
            }
        )
        if n % 25 == 0:
            logger.info("scan %d/%d", n, len(items))
    return pd.DataFrame(rows)


def _file_sha(p: Path) -> str:
    return _sha256(p.read_bytes())


def _none_if_na(v):
    return None if v is None or (isinstance(v, float) and np.isnan(v)) else v


def build_manifest(datasets: Path, seed: int = SELECTION_SEED, scan_cache: Path | None = None) -> dict:
    """scan_cache: 지정 시 스캔 결과 CSV 를 재사용/저장 (선정 규칙 반복용 — 파생 이미지는 이미 있어야 함)."""
    import pandas as pd
    import yaml

    os.environ.setdefault("OMP_NUM_THREADS", "1")
    if scan_cache is not None and scan_cache.exists():
        df = pd.read_csv(scan_cache, dtype={"vdi_display": "string"}).astype({"vdi_display": object})
        df["vdi_display"] = df["vdi_display"].map(lambda v: None if pd.isna(v) else str(v))
    else:
        df = scan(datasets, load_engine(), seed)
        if scan_cache is not None:
            df.to_csv(scan_cache, index=False)
    sel = select_cases(df, seed)
    bdir = bundle_dir()
    vdi = yaml.safe_load((bdir / "vdi.yaml").read_text(encoding="utf-8"))
    fixtures = [
        {
            "path": r.path,
            "sha256": r.sha256,
            "case": r.case,
            "class_folder": r.class_folder,
            "expected_vdi_display": _none_if_na(r.vdi_display),
            "expected_tier": r.tier,
            "expected_bee_total": int(r.bee_total),
            # 디버그 보조 (게이트 판정엔 미사용)
            "bee_infested": int(r.bee_infested),
            "quality_ok": bool(r.quality_ok),
        }
        for r in sel.itertuples(index=False)
    ]
    return {
        "_comment": (
            "회귀 게이트 매니페스트 v2 (two-stage 서빙 경로). 이미지는 라이선스(AI Hub 71667 재배포 금지)로 "
            "커밋하지 않는다 — datasets 디렉터리 기준 path/sha256/기대값만. "
            "생성: python -m training.data.make_regression_fixtures"
        ),
        "metadata": {
            "manifest_version": 2,
            "script_version": SCRIPT_VERSION,
            "bundle_version": BUNDLE_VERSION,
            "model_versions": {"stage1": BUNDLE_VERSION, "stage2": STAGE2_RUN, "vdi_config": vdi.get("version")},
            "vdi_config_sha": _file_sha(bdir / "vdi.yaml"),
            "stage1_sha": _file_sha(bdir / "stage1.onnx"),
            "stage2_sha": _file_sha(bdir / "stage2.onnx"),
            "tau": vdi.get("tau"),
            "thresholds": vdi.get("thresholds"),
            "quality": vdi.get("quality"),
            "tolerance": {"vdi_abs": 1.0, "tier_change": 0, "bee_total_rel": 0.10},
            "selection_seed": seed,
            "case_quota": CASE_QUOTA,
            "dataset": "AI Hub 71667 Sample + Sample_derived(합성 0마리·블러)",
            "serving_path": "run_analysis(engine='yolo', two_stage=OnnxTwoStageEngine) → Stage-1→Stage-2→VDI",
            "scanned": int(len(df)),
            "count": len(fixtures),
        },
        "fixtures": fixtures,
    }


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    p = argparse.ArgumentParser()
    p.add_argument("--seed", type=int, default=SELECTION_SEED)
    p.add_argument("--out", type=Path, default=MANIFEST_PATH)
    p.add_argument("--datasets-dir", type=Path, default=None, help="Sample/ 을 가진 datasets 디렉터리")
    p.add_argument("--scan-cache", type=Path, default=None, help="스캔 결과 CSV 재사용/저장 (개발용)")
    args = p.parse_args()

    datasets = args.datasets_dir or find_datasets_dir()
    if datasets is None:
        raise SystemExit("71667 Sample 을 찾지 못했다 — HELPBEE_DATASETS_DIR 지정")
    if not all((bundle_dir() / f).exists() for f in ("stage1.onnx", "stage2.onnx", "vdi.yaml", "metadata.json")):
        raise SystemExit(f"two-stage 번들 없음: {bundle_dir()}")
    manifest = build_manifest(datasets, seed=args.seed, scan_cache=args.scan_cache)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    counts: dict[str, int] = {}
    tiers: dict[str, int] = {}
    for e in manifest["fixtures"]:
        counts[e["case"]] = counts.get(e["case"], 0) + 1
        tiers[e["expected_tier"]] = tiers.get(e["expected_tier"], 0) + 1
    logger.info("\n===== 매니페스트 v2 =====")
    logger.info("%d fixtures (scanned %d) → %s", len(manifest["fixtures"]), manifest["metadata"]["scanned"], args.out)
    logger.info("case 분포: %s", counts)
    logger.info("tier 분포: %s", tiers)


if __name__ == "__main__":
    main()
