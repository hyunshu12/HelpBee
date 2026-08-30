import 'package:flutter/material.dart';

import '../data/booth_case.dart';

/// 관람객이 눈으로 먼저 판단하게 하는 화면. 여기서 박스를 보여주면
/// 정답을 미리 알려주는 셈이라 사진만 그린다.
class GuessScreen extends StatelessWidget {
  const GuessScreen({super.key, required this.case_, required this.onAnswer});

  final BoothCase case_;

  /// true=건강함 · false=문제 있음 · null=건너뜀
  final ValueChanged<bool?> onAnswer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Text(
            '이 벌통, 건강해 보이나요?',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Image.asset('assets/${case_.photo}', fit: BoxFit.contain),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Big(label: '건강함', onTap: () => onAnswer(true)),
              const SizedBox(width: 24),
              _Big(label: '문제 있음', onTap: () => onAnswer(false)),
              const SizedBox(width: 24),
              TextButton(
                onPressed: () => onAnswer(null),
                // 서서 쓰는 화면이라 보조 버튼도 48dp 이상은 확보한다.
                // 시각적 위계는 유지 — 채우기 버튼이 아니라 텍스트 버튼 그대로.
                style: TextButton.styleFrom(
                  minimumSize: const Size(180, 56),
                  textStyle: const TextStyle(fontSize: 20),
                ),
                child: const Text('바로 결과 보기'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onTap,
    style: FilledButton.styleFrom(
      minimumSize: const Size(220, 72), // 서서 누르는 버튼
    ),
    child: Text(label, style: const TextStyle(fontSize: 26)),
  );
}
