import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/risk/recommendations.dart';
import '../../../core/risk/risk_tier.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/text/korean_wrap.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/risk_gauge.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../data/analyses_api.dart';
import '../data/analysis_dto.dart';
import 'analysis_flow_args.dart';

/// 레포트 (Figma 24:12): the diagnosis result. Risk gauge + tier title +
/// analyzed-photo card + recommended actions. Recommendations come from the
/// backend (`analysis.recommendations`, with per-item severity); when absent
/// (e.g. a list-sourced row that omits them) we fall back to client-side,
/// tier-based copy. A `failed` analysis shows a graceful "couldn't finish"
/// state instead of a score.
class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key, required this.args});

  final ReportArgs args;

  Analysis get _a => args.analysis;

  /// Backend recommendations (with severity) when present; otherwise fall back
  /// to client-side tier copy so list-sourced rows (which omit them) still show
  /// guidance. Severity for the fallback is derived from the tier.
  List<RecommendationDto> _recommendations(
    AppLocalizations l10n,
    RiskTier tier,
  ) {
    if (_a.recommendations.isNotEmpty) return _a.recommendations;
    final severity = _severityForTier(tier);
    final copy = recommendationsFor(l10n, tier);
    return [
      for (var i = 0; i < copy.length; i++)
        RecommendationDto(order: i, content: copy[i], severity: severity),
    ];
  }

  void _toHome(BuildContext context) => context.go(RoutePaths.home);

  void _saveToHistory(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // The analysis is already persisted on creation; land on the hive detail
    // (timeline) and confirm. go(home)+push(detail) leaves home underneath.
    context.go(RoutePaths.home);
    context.push(RoutePaths.hiveDetailTo(_a.hiveId));
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.reportSavedSnack)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final success = _a.isSuccess;
    final tier = _a.tier;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _toHome(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.bgLight,
        appBar: AppBar(
          backgroundColor: AppColors.bgLight,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.captureCloseA11y,
            onPressed: () => _toHome(context),
          ),
          title: Text(l10n.reportTitle),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: l10n.reportShareA11y,
              onPressed: () => ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(SnackBar(content: Text(l10n.comingSoon))),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH,
                    AppSpacing.lg,
                    AppSpacing.screenH,
                    AppSpacing.lg,
                  ),
                  children: [
                    if (success && tier == RiskTier.insufficient)
                      _InsufficientCard(l10n: l10n)
                    else if (success && _a.isTwoStage)
                      _VdiCard(l10n: l10n, a: _a, tier: tier)
                    else
                      Center(
                        child: RiskGauge(
                          score: success ? _a.varroaInfectionRisk : null,
                          tier: tier,
                          caption: gaugeCaption(l10n, tier),
                        ),
                      ),
                    AppSpacing.gapLg,
                    Text(
                      !success
                          ? l10n.analyzingFailedTitle
                          : tier == RiskTier.insufficient
                          ? l10n.reportInsufficientTitle
                          : l10n.reportRiskStageTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    AppSpacing.gapLg,
                    _PhotoCard(
                      imagePath: args.imagePath,
                      hiveName: args.hiveName,
                      whenLabel: _whenLabel(l10n, _a),
                    ),
                    AppSpacing.gapMd,
                    if (success &&
                        args.imagePath != null &&
                        _a.evidence.isNotEmpty) ...[
                      _EvidenceGallery(
                        l10n: l10n,
                        imagePath: args.imagePath!,
                        evidence: _a.evidence,
                      ),
                      AppSpacing.gapMd,
                    ],
                    if (success && tier != RiskTier.unknown)
                      _RecommendationsCard(items: _recommendations(l10n, tier))
                    else
                      // 실패 상태: 사유 안내 + "다시 시도"(같은 이미지 재분석).
                      _RetrySection(args: args),
                  ],
                ),
              ),
              _BottomBar(
                onHome: () => _toHome(context),
                onSave: () => _saveToHistory(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.imagePath,
    required this.hiveName,
    required this.whenLabel,
  });

  final String? imagePath;
  final String hiveName;
  final String whenLabel;

  void _openViewer(BuildContext context) {
    if (imagePath == null) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                child: Semantics(
                  image: true,
                  label: l10n.reportAnalyzedPhoto,
                  child: Image.file(File(imagePath!), fit: BoxFit.contain),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: l10n.captureCloseA11y,
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return _Card(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppRadius.inputRadius,
            child: SizedBox(
              width: 56,
              height: 56,
              child: imagePath != null
                  ? Semantics(
                      image: true,
                      label: l10n.reportAnalyzedPhoto,
                      child: Image.file(File(imagePath!), fit: BoxFit.cover),
                    )
                  : Container(
                      color: AppColors.honeyLight.withValues(alpha: 0.4),
                      child: const Icon(
                        Icons.image_outlined,
                        color: AppColors.amberDeep,
                      ),
                    ),
            ),
          ),
          AppSpacing.wGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.reportAnalyzedPhoto,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$whenLabel\n$hiveName',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (imagePath != null)
            IconButton(
              icon: const Icon(Icons.zoom_in, color: AppColors.textSecondary),
              tooltip: l10n.reportAnalyzedPhoto,
              onPressed: () => _openViewer(context),
            ),
        ],
      ),
    );
  }
}

/// Severity ('info'|'warn'|'danger') → tier color token. Unknown → safe.
Color _severityColor(String severity) => switch (severity) {
  'danger' => AppColors.tierDanger,
  'warn' => AppColors.tierWatch,
  _ => AppColors.tierSafe,
};

/// Fallback severity when copy is client-side tier-based (no backend severity).
String _severityForTier(RiskTier tier) => switch (tier) {
  RiskTier.danger => 'danger',
  RiskTier.watch => 'warn',
  _ => 'info',
};

class _RecommendationsCard extends StatelessWidget {
  const _RecommendationsCard({required this.items});

  final List<RecommendationDto> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.tierDanger,
                size: 22,
              ),
              AppSpacing.wGapXs,
              Text(
                l10n.reportRecommendTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          AppSpacing.gapMd,
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _severityColor(
                        items[i].severity,
                      ).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: _severityColor(items[i].severity),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AppSpacing.wGapSm,
                  Expanded(
                    child: Text(
                      items[i].content,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppColors.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          Text(
            keepAll(l10n.reportRecommendDisclaimer),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.hintBorder,
            ),
          ),
        ],
      ),
    );
  }
}

class _FailedNoticeCard extends StatelessWidget {
  const _FailedNoticeCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Card(
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.tierWatch),
          AppSpacing.wGapSm,
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Failed-state block: the graceful "couldn't finish" notice + a 다시 시도
/// button. Retry re-POSTs `/v1/analyses` with the SAME (hiveId, imageId); the
/// backend re-runs inference and updates the failed row in place (same id),
/// then we replace this screen with the refreshed report. A retry that fails
/// again just lands on another failed report (this same UI). Errors before the
/// result (network/quota) surface as a snackbar, keeping the report on screen.
class _RetrySection extends ConsumerStatefulWidget {
  const _RetrySection({required this.args});

  final ReportArgs args;

  @override
  ConsumerState<_RetrySection> createState() => _RetrySectionState();
}

class _RetrySectionState extends ConsumerState<_RetrySection> {
  bool _loading = false;

  Analysis get _a => widget.args.analysis;

  Future<void> _retry() async {
    if (_loading) return;
    setState(() => _loading = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(analysesApiProvider)
          .create(hiveId: _a.hiveId, imageId: _a.imageId);
      // The retried row replaced the failed one in place; refresh the caches
      // so the home card + detail timeline + 진단 이력 탭 reflect the new result.
      ref.invalidate(latestAnalysisProvider(_a.hiveId));
      ref.invalidate(hiveAnalysesProvider(_a.hiveId));
      ref.invalidate(allAnalysesProvider);
      if (!mounted) return;
      context.pushReplacement(
        RoutePaths.report,
        extra: ReportArgs(
          analysis: result,
          hiveName: widget.args.hiveName,
          imagePath: widget.args.imagePath,
        ),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(appErrorMessage(l10n, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        _FailedNoticeCard(message: l10n.errAiUnavailable),
        AppSpacing.gapMd,
        PrimaryButton(
          label: l10n.commonRetry,
          onPressed: _loading ? null : _retry,
          loading: _loading,
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onHome, required this.onSave});

  final VoidCallback onHome;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.sm,
        AppSpacing.screenH,
        AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bgLight,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SecondaryButton(label: l10n.reportHome, onPressed: onHome),
          ),
          AppSpacing.wGapMd,
          Expanded(
            flex: 2,
            child: PrimaryButton(
              label: l10n.reportSaveToHistory,
              onPressed: onSave,
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.divider),
      ),
      child: child,
    );
  }
}

/// "오늘 오전 10:45" style label from the analysis time (UTC → local).
String _whenLabel(AppLocalizations l10n, Analysis a) {
  final t = (a.analyzedAt ?? a.createdAt).toLocal();
  final now = DateTime.now();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(t.year, t.month, t.day)).inDays;
  final String day = days <= 0
      ? l10n.today
      : (days == 1 ? l10n.yesterday : l10n.daysAgo(days));
  final bool am = t.hour < 12;
  final int h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final String mm = t.minute.toString().padLeft(2, '0');
  return '$day ${am ? l10n.am : l10n.pm} $h12:$mm';
}

/// v0.2.0 two-stage: VDI(가시 감염 지수) 표시 카드. `vdiDisplay`는 서버가 한 번
/// 반올림한 문자열이라 그대로 보여준다(재계산·재반올림 금지, spec v2.2 §3).
class _VdiCard extends StatelessWidget {
  const _VdiCard({required this.l10n, required this.a, required this.tier});

  final AppLocalizations l10n;
  final Analysis a;
  final RiskTier tier;

  String _ci(double v) => v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = riskTierColor(tier);
    final display = a.vdiDisplay ?? '-';
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            l10n.reportVdiTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          AppSpacing.gapSm,
          Text(
            '$display%',
            key: const Key('vdi-display'),
            style: theme.textTheme.displayMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (a.vdiCiLow != null && a.vdiCiHigh != null)
            Text(
              l10n.reportVdiCi(_ci(a.vdiCiLow!), _ci(a.vdiCiHigh!)),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          AppSpacing.gapSm,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              riskTierBadge(l10n, tier),
              style: theme.textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (a.beeTotal != null) ...[
            AppSpacing.gapSm,
            Text(
              l10n.reportBeeCounts(a.beeInfested ?? 0, a.beeTotal!),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
          if (a.corrected == false)
            Text(
              l10n.reportVdiUncorrected,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

/// 판독 불가(벌 0마리·품질 불량): 게이지 없이 재촬영 안내만.
class _InsufficientCard extends StatelessWidget {
  const _InsufficientCard({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Card(
      child: Column(
        children: [
          const Icon(
            Icons.photo_camera_back_outlined,
            size: 56,
            color: AppColors.tierUnknown,
          ),
          AppSpacing.gapSm,
          Text(
            l10n.reportInsufficientBody,
            key: const Key('insufficient-body'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 감염 의심 벌 크롭 갤러리 — 서버 `evidence[].cropRegion`(원본 픽셀)을 로컬
/// 원본 사진에서 잘라 그린다(크롭 URL은 없음). 최대 6장.
class _EvidenceGallery extends StatefulWidget {
  const _EvidenceGallery({
    required this.l10n,
    required this.imagePath,
    required this.evidence,
  });

  final AppLocalizations l10n;
  final String imagePath;
  final List<Evidence> evidence;

  @override
  State<_EvidenceGallery> createState() => _EvidenceGalleryState();
}

class _EvidenceGalleryState extends State<_EvidenceGallery> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final img = await decodeImageFromList(bytes);
      if (mounted) setState(() => _image = img);
    } catch (_) {
      // 로컬 사진을 못 읽으면 갤러리를 숨긴다.
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final items = widget.evidence.take(6).toList(growable: false);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.l10n.reportEvidenceTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          AppSpacing.gapSm,
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: CustomPaint(
                    painter: _CropPainter(img, items[i].cropRegion),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.region);

  final ui.Image image;
  final List<double> region; // x1,y1,x2,y2 in original pixels

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTRB(
      region[0].clamp(0, image.width.toDouble()),
      region[1].clamp(0, image.height.toDouble()),
      region[2].clamp(0, image.width.toDouble()),
      region[3].clamp(0, image.height.toDouble()),
    );
    if (src.isEmpty) return;
    canvas.drawImageRect(image, src, Offset.zero & size, Paint());
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image || old.region != region;
}
