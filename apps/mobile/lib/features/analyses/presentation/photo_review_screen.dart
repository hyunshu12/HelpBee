import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';
import 'analysis_flow_args.dart';

/// 카메라검토 (Figma 49:571): shows the captured photo and asks the user to
/// confirm framing before spending an analysis. "이 사진으로 분석하기" starts the
/// pipeline; "다시 찍기" returns to the camera.
class PhotoReviewScreen extends StatelessWidget {
  const PhotoReviewScreen({super.key, required this.args});

  final PhotoArgs args;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(args.imagePath), fit: BoxFit.cover),
          // Bottom scrim for text/buttons legibility over the photo.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 360,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                iconSize: 28,
                color: Colors.white,
                tooltip: l10n.captureCloseA11y,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  0,
                  AppSpacing.screenH,
                  AppSpacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.reviewTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    AppSpacing.gapSm,
                    Text(
                      l10n.reviewBody,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    AppSpacing.gapLg,
                    PrimaryButton(
                      label: l10n.reviewAnalyzeCta,
                      icon: Icons.cloud_done_outlined,
                      onPressed: () => context.pushReplacement(
                        RoutePaths.analyzing,
                        extra: args,
                      ),
                    ),
                    AppSpacing.gapSm,
                    SecondaryButton(
                      label: l10n.reviewRetake,
                      icon: Icons.refresh,
                      foreground: Colors.white,
                      onPressed: () => context.pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
