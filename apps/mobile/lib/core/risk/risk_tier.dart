import 'package:flutter/material.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../theme/app_colors.dart';

/// Risk tier shown to the user. Cross-cutting (home card, detail, result,
/// badge), so it lives in core rather than a single feature.
/// `insufficient` (v0.2.0 two-stage): 벌이 없거나 사진 품질이 나빠 판독 불가 —
/// 게이지 없이 재촬영 안내를 보여준다.
enum RiskTier { safe, watch, danger, insufficient, unknown }

/// Tier color from the design tokens.
Color riskTierColor(RiskTier tier) => switch (tier) {
  RiskTier.safe => AppColors.tierSafe,
  RiskTier.watch => AppColors.tierWatch,
  RiskTier.danger => AppColors.tierDanger,
  RiskTier.insufficient => AppColors.tierUnknown,
  RiskTier.unknown => AppColors.tierUnknown,
};

/// Localized "단계" badge label (안전 단계 / 주의 단계 / 위험 단계 / 진단 필요).
String riskTierBadge(AppLocalizations l10n, RiskTier tier) => switch (tier) {
  RiskTier.safe => l10n.badgeSafe,
  RiskTier.watch => l10n.badgeWatch,
  RiskTier.danger => l10n.badgeDanger,
  RiskTier.insufficient => l10n.badgeInsufficient,
  RiskTier.unknown => l10n.badgeUnknown,
};

/// Risk-score → tier when only a score is available
/// (<30 safe / <70 watch / else danger). Mirrors backend risk.yaml bands.
RiskTier riskTierFromScore(int? risk) {
  if (risk == null) return RiskTier.unknown;
  return risk < 30
      ? RiskTier.safe
      : (risk < 70 ? RiskTier.watch : RiskTier.danger);
}

/// Server tier (v0.2.0 `low|elevated|high|insufficient`, legacy
/// `safe|watch|danger`) → [RiskTier]. The server computes tier from
/// `vdi_display` once; the client never recomputes it from `vdi`.
/// Unknown/null → fall back to `overallHealth`, else unknown.
RiskTier riskTierFromServer(String? tier, {String? overallHealth}) {
  switch (tier) {
    case 'low':
    case 'safe':
      return RiskTier.safe;
    case 'elevated':
    case 'watch':
      return RiskTier.watch;
    case 'high':
    case 'danger':
      return RiskTier.danger;
    case 'insufficient':
      return RiskTier.insufficient;
  }
  switch (overallHealth) {
    case 'healthy':
      return RiskTier.safe;
    case 'warning':
      return RiskTier.watch;
    case 'critical':
      return RiskTier.danger;
  }
  return RiskTier.unknown;
}
