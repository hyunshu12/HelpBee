"""Stage-2 ONNX CPU 지연 벤치 (v0.2.1 백본 비교용 — 서빙은 CPU ONNX).

Usage (apps/ai 에서):
    python -m training.bench_stage2 --onnx <stage2.onnx> [--img-size 320] [--batch 64] [--threads 4] [--iters 5]
    (= python tasks.py bench-stage2 --onnx ...)

onnxruntime CPUExecutionProvider(intra_op_num_threads=--threads)로 (batch,3,S,S) 난수 입력을 warmup 1회 후
--iters 번 돌려 크롭 1장당 ms 의 p50/p95 를 JSON 한 줄로 출력한다:
    {"onnx", "img_size", "batch", "threads", "ms_per_crop_p50", "ms_per_crop_p95"}
--img-size 생략 시 모델 입력 shape 의 H (정적이 아니면 224). 서빙 청크는 64 (two_stage_engine).
"""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Callable

import numpy as np

from training.train_stage2 import onnx_input_size


def summarize(ms_per_crop) -> tuple[float, float]:
    """반복별 크롭당 ms → (p50, p95). numpy 선형 보간 분위수."""
    a = np.asarray(ms_per_crop, np.float64)
    if a.size == 0:
        raise ValueError("summarize: 측정값이 없다 (iters ≥ 1)")
    p50, p95 = np.percentile(a, [50, 95])
    return float(p50), float(p95)


def make_session(onnx_path: Path, threads: int):
    import onnxruntime as ort

    so = ort.SessionOptions()
    so.intra_op_num_threads = int(threads)
    so.inter_op_num_threads = 1
    so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    return ort.InferenceSession(str(onnx_path), sess_options=so, providers=["CPUExecutionProvider"])


def run_bench(session, img_size: int, batch: int, iters: int, warmup: int = 1, seed: int = 0,
              clock: Callable[[], float] = time.perf_counter) -> list[float]:
    """session.run 을 warmup 회 버린 뒤 iters 회 측정 → 반복별 크롭당 ms 리스트."""
    name = session.get_inputs()[0].name
    x = np.random.default_rng(seed).standard_normal((int(batch), 3, int(img_size), int(img_size))).astype(np.float32)
    for _ in range(int(warmup)):
        session.run(None, {name: x})
    out = []
    for _ in range(int(iters)):
        t0 = clock()
        session.run(None, {name: x})
        out.append((clock() - t0) * 1000.0 / int(batch))
    return out


def bench(onnx: Path, img_size: int | None = None, batch: int = 64, threads: int = 4, iters: int = 5,
          warmup: int = 1) -> dict:
    for k, v in (("batch", batch), ("threads", threads), ("iters", iters)):
        if int(v) < 1:
            raise ValueError(f"--{k} 는 1 이상: {v}")
    sess = make_session(Path(onnx), threads)
    size = int(img_size) if img_size else onnx_input_size(sess.get_inputs()[0].shape)
    p50, p95 = summarize(run_bench(sess, size, batch, iters, warmup))
    return {"onnx": str(onnx), "img_size": size, "batch": int(batch), "threads": int(threads),
            "ms_per_crop_p50": round(p50, 4), "ms_per_crop_p95": round(p95, 4)}


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Stage-2 ONNX CPU 지연 벤치 (크롭당 ms p50/p95)")
    p.add_argument("--onnx", type=Path, required=True, help="stage2.onnx")
    p.add_argument("--img-size", type=int, default=None, help="입력 한 변 (생략 시 모델 입력 shape 에서)")
    p.add_argument("--batch", type=int, default=64, help="배치 = 서빙 청크 (기본 64)")
    p.add_argument("--threads", type=int, default=4, help="onnxruntime intra_op_num_threads (기본 4)")
    p.add_argument("--iters", type=int, default=5, help="측정 반복 (warmup 1회 별도)")
    return p


def main(argv: list[str] | None = None) -> dict:
    a = build_parser().parse_args(argv)
    res = bench(a.onnx, a.img_size, a.batch, a.threads, a.iters)
    print(json.dumps(res, ensure_ascii=False))
    return res


if __name__ == "__main__":
    main()
