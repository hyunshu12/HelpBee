import 'package:flutter/material.dart';

import '../data/booth_case.dart';
import '../theme/app_colors.dart';
import 'image_fit.dart';

/// 사진 + 탐지 박스. 박스가 **하나씩 순서대로** 탁-탁-탁 찍히며 나타난다
/// ("AI가 개체를 하나하나 짚는" 연출).
///
/// 전부 동시에 페이드인하면 "그림 한 장이 밝아진" 것으로 보여서, 탐지가
/// 일어나고 있다는 인상이 안 난다. 박스마다 [_stagger] 만큼 늦게 시작해
/// [_window] 동안 조여들며 찍히게 한다.
///
/// cls='varroa' 는 굵은 빨강, 그 외는 얇은 초록. 2026-08-30 bbox 포맷 정정 후
/// 박스가 벌 한 마리씩 정확히 잡히므로 정상 벌도 함께 그린다 — 정상 사진에
/// 초록 박스만 뜨는 그림이 "다 건강하다"를 눈에 보이게 한다.
class BboxOverlay extends StatefulWidget {
  const BboxOverlay({
    super.key,
    required this.photoAsset,
    required this.imageSize,
    required this.boxes,
    this.animate = true,
    this.replay = 0,
  });

  final String photoAsset;
  final Size imageSize;
  final List<BoothBox> boxes;
  final bool animate;

  /// 이 값이 바뀔 때마다 박스 등장 애니메이션을 처음부터 다시 돌린다.
  ///
  /// 예전에는 호출부가 `key: ValueKey(replay)` 로 위젯을 통째로 **다시 만들어**
  /// 재생했다. 그러면 State·AnimationController 가 매번 새로 생기고 `Image` 도
  /// 다시 해석된다 — 어트랙트가 4초마다 재생하므로 8시간 부스에서 7,200번이다.
  /// 프로퍼티로 바꾸면 위젯은 그대로 두고 컨트롤러만 되감는다.
  final int replay;

  @override
  State<BboxOverlay> createState() => _BboxOverlayState();
}

class _BboxOverlayState extends State<BboxOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: totalMs(widget.boxes.length).round()),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _c.forward();
    } else {
      _c.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(BboxOverlay old) {
    super.didUpdateWidget(old);
    if (widget.replay != old.replay && widget.animate) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = ImageFit(
          imageSize: widget.imageSize,
          boxSize: Size(constraints.maxWidth, constraints.maxHeight),
        );
        // RepaintBoundary — 이 안의 사진·박스를 별도 레이어로 떼어낸다.
        // 없으면 화면 어딘가(어트랙트의 펄스 칩 등)가 애니메이션할 때마다
        // 사진까지 매 프레임 다시 래스터화된다.
        return RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(widget.photoAsset, fit: BoxFit.contain),
              AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: _BoxPainter(
                    fit: fit,
                    boxes: widget.boxes,
                    elapsedMs: _c.value * totalMs(widget.boxes.length),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 박스 하나가 찍히는 데 걸리는 시간.
const Duration _window = Duration(milliseconds: 240);

/// 박스와 박스 사이 간격 — 이 값이 "탁-탁-탁" 리듬을 만든다.
const Duration _stagger = Duration(milliseconds: 95);

/// 박스 [count] 개를 다 찍는 데 걸리는 전체 시간(ms).
@visibleForTesting
double totalMs(int count) =>
    (count <= 1 ? 0 : (count - 1) * _stagger.inMilliseconds).toDouble() +
    _window.inMilliseconds;

/// 그리는 순서 — 정상(초록) 먼저, 감염 의심(빨강)을 **맨 마지막**에.
///
/// 데이터 순서 그대로 그리면 빨강이 먼저 찍히고 초록이 뒤따라 연출이
/// 김빠진다. 초록으로 벌을 하나씩 훑다가 마지막에 빨강이 탁 찍혀야
/// "찾아냈다"는 인상이 난다. 결과는 같고 **보여주는 순서만** 바꾼다.
@visibleForTesting
List<BoothBox> revealOrder(List<BoothBox> boxes) => [
  ...boxes.where((b) => b.cls != 'varroa'),
  ...boxes.where((b) => b.cls == 'varroa'),
];

/// [index] 번째 박스의 진행도(0~1). 아직 차례가 오지 않았으면 0.
///
/// 이 함수가 순차 등장의 전부다 — 페인터는 위젯 테스트로 검증할 수 없어서
/// (박스를 전부 동시에 그려도 통과한다) 타이밍 계산을 순수 함수로 떼어낸다.
@visibleForTesting
double boxProgressAt(int index, double elapsedMs) {
  final start = index * _stagger.inMilliseconds;
  final t = (elapsedMs - start) / _window.inMilliseconds;
  return Curves.easeOut.transform(t.clamp(0.0, 1.0));
}

/// 박스 하나의 그리기 스타일. `cls` 로만 결정된다.
///
/// 위젯 테스트는 색이 뒤바뀌어도 통과하므로(예외만 확인) 이 결정을 순수 함수로 떼어
/// 단위 테스트한다 — 2026-08-30 리뷰 지적.
@visibleForTesting
class BoxStyle {
  const BoxStyle({
    required this.color,
    required this.strokeWidth,
    required this.alpha,
  });

  final Color color;
  final double strokeWidth;
  final double alpha;
}

/// `'varroa'` 는 굵은 빨강, 그 외(정상 벌·미지의 값)는 얇은 초록.
@visibleForTesting
BoxStyle boxStyleFor(String cls) => cls == 'varroa'
    ? const BoxStyle(color: AppColors.tierDanger, strokeWidth: 6, alpha: 1.0)
    : const BoxStyle(color: AppColors.tierSafe, strokeWidth: 3, alpha: 0.75);

class _BoxPainter extends CustomPainter {
  _BoxPainter({
    required this.fit,
    required this.boxes,
    required this.elapsedMs,
  });

  final ImageFit fit;
  final List<BoothBox> boxes;
  final double elapsedMs;

  @override
  void paint(Canvas canvas, Size size) {
    final ordered = revealOrder(boxes);
    for (var i = 0; i < ordered.length; i++) {
      final b = ordered[i];
      final progress = boxProgressAt(i, elapsedMs);
      if (progress <= 0) continue; // 아직 차례가 아니다
      final style = boxStyleFor(b.cls);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.strokeWidth
        ..color = style.color.withValues(alpha: progress * style.alpha);
      final target = fit.toScreen(Rect.fromLTWH(b.x, b.y, b.w, b.h));
      // 1.12배에서 1.0배로 조여들며 나타난다 — "짚는" 느낌
      final k = 1.0 + 0.12 * (1 - progress);
      final r = Rect.fromCenter(
        center: target.center,
        width: target.width * k,
        height: target.height * k,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(8)),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.elapsedMs != elapsedMs || old.boxes != boxes;
}
