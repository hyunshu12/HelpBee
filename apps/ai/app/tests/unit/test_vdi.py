import math

from app.services.vdi import (
    VdiConfig,
    aggregate,
    corrected_ci,
    display,
    jeffreys_ci,
    load_vdi_config,
    rogan_gladen,
    tier_from_display,
)

CFG = VdiConfig(tau=0.6, tpr=0.90, fpr=0.01, corrected=True)


def test_display_rounding_boundaries():
    assert display(2.949) == "2.9" and display(2.95) == "3.0" and display(9.95) == "10.0" and display(10.0) == "10.0"


def test_tier_half_open_from_display():
    t = lambda s: tier_from_display(s, CFG, bee_total=300, quality_ok=True)  # noqa: E731
    assert t("2.9") == "low" and t("3.0") == "elevated" and t("9.9") == "elevated" and t("10.0") == "high"
    assert tier_from_display("50.0", CFG, bee_total=0, quality_ok=True) == "insufficient"
    assert tier_from_display("50.0", CFG, bee_total=10, quality_ok=False) == "insufficient"


def test_rogan_gladen_guard():
    bad = VdiConfig(tau=0.5, tpr=0.55, fpr=0.10, corrected=False)
    assert rogan_gladen(7.0, bad) == 7.0
    assert math.isclose(rogan_gladen(7.0, CFG), (7 - 1) / (0.90 - 0.01))


def test_healthy_hive_ci_not_collapsed():
    lo, hi = corrected_ci(0, 300, CFG)
    raw_lo, raw_hi = jeffreys_ci(0, 300)
    assert lo == 0.0 and hi >= raw_hi > 0


def test_aggregate_sums_counts_not_percentages():
    r = aggregate([(1, 40), (9, 900)], CFG)  # 10/940 = 1.064% raw
    assert math.isclose(r["raw"], 10 / 940 * 100) and r["tier"] == "low" and r["bee_total"] == 940


def test_load_vdi_config_reads_train_stage2_yaml(tmp_path):
    from training.train_stage2 import write_vdi_yaml

    p = write_vdi_yaml(tmp_path / "vdi.yaml", version="v0.2.0", tau=0.62, tpr=0.91, fpr=0.02, platt=(1.7, -0.3))
    cfg = load_vdi_config(p)
    assert cfg == VdiConfig(
        tau=0.62, tpr=0.91, fpr=0.02, corrected=True, elevated=3.0, high=10.0, platt=(1.7, -0.3)
    )
