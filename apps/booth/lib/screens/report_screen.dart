import 'package:flutter/material.dart';

import '../data/booth_case.dart';
import '../data/risk_tier.dart';
import '../widgets/bbox_overlay.dart';
import '../widgets/risk_gauge.dart';

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
  ({String mine, String verdict})? get _comparison {
    final g = widget.guess;
    if (g == null) return null;
    final correct = g == widget.case_.isHealthy;
    return (
      mine: g ? '건강함' : '문제 있음',
      verdict: correct ? '정확합니다!' : '눈으로는 찾기 어렵습니다 — 전문가도 어렵습니다.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.case_;
    final recs = c.recommendations;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 6,
            child: BboxOverlay(
              photoAsset: 'assets/${c.photo}',
              imageSize: Size(
                c.imageWidth.toDouble(),
                c.imageHeight.toDouble(),
              ),
              boxes: c.boxes,
            ),
          ),
          const SizedBox(width: 32),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 2026-08-30 fix-round: 실제 부스 화면(1366x1024)에서는 Spacer() 로
                // 충분하다 — 오버플로는 테스트 기본 서피스(800x600)에서만 발생했다.
                // 근거: .superpowers/sdd/2026-08-30_부스체험앱-구현계획/task-4-report.md
                // 의 "Step 4 — 레이아웃 재검증" 절.
                RiskGauge(
                  score: c.riskScore,
                  tier: c.tier,
                  caption: riskTierLabel(c.tier),
                  size: 260,
                  stroke: 22,
                ),
                if (_comparison != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    '당신: ${_comparison!.mine}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _comparison!.verdict,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
                const SizedBox(height: 24),
                if (recs.isNotEmpty)
                  Text(
                    recs.first,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                if (recs.length > 1 && !_expanded)
                  TextButton(
                    onPressed: () => setState(() => _expanded = true),
                    child: const Text('처방 더 보기'),
                  ),
                if (_expanded)
                  ...recs
                      .skip(1)
                      .map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            '· $r',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                const Spacer(),
                Row(
                  children: [
                    if (widget.onHistory != null)
                      TextButton(
                        onPressed: widget.onHistory,
                        child: const Text('기록 보기'),
                      ),
                    const Spacer(),
                    if (widget.onFinish != null)
                      TextButton(
                        onPressed: widget.onFinish,
                        child: const Text('QR 받기'),
                      ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: widget.onRestart,
                      child: const Text('다른 사진 해보기'),
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
