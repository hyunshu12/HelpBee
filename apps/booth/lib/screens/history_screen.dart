import 'package:flutter/material.dart';

import '../data/booth_session.dart';
import '../theme/app_colors.dart';
import '../widgets/booth_scaffold.dart';
import '../widgets/surfaces.dart';
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
    final t = Theme.of(context).textTheme;
    return BoothScaffold(
      eyebrow: '곁가지 · 위험도 추이',
      footer: Row(
        children: [
          FilledButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 28),
            label: const Text('돌아가기'),
            style: FilledButton.styleFrom(minimumSize: const Size(240, 72)),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              '실제 앱에서는 벌통마다 진단할 때마다 이렇게 쌓입니다',
              style: t.bodyMedium?.copyWith(color: AppColors.hintBorder),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('나의 위험도 추이', style: t.headlineLarge),
          const SizedBox(height: 4),
          Text(
            '최근 4주 예시 기록에 이번 진단 결과를 더했어요',
            style: t.bodyLarge?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: BoothCard(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
              child: TrendChart(
                scores: session.chartScores,
                seedCount: BoothSession.seedScores.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
