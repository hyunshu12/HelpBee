import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';

/// `1 / 3` — 투어 진행 표시.
///
/// 자간 넓힌 안내 라벨(구 `Eyebrow`)을 대신한다. 관람객에게 필요한 정보는
/// "몇 장 중 몇 번째인가" 하나뿐이라 숫자만 남긴다.
class RoundIndicator extends StatelessWidget {
  const RoundIndicator({super.key, required this.index, required this.total});

  /// 0-based.
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) => Text(
    '${index + 1} / $total',
    style: const TextStyle(
      fontFamily: kBodyFont,
      fontFamilyFallback: kBodyFallback,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: AppColors.hintBorder,
      height: 1.0,
    ),
  );
}
