import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 위험도 티어. apps/mobile 의 core/risk/risk_tier.dart 를 옮겨 온 것이되,
/// 부스 앱은 한국어 전용이라 l10n 대신 문자열을 직접 쓴다.
enum RiskTier { safe, watch, danger, unknown }

Color riskTierColor(RiskTier tier) => switch (tier) {
  RiskTier.safe => AppColors.tierSafe,
  RiskTier.watch => AppColors.tierWatch,
  RiskTier.danger => AppColors.tierDanger,
  RiskTier.unknown => AppColors.tierUnknown,
};

/// 배지 문구. apps/mobile 의 badgeSafe/Watch/Danger 와 같은 단어를 쓴다.
String riskTierLabel(RiskTier tier) => switch (tier) {
  RiskTier.safe => '안전',
  RiskTier.watch => '주의',
  RiskTier.danger => '위험',
  RiskTier.unknown => '진단 필요',
};

/// cases.json 의 tier 문자열 → enum. 모르는 값은 unknown.
RiskTier riskTierFromName(String? name) => switch (name) {
  'safe' => RiskTier.safe,
  'watch' => RiskTier.watch,
  'danger' => RiskTier.danger,
  _ => RiskTier.unknown,
};
