import 'package:flutter/material.dart';

import '../data/risk_tier.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// 티어 배지 — 옅은 티어색 알약 + 점 + 굵은 티어색 글자.
///
/// 결과 화면에서 "위험/주의/안전"은 96pt 숫자보다 실제로 더 중요한 정보다
/// (관람객은 숫자의 의미를 모른다). 평범한 텍스트 대신 배지로 만들어 눈에
/// 먼저 걸리게 한다.
class TierBadge extends StatelessWidget {
  const TierBadge({super.key, required this.tier, this.scale = 1.0});

  final RiskTier tier;

  /// 1.0 = 결과 화면 기준(글자 30). 어트랙트처럼 더 크게 쓸 때 올린다.
  final double scale;

  static Color softFor(RiskTier tier) => switch (tier) {
    RiskTier.safe => AppColors.tierSafeSoft,
    RiskTier.watch => AppColors.tierWatchSoft,
    RiskTier.danger => AppColors.tierDangerSoft,
    RiskTier.unknown => AppColors.tierUnknownSoft,
  };

  @override
  Widget build(BuildContext context) {
    final color = riskTierColor(tier);
    final dot = 14.0 * scale;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 22 * scale,
        vertical: 12 * scale,
      ),
      decoration: BoxDecoration(
        color: softFor(tier),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: 10 * scale),
          Text(
            riskTierLabel(tier),
            style: TextStyle(
              fontSize: 30 * scale,
              height: 1.0,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
