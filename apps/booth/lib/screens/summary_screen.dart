import 'package:flutter/material.dart';

import '../data/booth_session.dart';
import '../widgets/booth_scaffold.dart';

/// Task 6 에서 채운다. 지금은 배선이 돌도록 최소 형태만.
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({
    super.key,
    required this.session,
    required this.onMore,
    required this.onFinish,
  });

  final BoothSession session;
  final VoidCallback onMore;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) => BoothScaffold(
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '3장 중 ${session.correctCount}장 맞히셨습니다',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(onPressed: onMore, child: const Text('더 해보기')),
              const SizedBox(width: 16),
              FilledButton(
                onPressed: onFinish,
                style: FilledButton.styleFrom(minimumSize: const Size(260, 76)),
                child: const Text('QR 받기 →'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
