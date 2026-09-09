import 'dart:async';

import 'package:flutter/material.dart';

import '../data/booth_case.dart';
import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';
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
    this.startDelay = Duration.zero,
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

  /// 박스가 찍히기 전 사진만 보여 주는 시간.
  ///
  /// 결과 화면이 뜨자마자 박스가 나오면 관람객이 원본 사진을 볼 틈이 없다 —
  /// "AI가 무엇을 보고 찾았는지"가 이 앱의 핵심인데 비교 대상이 사라진다.
  final Duration startDelay;

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
    if (!widget.animate) {
      _c.value = 1.0;
      return;
    }
    if (widget.startDelay == Duration.zero) {
      _c.forward();
    } else {
      _delay = Timer(widget.startDelay, () {
        if (mounted) _c.forward();
      });
    }
  }

  Timer? _delay;

  @override
  void didUpdateWidget(BboxOverlay old) {
    super.didUpdateWidget(old);
    if (widget.replay != old.replay && widget.animate) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
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

/// 박스 하나의 테두리가 그려지는 데 걸리는 시간.
///
/// 2026-09-08: 240ms 는 "한 번에 다 뜬" 것처럼 보였다. 검출기가 하나씩
/// 짚는다는 인상을 주려면 그리는 과정이 눈에 보여야 한다.
const Duration _window = Duration(milliseconds: 360);

/// 박스와 박스 사이 간격 — 이 값이 "하나씩" 리듬을 만든다.
const Duration _stagger = Duration(milliseconds: 420);

/// 전체 연출 상한. 박스가 18개인 케이스도 있어서 간격을 그대로 두면 7초를
/// 넘긴다 — 관람객이 기다리다 지치고, 어트랙트 반복 주기(8초)도 넘는다.
const double _maxTotalMs = 4500;

double _rawTotal(int count) =>
    (count <= 1 ? 0 : (count - 1) * _stagger.inMilliseconds).toDouble() +
    _window.inMilliseconds;

/// 상한에 걸렸을 때 실제로 쓰이는 간격.
double _staggerFor(int count) {
  if (count <= 1) return _stagger.inMilliseconds.toDouble();
  if (_rawTotal(count) <= _maxTotalMs) {
    return _stagger.inMilliseconds.toDouble();
  }
  return (_maxTotalMs - _window.inMilliseconds) / (count - 1);
}

/// 박스 [count] 개를 다 찍는 데 걸리는 전체 시간(ms). 상한에 걸리면 잘린다.
@visibleForTesting
double totalMs(int count) {
  final raw = _rawTotal(count);
  return raw > _maxTotalMs ? _maxTotalMs : raw;
}

/// 그리는 순서 — 정상(초록) → 다른 병(주황) → 응애(빨강) 맨 마지막.
///
/// 데이터 순서 그대로 그리면 빨강이 먼저 찍히고 초록이 뒤따라 연출이
/// 김빠진다. 초록으로 벌을 하나씩 훑다가 마지막에 빨강이 탁 찍혀야
/// "찾아냈다"는 인상이 난다. 결과는 같고 **보여주는 순서만** 바꾼다.
@visibleForTesting
List<BoothBox> revealOrder(List<BoothBox> boxes) => [
  ...boxes.where((b) => b.cls != 'varroa' && b.cls != 'disease'),
  ...boxes.where((b) => b.cls == 'disease'),
  ...boxes.where((b) => b.cls == 'varroa'),
];

/// [index] 번째 박스의 진행도(0~1). 아직 차례가 오지 않았으면 0.
///
/// 이 함수가 순차 등장의 전부다 — 페인터는 위젯 테스트로 검증할 수 없어서
/// (박스를 전부 동시에 그려도 통과한다) 타이밍 계산을 순수 함수로 떼어낸다.
/// [count] 는 전체 박스 수 — 상한에 걸린 케이스의 간격 축소를 반영한다.
@visibleForTesting
double boxProgressAt(int index, double elapsedMs, {int count = 1}) {
  final start = index * _staggerFor(count);
  final t = (elapsedMs - start) / _window.inMilliseconds;
  return Curves.easeOut.transform(t.clamp(0.0, 1.0));
}

/// 박스 하나의 그리기 스타일. `cls` 로만 결정된다.
///
/// 위젯 테스트는 색이 뒤바뀌어도 통과하므로(예외만 확인) 이 결정을 순수 함수로
/// 떼어 단위 테스트한다.
@visibleForTesting
class BoxStyle {
  const BoxStyle({
    required this.color,
    required this.strokeWidth,
    required this.alpha,
    this.tag,
  });

  final Color color;
  final double strokeWidth;
  final double alpha;

  /// 박스 좌상단에 붙는 라벨. null 이면 태그를 그리지 않는다.
  final String? tag;
}

/// 실제 검출기 출력처럼 **직각·얇은 선**.
///
/// 2026-09-08: 둥근 모서리(반경 8)에 굵은 선(6)은 일러스트 스티커처럼 보였다.
/// 진짜 검출기는 직각에 가는 선으로 그린다.
///
/// 정상 벌에는 태그를 달지 않는다 — 6~18개에 전부 '정상' 이 붙으면 화면이
/// 글자로 덮인다. 색만으로 충분하다.
@visibleForTesting
BoxStyle boxStyleFor(String cls) => switch (cls) {
  'varroa' => const BoxStyle(
    color: AppColors.tierDanger,
    strokeWidth: 3,
    alpha: 1.0,
    tag: '응애',
  ),
  'disease' => const BoxStyle(
    color: AppColors.boxDisease,
    strokeWidth: 3,
    alpha: 1.0,
    tag: '질병',
  ),
  _ => const BoxStyle(color: AppColors.tierSafe, strokeWidth: 2, alpha: 0.7),
};

/// 박스 라벨 태그의 글자 스타일.
///
/// ⚠️ `fontFamily` 를 반드시 명시해야 한다 — `TextPainter` 는 위젯 트리 밖이라
/// 테마의 서체를 물려받지 못하고, 웹에서 한글이 두부(□)로 그려진다.
@visibleForTesting
const TextStyle boxTagStyle = TextStyle(
  fontFamily: kBodyFont,
  fontFamilyFallback: kBodyFallback,
  fontSize: 15,
  fontWeight: FontWeight.w700,
  height: 1.0,
  color: AppColors.surface,
);

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
      final progress = boxProgressAt(i, elapsedMs, count: ordered.length);
      if (progress <= 0) continue; // 아직 차례가 아니다
      final style = boxStyleFor(b.cls);
      final r = fit.toScreen(Rect.fromLTWH(b.x, b.y, b.w, b.h));

      // 테두리가 좌상단에서 시계방향으로 그려진다 — 검출기가 찾아서 표시하는
      // 동작 그대로. 페이드·축소는 "그림이 밝아진" 느낌이라 쓰지 않는다.
      _drawPartialRect(canvas, r, progress, style);

      // 태그는 테두리가 다 그려진 뒤 붙는다.
      if (progress >= 1.0 && style.tag != null) {
        _drawTag(canvas, r, style);
      }
    }
  }

  /// 사각형 둘레를 [progress] 만큼만 그린다 (좌상단 → 시계방향).
  void _drawPartialRect(
    Canvas canvas,
    Rect r,
    double progress,
    BoxStyle style,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.strokeWidth
      ..color = style.color.withValues(alpha: style.alpha);

    final path = Path()
      ..moveTo(r.left, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..close();

    if (progress >= 1.0) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  /// 박스 좌상단 바깥에 채운 라벨. 위쪽 공간이 없으면 안쪽으로 넣는다.
  void _drawTag(Canvas canvas, Rect r, BoxStyle style) {
    // 박스가 너무 좁으면 태그가 박스보다 넓어져 지저분해진다 (석고병은
    // 박스가 소방 1칸 크기다) — 생략한다.
    if (r.width < 60) return;

    final tp = TextPainter(
      text: TextSpan(text: style.tag, style: boxTagStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    const padH = 7.0;
    const padV = 4.0;
    final tagW = tp.width + padH * 2;
    final tagH = tp.height + padV * 2;
    final above = r.top - tagH >= 0;
    final origin = Offset(r.left, above ? r.top - tagH : r.top);

    canvas.drawRect(
      Rect.fromLTWH(origin.dx, origin.dy, tagW, tagH),
      Paint()..color = style.color.withValues(alpha: style.alpha),
    );
    tp.paint(canvas, origin + const Offset(padH, padV));
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.elapsedMs != elapsedMs || old.boxes != boxes;
}
