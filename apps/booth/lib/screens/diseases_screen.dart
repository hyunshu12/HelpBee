import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../widgets/booth_scaffold.dart';
import '../widgets/surfaces.dart';

/// "이런 병들을 찾습니다" — 인트로 다음, 투어 시작 전.
///
/// 2026-09-14 아이패드 실측 피드백으로 추가. 인트로가 응애만 설명하는데 1라운드에
/// 석고병이 나와서, 관람객이 처음 보는 병을 아무 맥락 없이 맞닥뜨렸다. 세 병을
/// 미리 한 번 보여주면 1라운드의 "보이는 병"과 2·3라운드의 "안 보이는 응애"가
/// 대비로 읽힌다 — 그 대비가 이 부스가 하려는 말 전부다.
class DiseasesScreen extends StatefulWidget {
  const DiseasesScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  /// (사진, 병명, 설명, 눈에 띄는 정도) — 화면에 나오는 순서.
  ///
  /// 응애를 맨 뒤에 둔다. 앞의 둘을 보고 "아 이런 게 병이구나" 한 다음 마지막에
  /// "그런데 이건 안 보입니다"가 와야 남는다.
  static const List<(String, String, String, String)> diseases = [
    ('assets/chalk_closeup.jpg', '석고병', '애벌레가 하얗게 굳어 미라처럼 됩니다', '눈에 잘 띕니다'),
    ('assets/dwv_closeup.jpg', '날개불구 바이러스', '날개가 쪼그라들어 날지 못합니다', '자세히 보면 보입니다'),
    ('assets/varroa_closeup.jpg', '바로아 응애', '벌 몸에 붙는 2mm 진드기입니다', '거의 안 보입니다'),
  ];

  @override
  State<DiseasesScreen> createState() => _DiseasesScreenState();
}

class _DiseasesScreenState extends State<DiseasesScreen>
    with SingleTickerProviderStateMixin {
  /// 18초 — 카드 3장을 눈으로 훑고 마지막 줄까지 읽는 데 드는 시간. 인트로(25초)
  /// 보다 짧은 건 여기는 읽을 글이 줄당 한 문장뿐이기 때문이다.
  static const Duration autoAdvance = Duration(seconds: 18);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: autoAdvance,
  );

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) widget.onDone();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return BoothScaffold(
      onTap: widget.onDone,
      footer: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                child: LinearProgressIndicator(
                  value: _c.value,
                  minHeight: 8,
                  backgroundColor: AppColors.divider,
                  valueColor: const AlwaysStoppedAnimation(
                    AppColors.honeyPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 24),
            Text(
              '탭하면 바로 넘어갑니다',
              style: t.bodyMedium?.copyWith(color: AppColors.hintBorder),
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HelpBee 가 찾는 병은 이 셋입니다', style: t.headlineLarge),
          const SizedBox(height: 4),
          Text(
            '셋 다 벌통 사진 한 장에서 찾아냅니다',
            style: t.bodyLarge?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < DiseasesScreen.diseases.length; i++) ...[
                  if (i > 0) const SizedBox(width: 24),
                  Expanded(child: _DiseaseCard(DiseasesScreen.diseases[i])),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiseaseCard extends StatelessWidget {
  const _DiseaseCard(this.data);

  final (String, String, String, String) data;

  @override
  Widget build(BuildContext context) {
    final (photo, name, detail, visibility) = data;
    final t = Theme.of(context).textTheme;
    return BoothCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: double.infinity,
                child: Image.asset(photo, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(name, style: t.headlineMedium),
          const SizedBox(height: 6),
          Text(
            detail,
            style: t.bodyLarge?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          HoneyChip(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              visibility,
              style: t.bodyMedium?.copyWith(
                color: AppColors.amberDeep,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
