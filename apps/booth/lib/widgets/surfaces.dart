import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// 흰 카드 면. 부스 화면이 "PPT 슬라이드"처럼 보이던 가장 큰 이유가 모든
/// 요소가 배경 위에 그냥 얹혀 있었기 때문이다 — 카드로 묶어 층을 만든다.
class BoothCard extends StatelessWidget {
  const BoothCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(28),
    this.dark = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: dark ? AppColors.boothInkSoft : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: dark ? AppColors.boothInkLine : AppColors.divider,
      ),
      // 그림자 없음 — 카드마다 그림자를 깔면 화면이 슬라이드처럼 보인다.
      // 구분은 가는 선 하나로 충분하다.
    ),
    child: child,
  );
}

/// 사진 액자. 얇은 매트 + 가는 테두리. 맨 `Image.asset` 을 그대로 두면
/// 사진이 배경에 붙어 버려 "붙여넣은 이미지"로 보인다.
class PhotoFrame extends StatelessWidget {
  const PhotoFrame({
    super.key,
    required this.child,
    this.matte = 6,
    this.dark = false,
    this.aspectRatio,
  });

  final Widget child;

  /// 사진 둘레의 흰 여백(액자 매트) 두께.
  final double matte;
  final bool dark;

  /// 지정하면 액자가 사진 비율에 딱 맞게 줄어든다.
  ///
  /// BoxFit.contain 으로 사진을 넣을 때 이걸 안 주면 액자만 부모 크기로
  /// 늘어나고 사진은 가운데 정렬돼, 위아래(또는 좌우)에 커다란 흰 띠가 남는다
  /// (2026-08-31 웹 실측 — 결과 화면 사진 위아래로 110px씩). 액자를 사진에
  /// 맞춰야 여백 없이 붙는다.
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final framed = _frame();
    if (aspectRatio == null) return framed;
    return Center(
      child: AspectRatio(aspectRatio: aspectRatio!, child: framed),
    );
  }

  Widget _frame() => Container(
    padding: EdgeInsets.all(matte),
    decoration: BoxDecoration(
      color: dark ? AppColors.boothInkSoft : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: dark ? AppColors.boothInkLine : AppColors.divider,
      ),
    ),
    child: ClipRRect(borderRadius: BorderRadius.circular(6), child: child),
  );
}

/// 옅은 꿀색 알약 칩. 사실 한 줄, 단계 표시 등에 쓴다.
class HoneyChip extends StatelessWidget {
  const HoneyChip({
    super.key,
    required this.child,
    this.dark = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  });

  final Widget child;
  final bool dark;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: dark ? AppColors.boothInkSoft : AppColors.honeySoft,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      border: Border.all(
        color: dark ? AppColors.boothInkLine : AppColors.honeyEdge,
      ),
    ),
    child: child,
  );
}
