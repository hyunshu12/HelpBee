# apps/ai/app/tests/unit/test_bench_stage2.py
"""Stage-2 ONNX CPU 지연 벤치 (v0.2.1). 합성 ONNX 는 onnx/onnxruntime 있을 때만 (importorskip)."""
import json

import numpy as np
import pytest

from training.bench_stage2 import build_parser, run_bench, summarize


def test_summarize_percentiles():
    assert summarize([1.0, 2.0, 3.0, 4.0, 5.0]) == (3.0, 4.8)
    assert summarize([2.5]) == (2.5, 2.5)
    with pytest.raises(ValueError):
        summarize([])


class _Inp:
    name = "image"
    shape = ["b", 3, 32, 32]


class _FakeSession:
    def __init__(self):
        self.calls = []

    def get_inputs(self):
        return [_Inp()]

    def run(self, outputs, feeds):
        self.calls.append(feeds["image"].shape)
        return [np.zeros(feeds["image"].shape[0], np.float32)]


def test_run_bench_warmup_iters_and_per_crop_ms():
    sess = _FakeSession()
    ticks = iter([0.0, 0.8, 1.0, 1.4])  # 반복 2회: 800ms, 400ms (clock 은 초)
    ms = run_bench(sess, img_size=32, batch=8, iters=2, warmup=1, clock=lambda: next(ticks))
    assert sess.calls == [(8, 3, 32, 32)] * 3  # warmup 1 + iters 2
    assert ms == pytest.approx([100.0, 50.0])  # 크롭당 ms = 반복 ms / batch


def test_parser_defaults():
    a = build_parser().parse_args(["--onnx", "s2.onnx"])
    assert (a.img_size, a.batch, a.threads, a.iters) == (None, 64, 4, 5)


def _tiny_onnx(path, size=32):
    onnx = pytest.importorskip("onnx")
    from onnx import TensorProto, helper

    x = helper.make_tensor_value_info("image", TensorProto.FLOAT, ["b", 3, size, size])
    y = helper.make_tensor_value_info("featmap", TensorProto.FLOAT, ["b", 3, 1, 1])
    g = helper.make_graph([helper.make_node("GlobalAveragePool", ["image"], ["featmap"])], "tiny", [x], [y])
    m = helper.make_model(g, opset_imports=[helper.make_opsetid("", 17)])
    m.ir_version = 8
    onnx.save(m, str(path))
    return path


def test_bench_synthetic_onnx_reads_input_size(tmp_path, capsys):
    pytest.importorskip("onnxruntime")
    from training.bench_stage2 import main

    p = _tiny_onnx(tmp_path / "tiny.onnx", size=32)
    res = main(["--onnx", str(p), "--batch", "4", "--threads", "1", "--iters", "3"])
    assert set(res) == {"onnx", "img_size", "batch", "threads", "ms_per_crop_p50", "ms_per_crop_p95"}
    assert (res["img_size"], res["batch"], res["threads"]) == (32, 4, 1)
    assert 0 <= res["ms_per_crop_p50"] <= res["ms_per_crop_p95"]
    assert json.loads(capsys.readouterr().out.strip()) == res
