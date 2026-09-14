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

  /// 화면에 나오는 순서대로의 병 세 가지.
  ///
  /// 응애를 맨 뒤에 둔다. 앞의 둘을 보고 "아 이런 게 병이구나" 한 다음 마지막에
  /// "그런데 이건 안 보입니다"가 와야 남는다.
  static const List<Disease> diseases = [
    // ⚠️ 폴더명이 "석고병"이라 처음엔 석고병으로 적었는데, 이 사진의 실제 라벨은
    // **부저병**이다(2026-09-14). 부스에서 틀린 병명을 말하지 않도록 맞춘다.
    Disease(
      photo: 'assets/foul_closeup.jpg',
      name: '부저병',
      detail: '애벌레가 죽어 색이 변하고 녹아내리는 병',
      visibility: '눈으로 찾기 쉬움',
      visibleSteps: 3,
    ),
    Disease(
      photo: 'assets/dwv_closeup.jpg',
      name: '날개불구 바이러스',
      detail: '날개가 쪼그라들어 날지 못하게 되는 병',
      visibility: '자세히 보면 보임',
      visibleSteps: 2,
    ),
    Disease(
      photo: 'assets/varroa_closeup.jpg',
      name: '바로아 응애',
      detail: '벌 몸에 붙어 체액을 빨아먹는 2mm 진드기',
      visibility: '눈으로는 거의 못 찾음',
      visibleSteps: 1,
    ),
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

/// 병 하나의 소개 데이터.
///
/// 레코드 튜플이 아니라 이름 있는 필드로 둔다 — `.$3` 이 무엇인지 호출부에서
/// 알 수 없고, 항목이 하나 늘 때마다 조용히 어긋난다.
class Disease {
  const Disease({
    required this.photo,
    required this.name,
    required this.detail,
    required this.visibility,
    required this.visibleSteps,
  });

  final String photo;
  final String name;
  final String detail;

  /// 사람 눈에 얼마나 띄는지 — 화면 아래 눈금과 문구로 나간다.
  final String visibility;

  /// 1~3. 이 화면이 하려는 말이 여기 다 들어 있다: 3 → 2 → 1 로 내려가고,
  /// 마지막(응애)이 1이라서 "그래서 AI가 필요하다"가 성립한다.
  final int visibleSteps;
}

class _DiseaseCard extends StatelessWidget {
  const _DiseaseCard(this.data);

  final Disease data;

  /// 눈금 색 — 잘 보이는 병은 초록, 안 보이는 응애는 빨강. 관람객이 글을 안
  /// 읽고 색만 훑어도 "아래로 갈수록 어려워진다"가 읽힌다.
  Color get _stepColor => switch (data.visibleSteps) {
    3 => AppColors.tierSafe,
    2 => AppColors.tierWatch,
    _ => AppColors.tierDanger,
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return BoothCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 사진이 **남는 높이를 전부** 가져간다(비율 고정 아님). 원본 비율대로
          // 두면 세로 사진 한 장 때문에 카드 셋의 제목 줄이 32px씩 어긋나고,
          // 4:3 으로 고정하면 짧은 캔버스(1280x720 웹 백업)에서 글이 61px 잘린다
          // — 둘 다 2026-09-14 실측. 글이 필요한 만큼 먼저 자리잡고 사진이
          // 나머지를 채우면 캔버스 높이가 얼마든 정렬도 맞고 잘리지도 않는다.
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
              child: SizedBox(
                width: double.infinity,
                child: Image.asset(data.photo, fit: BoxFit.cover),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  data.name,
                  textAlign: TextAlign.center,
                  style: t.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  data.detail,
                  textAlign: TextAlign.center,
                  style: t.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const Divider(height: 24, color: AppColors.divider),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 5),
                      Container(
                        width: 22,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i < data.visibleSteps
                              ? _stepColor
                              : AppColors.divider,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    Text(
                      data.visibility,
                      style: t.bodyMedium?.copyWith(
                        color: _stepColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
