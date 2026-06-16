import 'package:flutter/material.dart';

import 'package:helpbee/core/risk/risk_tier.dart';
import 'package:helpbee/l10n/app_localizations.dart';

/// Tier pill — 안전 단계 / 주의 단계 / 위험 단계 / 진단 필요. Color + text from
/// the tier (never color-only, for color-blind / sunlight readability).
class RiskBadge extends StatelessWidget {
  const RiskBadge({super.key, required this.tier});

  final RiskTier tier;

  @override
  Widget build(BuildContext context) {
    final color = riskTierColor(tier);
    final label = riskTierBadge(AppLocalizations.of(context), tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
