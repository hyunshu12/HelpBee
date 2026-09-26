"""POST /aggregate — N장 합산 (스펙 v2.2 §3·§8).

같은 벌통의 여러 사진을 **카운트로 합산**(Σk/Σn)해 VDI·CI·tier 를 낸다 — 퍼센트 평균 금지
(저장된 vdi 는 clip 돼 역산 불가). 수식은 `app.services.vdi.aggregate` 단일 소스이며
API(`GET /v1/analyses/aggregate`)는 DB의 (bee_infested, bee_total) 만 모아 여기로 보낸다.

요청: {counts: [{bee_infested, bee_total}] (1~50개), quality_ok: bool=true} + 내부 HMAC bearer
응답: {vdi, vdi_display, vdi_raw, sampling_ci95, bee_total, bee_infested, tier, corrected}
"""

from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, model_validator

from app.routers.analyze import require_internal
from app.services import vdi as vdi_mod
from app.services.orchestrator import _DEFAULT_VDI_YAML
from app.services.vdi import VdiConfig

router = APIRouter()


class BeeCount(BaseModel):
    bee_infested: int = Field(ge=0)
    bee_total: int = Field(ge=0)

    @model_validator(mode="after")
    def _infested_le_total(self) -> "BeeCount":
        if self.bee_infested > self.bee_total:
            raise ValueError("bee_infested must be <= bee_total")
        return self


class AggregateRequest(BaseModel):
    counts: list[BeeCount] = Field(min_length=1, max_length=50)
    quality_ok: bool = True


def get_vdi_config() -> VdiConfig:  # pragma: no cover - 런타임 의존 (테스트는 override)
    """서빙 중인 two-stage 번들의 vdi.yaml — 없으면(yolo-v1 롤백) 저장소 기본 vdi.yaml."""
    from app.deps import get_two_stage_engine

    engine = get_two_stage_engine()
    if engine is not None:
        return engine.vdi_config()
    return vdi_mod.load_vdi_config(_DEFAULT_VDI_YAML)


@router.post("/aggregate")
async def aggregate(
    body: AggregateRequest,
    _claims: dict = Depends(require_internal),
    cfg: VdiConfig = Depends(get_vdi_config),
) -> dict:
    agg = vdi_mod.aggregate(
        [(c.bee_infested, c.bee_total) for c in body.counts], cfg, quality_ok=body.quality_ok
    )
    return {
        "vdi": agg["vdi"],
        "vdi_display": agg["vdi_display"],
        "vdi_raw": agg["raw"],
        "sampling_ci95": list(agg["sampling_ci95"]),
        "bee_total": agg["bee_total"],
        "bee_infested": agg["bee_infested"],
        "tier": agg["tier"],
        "corrected": vdi_mod._usable(cfg),
    }
