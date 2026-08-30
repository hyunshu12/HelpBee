import 'dart:async';

import 'package:flutter/material.dart';

import '../data/booth_case.dart';

/// 실제 추론은 없다. 곧바로 결과를 띄우면 관람객이 "분석한 게 맞나?" 하므로
/// 1.5초 동안 파이프라인 단계를 보여준다. 문구는 실제 동작 순서를 그대로 쓴다.
class AnalyzingScreen extends StatefulWidget {
  const AnalyzingScreen({super.key, required this.case_, required this.onDone});

  final BoothCase case_;
  final VoidCallback onDone;

  @override
  State<AnalyzingScreen> createState() => _AnalyzingScreenState();
}

class _AnalyzingScreenState extends State<AnalyzingScreen> {
  /// 파이프라인 단계 문구. `{beeTotal}` 은 build 시 실제 마리 수로 치환된다.
  /// 타이머의 완료 임계값(initState)이 이 목록의 길이를 그대로 참조하므로,
  /// 단계를 추가/삭제해도 리터럴 상수를 따로 맞출 필요가 없다.
  static const _stepTemplates = ['사진을 읽는 중', '{beeTotal}마리 탐지', '감염 개체 판별 중'];

  Timer? _timer;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted) return;
      setState(() => _step = t.tick);
      if (t.tick >= _stepTemplates.length) {
        t.cancel();
        widget.onDone();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      for (final template in _stepTemplates)
        template.replaceAll('{beeTotal}', '벌 ${widget.case_.beeTotal}'),
    ];
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 32),
          Text(
            steps[_step.clamp(0, steps.length - 1)],
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ],
      ),
    );
  }
}
