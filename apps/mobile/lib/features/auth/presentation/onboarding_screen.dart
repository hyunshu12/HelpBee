import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/text/korean_wrap.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';
import 'auth_controller.dart';

/// Three-step onboarding carousel. Each page: a Skip action (top-right), a large
/// honey-tinted illustration placeholder, a title + body, page dots, and a
/// full-width CTA (Next on pages 1–2, Start on page 3).
///
/// Skip or finishing the last page calls
/// `authController.completeOnboarding()`, which flips the flow state to
/// unauthenticated → the router redirects to `/login`.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    // Idempotent: completeOnboarding persists the flag and updates state.
    ref.read(authControllerProvider.notifier).completeOnboarding();
  }

  void _next(int lastIndex) {
    if (_index >= lastIndex) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final pages = <_OnbPage>[
      _OnbPage(title: l10n.onbTitle1, body: l10n.onbBody1, icon: Icons.photo_camera_rounded),
      _OnbPage(title: l10n.onbTitle2, body: l10n.onbBody2, icon: Icons.center_focus_strong_rounded),
      _OnbPage(title: l10n.onbTitle3, body: l10n.onbBody3, icon: Icons.notifications_active_rounded),
    ];
    final int lastIndex = pages.length - 1;
    final bool isLast = _index == lastIndex;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with right-aligned Skip.
            SizedBox(
              height: AppSpacing.touchTarget,
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    l10n.onbSkip,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _OnboardingPageView(page: pages[i]),
              ),
            ),
            // Page indicator dots.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  pages.length,
                  (i) => _Dot(active: i == _index),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                0,
                AppSpacing.screenH,
                AppSpacing.xl,
              ),
              child: PrimaryButton(
                label: isLast ? l10n.onbStart : l10n.onbNext,
                onPressed: () => _next(lastIndex),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnbPage {
  const _OnbPage({required this.title, required this.body, required this.icon});

  final String title;
  final String body;
  final IconData icon;
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({required this.page});

  final _OnbPage page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Large rounded honey-tinted illustration placeholder.
          Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              color: AppColors.honeyLight,
              borderRadius: BorderRadius.circular(24),
            ),
            alignment: Alignment.center,
            child: Icon(page.icon, size: 120, color: AppColors.amberDeep),
          ),
          AppSpacing.gapXl,
          Text(
            keepAll(page.title),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
          AppSpacing.gapSm,
          Text(
            keepAll(page.body),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      width: active ? 22 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? AppColors.honeyPrimary : AppColors.hintBorder,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
    );
  }
}
