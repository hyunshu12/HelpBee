import 'dart:async';

import 'package:flutter/material.dart';

/// 마무리 화면. 동아리 홈페이지 QR 을 크게 띄우고 15초 뒤 세션을 초기화한다.
/// 관람객이 폰을 꺼내 찍을 시간을 주되, 다음 사람을 오래 기다리게 하지 않는 길이다.
class OutroScreen extends StatefulWidget {
  const OutroScreen({super.key, required this.onRestart});

  final VoidCallback onRestart;

  @override
  State<OutroScreen> createState() => _OutroScreenState();
}

class _OutroScreenState extends State<OutroScreen> {
  static const Duration autoReset = Duration(seconds: 15);

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(autoReset, () {
      if (mounted) widget.onRestart();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      // Column은 가로축을 부모 폭이 아니라 가장 넓은 자식에 맞춰 shrink-wrap한다
      // (Expanded로 폭을 채우는 자식이 없으면). 여기 자식들은 전부 고정 크기라
      // Center 없이는 화면 왼쪽에 쏠려 붙는다 — 2026-08-30 스크린샷 실측(중심이
      // 화면 중앙 1366이 아니라 502에 위치)으로 발견.
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '체험해 주셔서 감사합니다',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 320,
              height: 320,
              child: Image.asset('assets/qr_mrmr.png', fit: BoxFit.contain),
            ),
            const SizedBox(height: 20),
            Text(
              'QR 을 찍으면 저희 팀 홈페이지로 갑니다',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 40),
            FilledButton(
              onPressed: widget.onRestart,
              style: FilledButton.styleFrom(minimumSize: const Size(280, 72)),
              child: const Text('처음으로', style: TextStyle(fontSize: 26)),
            ),
          ],
        ),
      ),
    );
  }
}
