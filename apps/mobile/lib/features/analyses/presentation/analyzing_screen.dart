import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/text/korean_wrap.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../data/analysis_dto.dart';
import 'analysis_flow_args.dart';
import 'analysis_run_controller.dart';

/// 분석중 (Figma 19:315): drives the upload→analyze pipeline
/// ([runAnalysisProvider]) and shows the bee/ring animation. On completion it
/// replaces itself with the report (a `failed` analysis is a normal result, not
/// an error); pipeline exceptions render an inline retry/cancel state.
class AnalyzingScreen extends ConsumerStatefulWidget {
  const AnalyzingScreen({super.key, required this.args});

  final PhotoArgs args;

  @override
  ConsumerState<AnalyzingScreen> createState() => _AnalyzingScreenState();
}

class _AnalyzingScreenState extends ConsumerState<AnalyzingScreen> {
  bool _navigated = false;

  AnalysisRequest get _req =>
      (hiveId: widget.args.hiveId, imagePath: widget.args.imagePath);

  void _toReport(Analysis analysis) {
    if (_navigated || !mounted) return;
    _navigated = true;
    context.pushReplacement(
      RoutePaths.report,
      extra: ReportArgs(
        analysis: analysis,
        hiveName: widget.args.hiveName,
        imagePath: widget.args.imagePath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    ref.listen<AsyncValue<Analysis>>(runAnalysisProvider(_req), (_, next) {
      next.whenOrNull(data: _toReport);
    });

    final state = ref.watch(runAnalysisProvider(_req));

    return PopScope(
      // Block back only while the (non-cancellable) inference call is in
      // flight; once it errors, let the user back out normally.
      canPop: state.hasError,
      child: Scaffold(
        backgroundColor: AppColors.bgLight,
        body: SafeArea(
          child: Center(
            child: state.hasError
                ? _ErrorView(
                    message: appErrorMessage(l10n, state.error!),
                    onRetry: () => ref.invalidate(runAnalysisProvider(_req)),
                    onClose: () => context.pop(),
                  )
                : const _AnalyzingView(),
          ),
        ),
      ),
    );
  }
}

class _AnalyzingView extends StatelessWidget {
  const _AnalyzingView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  strokeWidth: 6,
                  color: AppColors.honeyBrand,
                ),
              ),
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: AppColors.honeyLight.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text('🐝', style: TextStyle(fontSize: 38)),
              ),
            ],
          ),
        ),
        AppSpacing.gapXl,
        Text(
          l10n.analyzingTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        AppSpacing.gapSm,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Text(
            keepAll(l10n.analyzingBody),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 56, color: AppColors.tierWatch),
          AppSpacing.gapMd,
          Text(
            l10n.analyzingFailedTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          AppSpacing.gapXs,
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          AppSpacing.gapXl,
          PrimaryButton(label: l10n.commonRetry, onPressed: onRetry),
          AppSpacing.gapSm,
          SecondaryButton(label: l10n.commonCancel, onPressed: onClose),
        ],
      ),
    );
  }
}
