import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/slide_deck.dart';

/// 발표 슬라이드 화면 (이사장님 발표, 2026-09).
///
/// 슬라이드 그림이 곧 화면이다 — 워드마크·여백·크로스페이드 어느 것도 얹지 않는다.
/// 입력은 세 갈래: 화면 절반 탭, 스와이프, 키보드(블루투스 프레젠터는
/// PageDown/PageUp 또는 방향키를 보낸다).
class PresentationScreen extends StatefulWidget {
  const PresentationScreen({
    super.key,
    required this.deck,
    required this.onDemo,
    required this.onExit,
  });

  final SlideDeck deck;

  /// 시연 장의 "시연 시작 →".
  final VoidCallback onDemo;

  /// 마지막 장에서 한 번 더 넘겼을 때 — 발표 끝.
  final VoidCallback onExit;

  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _PresentationScreenState extends State<PresentationScreen> {
  /// 스와이프로 인정하는 최소 속도. 이보다 느리면 탭하려다 손이 밀린 것.
  static const double _swipeVelocity = 200;

  @override
  void initState() {
    super.initState();
    // 첫 넘김에서 흰 프레임이 번쩍이지 않도록 전 장을 미리 디코드해 둔다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final p in widget.deck.paths) {
        precacheImage(AssetImage(p), context, onError: (_, _) {});
      }
    });
  }

  void _next() {
    if (widget.deck.next()) {
      setState(() {});
    } else {
      widget.onExit();
    }
  }

  void _prev() {
    if (widget.deck.prev()) setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.pageDown ||
        k == LogicalKeyboardKey.space) {
      _next();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.pageUp) {
      _prev();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final deck = widget.deck;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final w = MediaQuery.sizeOf(context).width;
          d.localPosition.dx < w / 2 ? _prev() : _next();
        },
        onHorizontalDragEnd: (d) {
          final vx = d.velocity.pixelsPerSecond.dx;
          if (vx < -_swipeVelocity) _next();
          if (vx > _swipeVelocity) _prev();
        },
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                deck.paths[deck.index],
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                // 에셋이 없으면 검은 화면 + 경로만. 발표 중 빨간 에러보다 낫다.
                errorBuilder: (_, _, _) => Center(
                  child: Text(
                    deck.paths[deck.index],
                    style: const TextStyle(color: Colors.white24, fontSize: 14),
                  ),
                ),
              ),
              // 시연 버튼은 하단 중앙 — 13번 장 오른쪽에 폰 목업이 있어 오른쪽
              // 아래는 겹친다. 16:9 를 4:3 에 맞추면 아래 검은 띠에 놓인다.
              if (deck.isDemo)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Center(
                    child: FilledButton(
                      onPressed: widget.onDemo,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(280, 76),
                      ),
                      child: const Text('시연 시작 →'),
                    ),
                  ),
                ),
              Positioned(
                right: 20,
                bottom: 16,
                // 발표자용. 청중이 못 읽을 만큼만 흐리게.
                child: Text(
                  '${deck.index + 1} / ${deck.paths.length}',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 14,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
