import 'package:flutter/material.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../theme/app_colors.dart';

/// Risk tier shown to the user. Cross-cutting (home card, detail, result,
/// badge), so it lives in core rather than a single feature.
enum RiskTier { safe, watch, danger, unknown }

/// Tier color from the design tokens.
Color riskTierColor(RiskTier tier) => switch (tier) {
      RiskTier.safe => AppColors.tierSafe,
      RiskTier.watch => AppColors.tierWatch,
      RiskTier.danger => AppColors.tierDanger,
      RiskTier.unknown => AppColors.tierUnknown,
    };

/// Localized "단계" badge label (안전 단계 / 주의 단계 / 위험 단계 / 진단 필요).
String riskTierBadge(AppLocalizations l10n, RiskTier tier) => switch (tier) {
      RiskTier.safe => l10n.badgeSafe,
      RiskTier.watch => l10n.badgeWatch,
      RiskTier.danger => l10n.badgeDanger,
      RiskTier.unknown => l10n.badgeUnknown,
    };

/// Risk-score → tier when only a score is available
/// (<30 safe / <70 watch / else danger). Mirrors backend risk.yaml bands.
RiskTier riskTierFromScore(int? risk) {
  if (risk == null) return RiskTier.unknown;
  return risk < 30 ? RiskTier.safe : (risk < 70 ? RiskTier.watch : RiskTier.danger);
}
