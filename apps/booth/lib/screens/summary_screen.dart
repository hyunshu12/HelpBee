import 'package:flutter/material.dart';

import '../data/booth_session.dart';
import '../data/case_kind.dart';
import '../data/tour.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../widgets/booth_scaffold.dart';

/// 투어의 결론 화면 (설계 §4.5).
///
/// 이 화면이 이 기획의 핵심이다 — 3라운드가 만든 대비("보이는 건 맞혔고,
/// 안 보이는 건 못 맞혔다")를 한 줄로 정리해 QR 로 넘긴다.
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
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final results = session.results;

    return BoothScaffold(
      footer: Row(
        children: [
          TextButton(onPressed: onMore, child: const Text('더 해보기')),
          const Spacer(),
          FilledButton(
            onPressed: onFinish,
            style: FilledButton.styleFrom(minimumSize: const Size(300, 76)),
            child: const Text('QR 받기 →'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            summaryHeadline(session.correctCount, results.length),
            style: t.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < results.length; i++) ...[
                  if (i > 0) const SizedBox(width: 20),
                  Expanded(child: _RoundTile(result: results[i])),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '눈에 보이는 병은 찾으셨을 겁니다. 응애는 사람 눈으로는 어렵습니다.\n'
            'HelpBee 는 3장 다 찾았습니다.',
            style: t.bodyLarge?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 맞힌 수에 따른 첫 줄.
///
/// 0장이라고 관람객을 탓하지 않는다 — **못 찾는 게 정상**이라는 게 이 부스의
/// 메시지이고, 0장이야말로 그 메시지가 가장 잘 통한 경우다.
@visibleForTesting
String summaryHeadline(int correct, int total) => switch (correct) {
  0 => '한 장도 못 찾으셨죠 — 그게 정상입니다',
  _ when correct == total => '$total장 다 맞히셨습니다. 눈이 좋으시네요',
  _ => '$total장 중 $correct장 맞히셨습니다',
};

/// 라운드가 어떤 성격이었는지 한 단어로. 관람객이 "왜 이건 맞고 저건 틀렸지"를
/// 스스로 잇게 해주는 라벨이다.
@visibleForTesting
String roundCaption(CaseKind kind) => switch (kind) {
  CaseKind.visible => '보이는 병',
  CaseKind.varroa => '안 보이는 병',
  CaseKind.healthy => '함정',
};

class _RoundTile extends StatelessWidget {
  const _RoundTile({required this.result});

  final TourResult result;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final skipped = result.guess == null;
    final mark = skipped ? '—' : (result.correct ? '✓' : '✗');
    final color = skipped
        ? AppColors.hintBorder
        : (result.correct ? AppColors.tierSafe : AppColors.tierDanger);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.photo),
            // 요약에서는 박스를 그리지 않는다 — 결과 화면에서 이미 봤고,
            // 여기서는 "어떤 사진이었는지" 기억을 되살리는 게 전부다.
            child: Image.asset(
              'assets/${result.case_.photo}',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              mark,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                roundCaption(result.case_.kind),
                style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
