import 'package:flutter/material.dart';

import '../data/booth_case.dart';
import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';
import '../widgets/booth_scaffold.dart';

/// 사진 10장 중 하나를 고르는 화면.
///
/// ⚠️ 티어·점수를 절대 쓰지 않는다. 관람객이 답을 미리 알면 다음 단계(추측)가
/// 무의미해진다 — `picker_screen_test` 가 '위험/주의/안전/100/90/50' 부재를 단언한다.
/// ⚠️ 카드 외에 `Image` 위젯을 추가하지 말 것 (같은 테스트가 Image 개수를 센다).
class PickerScreen extends StatelessWidget {
  const PickerScreen({super.key, required this.cases, required this.onPick});

  final List<BoothCase> cases;
  final ValueChanged<BoothCase> onPick;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return BoothScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('벌통 사진을 하나 골라보세요', style: t.headlineLarge),
          const SizedBox(height: 4),
          Text(
            '어떤 벌통이 아픈지는 아직 알려드리지 않을게요',
            style: t.bodyLarge?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          // GridView + 고정 childAspectRatio 를 쓰지 않는다 — 캔버스 높이가
          // 가정보다 조금만 짧아도(세이프에어리어 차이, 웹 백업의 브라우저 크롬)
          // 아래 줄이 잘려 아래 카드를 아예 누를 수 없게 된다. Expanded 5x2 는
          // 남은 공간이 얼마든 항상 정확히 채우고, 절대 넘치지 않는다.
          Expanded(
            child: Column(
              children: [
                for (var row = 0; row < 2; row++) ...[
                  if (row > 0) const SizedBox(height: 20),
                  Expanded(
                    child: Row(
                      children: [
                        for (var col = 0; col < 5; col++) ...[
                          if (col > 0) const SizedBox(width: 20),
                          Expanded(child: _slotAt(row * 5 + col)),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 10칸 중 i번 칸. 케이스가 10장보다 적어도(데이터 사고) 빈 칸으로 버틴다.
  Widget _slotAt(int i) => i < cases.length
      ? _PhotoCardButton(
          index: i + 1,
          photo: 'assets/${cases[i].photo}',
          onTap: () => onPick(cases[i]),
        )
      : const SizedBox.shrink();
}

class _PhotoCardButton extends StatelessWidget {
  const _PhotoCardButton({
    required this.index,
    required this.photo,
    required this.onTap,
  });

  final int index;
  final String photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider, width: 2),
        ),
        padding: const EdgeInsets.all(5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(photo, fit: BoxFit.cover),
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.honeyPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      fontFamily: kDisplayFont,
                      fontFamilyFallback: kDisplayFallback,
                      fontSize: 22,
                      height: 1.0,
                      color: AppColors.textPrimary,
                    ),
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
