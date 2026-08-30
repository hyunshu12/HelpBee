import 'package:flutter/material.dart';

import '../data/booth_case.dart';
import '../data/risk_tier.dart';
import '../theme/app_colors.dart';
import '../widgets/bbox_overlay.dart';
import '../widgets/booth_scaffold.dart';
import '../widgets/risk_gauge.dart';
import '../widgets/surfaces.dart';
import '../widgets/tier_badge.dart';

/// 체험의 결론 화면. 왼쪽은 박스가 그려지는 사진(핵심 연출), 오른쪽은 판정 카드들.
///
/// ⚠️ 티어 문구('위험')는 화면에 **한 번만** 나와야 한다 — 게이지 캡션과 [TierBadge]
/// 를 동시에 쓰면 같은 단어가 둘이 되어 `report_screen_test` 가 깨지고, 무엇보다
/// 같은 정보가 두 번 나오는 게 디자인상으로도 틀렸다. 여기서는 배지만 쓴다.
class ReportScreen extends StatefulWidget {
  const ReportScreen({
    super.key,
    required this.case_,
    required this.guess,
    required this.onRestart,
    this.onHistory,
    this.onFinish,
  });

  final BoothCase case_;

  /// 관람객의 추측. true=건강함, false=문제 있음, null=건너뜀.
  final bool? guess;
  final VoidCallback onRestart;
  final VoidCallback? onHistory;
  final VoidCallback? onFinish;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  bool _expanded = false;

  /// 관람객의 추측과 AI 판정을 나란히 보여줄 문구. 추측을 건너뛰었으면 null.
  ///
  /// `mine` 을 반드시 화면에 렌더해야 한다 — "건너뛰면 대조 줄이 안 나온다" 테스트가
  /// 화면 어디에도 '당신' 이 없으면 무엇을 넘겨도 통과하는 공허한 테스트가 된다.
  ({String mine, String verdict, bool correct})? get _comparison {
    final g = widget.guess;
    if (g == null) return null;
    final correct = g == widget.case_.isHealthy;
    return (
      mine: g ? '건강함' : '문제 있음',
      // 스펙 §3 설계 의도: "정상 사진을 골라 '건강함'을 맞히면 '정확합니다!
      // 이 벌통은 건강합니다'로 기분 좋게 끝낸다" — 이 문구는 정상 벌통을
      // 맞혔을 때 한정이다. 위험/주의 벌통을 '문제 있음'으로 맞혔을 때 그대로
      // 붙이면 "이 벌통은 건강합니다"라는 실제와 반대되는 문장이 나간다.
      verdict: correct
          ? (widget.case_.isHealthy ? '정확합니다! 이 벌통은 건강합니다' : '정확합니다!')
          : '눈으로는 찾기 어렵습니다 — 전문가도 어렵습니다.',
      correct: correct,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.case_;
    final t = Theme.of(context).textTheme;
    final recs = c.recommendations;
    final cmp = _comparison;

    return BoothScaffold(
      eyebrow: '4단계 · 진단 결과',
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 6,
            // stretch — start 면 PhotoFrame 이 사진 크기로 shrink-wrap 해서
            // 컬럼 폭을 못 채운다(guess 화면과 같은 결함).
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: PhotoFrame(
                    aspectRatio: c.imageWidth / c.imageHeight,
                    child: BboxOverlay(
                      photoAsset: 'assets/${c.photo}',
                      imageSize: Size(
                        c.imageWidth.toDouble(),
                        c.imageHeight.toDouble(),
                      ),
                      boxes: c.boxes,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // 관람객은 색 박스가 뭘 뜻하는지 모른다. 범례가 없으면 이 화면의
                // 핵심 연출(빨강/초록)이 그냥 "알록달록한 네모"로 끝난다.
                const Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    _Legend(color: AppColors.tierDanger, label: '응애 의심'),
                    SizedBox(width: 20),
                    _Legend(color: AppColors.tierSafe, label: '정상 벌'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 처방을 모두 펼치면(위험 티어 5줄) 오른쪽 컬럼이 화면보다
                // 길어질 수 있다. 스크롤 래퍼는 내용이 들어맞을 때는 아무
                // 차이가 없고, 넘칠 때만 구제한다.
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ResultCard(case_: c),
                        if (cmp != null) ...[
                          const SizedBox(height: 16),
                          _ComparisonCard(
                            mine: cmp.mine,
                            verdict: cmp.verdict,
                            correct: cmp.correct,
                          ),
                        ],
                        if (recs.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          BoothCard(
                            padding: const EdgeInsets.all(24),
                            accent: AppColors.honeyPrimary,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.medical_services_outlined,
                                      size: 24,
                                      color: AppColors.amberDeep,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '권장 조치',
                                      style: t.bodyMedium?.copyWith(
                                        color: AppColors.amberDeep,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(recs.first, style: t.titleMedium),
                                if (recs.length > 1 && !_expanded) ...[
                                  const SizedBox(height: 14),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    // 나머지 처방으로 가는 유일한 통로다 —
                                    // 테마의 꿀색 알약 스타일을 그대로 쓴다.
                                    child: TextButton(
                                      onPressed: () =>
                                          setState(() => _expanded = true),
                                      child: const Text('처방 더 보기'),
                                    ),
                                  ),
                                ],
                                if (_expanded)
                                  ...recs
                                      .skip(1)
                                      .map(
                                        (r) => Padding(
                                          padding: const EdgeInsets.only(
                                            top: 12,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                margin: const EdgeInsets.only(
                                                  top: 10,
                                                ),
                                                width: 8,
                                                height: 8,
                                                decoration: const BoxDecoration(
                                                  color: AppColors.honeyEdge,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  r,
                                                  style: t.bodyMedium,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 주 버튼은 **QR(마무리)로 가는 길**이다.
                //
                // 2026-08-31: 예전엔 '다른 사진 해보기'가 제일 큰 버튼이었는데,
                // 그러면 관람객이 사진만 계속 돌려보다 QR 을 못 보고 떠난다.
                // 체험의 마지막 목적은 "저희 팀이 누군지 남기는 것"이므로
                // 기본 동선이 그쪽으로 흐르게 하고, 사진 다시 보기는 보조로 둔다.
                Row(
                  children: [
                    if (widget.onHistory != null) ...[
                      TextButton(
                        onPressed: widget.onHistory,
                        child: const Text('기록 보기'),
                      ),
                      const SizedBox(width: 10),
                    ],
                    TextButton(
                      onPressed: widget.onRestart,
                      child: const Text('다른 사진 해보기'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        // onFinish 가 없으면(단위 테스트 등) 주 버튼이 사라져
                        // 화면에서 나갈 길이 없어진다 — 그때는 '다른 사진'이
                        // 주 버튼 자리를 대신한다.
                        onPressed: widget.onFinish ?? widget.onRestart,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 72),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                // 짧게 — '다음 단계로 넘어가기'는 이 폭에서
                                // '다음 단계로 넘어…' 로 잘렸다(2026-08-31 실측).
                                widget.onFinish != null
                                    ? '다음 단계로'
                                    : '다른 사진 해보기',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 26,
                              color: AppColors.textPrimary,
                            ),
                          ],
                        ),
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

/// 게이지 + 티어 배지 + 마리 수. 세로로 쌓지 않고 가로로 붙여 높이를 아낀다 —
/// 오른쪽 컬럼에는 이 아래로 대조 카드와 처방 카드가 더 들어간다.
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.case_});

  final BoothCase case_;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return BoothCard(
      padding: const EdgeInsets.all(22),
      accent: riskTierColor(case_.tier),
      child: Row(
        children: [
          RiskGauge(
            score: case_.riskScore,
            tier: case_.tier,
            size: 190,
            stroke: 18,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TierBadge(tier: case_.tier, scale: 0.9),
                ),
                const SizedBox(height: 14),
                Text(
                  case_.varroaCount == 0
                      ? '감염 의심 개체 없음'
                      : '벌 ${case_.beeTotal}마리 중\n${case_.varroaCount}마리 감염 의심',
                  style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "당신: 건강함" 대조 카드. 맞히면 초록, 틀리면 꿀색 톤 — 틀렸다고 빨강으로
/// 칠하지 않는다. 여기서 관람객을 혼내는 게 아니라 "원래 어렵다"고 말해줘야 한다.
class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.mine,
    required this.verdict,
    required this.correct,
  });

  final String mine;
  final String verdict;
  final bool correct;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tone = correct ? AppColors.tierSafe : AppColors.amberDeep;
    return BoothCard(
      padding: const EdgeInsets.all(22),
      accent: tone,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            correct
                ? Icons.check_circle_outline_rounded
                : Icons.visibility_off_outlined,
            size: 30,
            color: tone,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ⚠️ 이 문자열은 정확히 '당신: {mine}' 이어야 한다 (테스트 계약).
                Text(
                  '당신: $mine',
                  style: t.titleMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(verdict, style: t.titleMedium?.copyWith(color: tone)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 26,
        height: 18,
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 3),
          borderRadius: BorderRadius.circular(5),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        label,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    ],
  );
}
