import 'package:flutter/material.dart';

import '../data/booth_session.dart';
import '../widgets/trend_chart.dart';

/// 결과 화면의 [기록 보기]에서 들어오는 곁가지 화면. 부스 체험자는 실제로 벌통을
/// 갖고 있지 않으니 "최근 4주" 라는 말 자체가 낯설다 — 이 화면의 목적은 정확한
/// 개인 기록을 보여주는 게 아니라, "이 제품은 한 번 쓰고 마는 게 아니라 반복해서
/// 쓰는 것"이라는 인상을 주는 데 있다. 그래서 미리 심어둔 예시 4점
/// ([BoothSession.seedScores]) 뒤에 이번 체험 결과를 이어 붙여 보여준다.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.session, required this.onBack});

  final BoothSession session;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('나의 위험도 추이', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 12),
          Text(
            '최근 4주 예시 기록에 이번 진단 결과를 더했어요',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 32),
          Expanded(
            child: TrendChart(
              scores: session.chartScores,
              seedCount: BoothSession.seedScores.length,
            ),
          ),
          const SizedBox(height: 32),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: onBack,
              style: FilledButton.styleFrom(minimumSize: const Size(220, 72)),
              child: const Text('돌아가기', style: TextStyle(fontSize: 26)),
            ),
          ),
        ],
      ),
    );
  }
}
