import 'dart:async';

import 'package:flutter/material.dart';

/// "응애가 뭐죠?" — 관람객 대부분이 모르는 것을 먼저 알려준다.
/// 3초 뒤 자동 진행하되 터치하면 즉시 넘어간다.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  static const Duration autoAdvance = Duration(seconds: 3);

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(autoAdvance, () {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onDone,
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Expanded(
              child: Image.asset(
                'assets/varroa_closeup.jpg',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '꿀벌에 붙은 이 진드기가 벌통을 무너뜨립니다',
              style: Theme.of(context).textTheme.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '사람 눈으로는 찾기 어렵습니다',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
