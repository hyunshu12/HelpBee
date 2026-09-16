import 'package:flutter/material.dart';

import '../data/booth_case.dart';
import '../data/tour.dart';
import '../theme/app_colors.dart';
import '../widgets/booth_scaffold.dart';
import '../widgets/round_indicator.dart';
import '../widgets/surfaces.dart';

/// 관람객이 눈으로 먼저 판단하게 하는 화면. 여기서 박스를 보여주면
/// 정답을 미리 알려주는 셈이라 사진만 그린다.
///
/// 두 선택지는 **시각적으로 동등**해야 한다 — '건강함'만 초록으로 칠하는 식의
/// 힌트를 주면 추측이 아니라 유도가 된다.
class GuessScreen extends StatelessWidget {
  const GuessScreen({
    super.key,
    required this.case_,
    this.onAnswer,
    this.onDiseaseAnswer,
    this.roundIndex,
    this.roundTotal = 3,
  }) : assert(
         (onAnswer == null) != (onDiseaseAnswer == null),
         '건강/문제 2택(onAnswer) 또는 병명 택1(onDiseaseAnswer) 중 하나만',
       );

  final BoothCase case_;

  /// 건강/문제 2택 모드. true=건강함 · false=문제 있음 · null=건너뜀
  final ValueChanged<bool?>? onAnswer;

  /// 병명 택1 모드 (1라운드). [kRound1Choices] 의 id · null=건너뜀.
  ///
  /// 2026-09-16: 1라운드는 응애를 뺀 풀(정상·날개불구·부저병)에서 뽑고
  /// 관람객이 셋 중 하나를 고른다. 찍으면 33%.
  final ValueChanged<String?>? onDiseaseAnswer;

  bool get _diseaseMode => onDiseaseAnswer != null;

  /// 투어 라운드 (0-based). 보너스 경로면 null — 표시하지 않는다.
  final int? roundIndex;
  final int roundTotal;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return BoothScaffold(
      footer: Row(
        children: [
          if (_diseaseMode)
            for (final (i, choice) in kRound1Choices.indexed) ...[
              if (i > 0) const SizedBox(width: 20),
              Expanded(
                child: _Choice(
                  label: choice.label,
                  onTap: () => onDiseaseAnswer!(choice.id),
                ),
              ),
            ]
          else ...[
            Expanded(
              child: _Choice(label: '건강함', onTap: () => onAnswer!(true)),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _Choice(label: '문제 있음', onTap: () => onAnswer!(false)),
            ),
          ],
          const SizedBox(width: 20),
          TextButton(
            onPressed: () =>
                _diseaseMode ? onDiseaseAnswer!(null) : onAnswer!(null),
            // 서서 쓰는 화면이라 보조 버튼도 60dp 이상(테마 기본).
            // 시각적 위계는 유지 — 채우기 버튼이 아니라 옅은 꿀색 알약.
            style: TextButton.styleFrom(minimumSize: const Size(230, 76)),
            child: const Text('바로 결과 보기'),
          ),
        ],
      ),
      // stretch 여야 한다 — start 면 Column 이 가로로 shrink-wrap 해서
      // PhotoFrame 이 사진의 contain 크기만큼만 차지하고 오른쪽 절반이 통째로
      // 빈다(2026-08-31 웹 실측). 헤드라인은 stretch 여도 왼쪽 정렬로 그려진다.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  _diseaseMode ? '이 벌통, 어떤 상태일까요?' : '이 벌통, 건강해 보이나요?',
                  style: t.headlineLarge,
                ),
              ),
              if (roundIndex != null)
                RoundIndicator(index: roundIndex!, total: roundTotal),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '정답은 바로 다음 화면에서 알려드려요',
            style: t.bodyLarge?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: PhotoFrame(
              aspectRatio: case_.imageWidth / case_.imageHeight,
              child: Image.asset('assets/${case_.photo}', fit: BoxFit.contain),
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onTap,
    style: FilledButton.styleFrom(minimumSize: const Size(0, 76)),
    child: Text(label, style: const TextStyle(fontSize: 28)),
  );
}
