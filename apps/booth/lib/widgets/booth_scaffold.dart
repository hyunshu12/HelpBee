import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'brand.dart';

/// 모든 부스 화면의 공통 틀. 화면마다 `Padding(Column(...))` 을 새로 짜면
/// 여백·정렬·브랜딩이 제각각이 되고, 그 불일치가 "슬라이드 같다"는 인상의
/// 절반을 만든다. 여기 한 곳에서 여백·헤더·배경을 정한다.
///
/// [dark] 는 어트랙트/마무리처럼 **시선을 끌어야 하는** 화면용이다. 밝은 크림
/// 화면들 사이에 검정 화면이 끼면 부스 앞을 지나는 사람 눈에 확실히 걸린다.
class BoothScaffold extends StatelessWidget {
  const BoothScaffold({
    super.key,
    required this.child,
    this.dark = false,
    this.footer,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(48, 28, 48, 36),
  });

  final Widget child;
  final bool dark;

  /// 본문 아래 고정 영역(버튼 줄 등).
  final Widget? footer;

  /// 화면 전체를 탭 대상으로 만든다 (어트랙트·인트로).
  final VoidCallback? onTap;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [Wordmark(onDark: dark, size: 28)]),
          const SizedBox(height: 20),
          Expanded(child: child),
          if (footer != null) ...[const SizedBox(height: 24), footer!],
        ],
      ),
    );

    final stack = Stack(
      fit: StackFit.expand,
      children: [
        // 그라디언트·패턴 없는 단색. 배경 장식은 화면을 "만들어진 템플릿"처럼
        // 보이게 하고, 부스에서는 사진이 주인공이라 배경이 조용할수록 낫다.
        ColoredBox(color: dark ? AppColors.boothInk : AppColors.boothBg),
        body,
      ],
    );

    final content = onTap == null
        ? stack
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: stack,
          );

    return DefaultTextStyle.merge(
      style: TextStyle(color: dark ? AppColors.onInk : AppColors.textPrimary),
      child: content,
    );
  }
}
