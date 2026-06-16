import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/analyses/presentation/analysis_history_screen.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/auth_flow_state.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/hives/presentation/hive_detail_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/settings/presentation/profile_edit_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import 'app_shell.dart';
import 'route_paths.dart';

/// App-wide router. Declarative tree + a redirect driven by the
/// [authControllerProvider] flow state.
///
/// Layout:
/// - Top-level (root navigator): splash / onboarding / login / signup, and the
///   pushed-over-the-shell hive detail (`/hives/:id`).
/// - [StatefulShellRoute] with the three bottom-nav tabs: 벌통(`/home`),
///   진단 이력(`/history`), 설정(`/settings`, with nested `/settings/profile`).
///
/// Redirect policy (by current [AuthFlowState]):
/// - splash → `/splash`; onboarding → `/onboarding`.
/// - unauthenticated → allow `/login` and `/signup`; else `/login`.
/// - authenticated → if on an auth/splash/onboarding route go `/home`; else stay.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen<AuthFlowState>(
    authControllerProvider,
    (_, _) => refresh.value++,
    fireImmediately: false,
  );

  return GoRouter(
    initialLocation: RoutePaths.splash,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      final bool onSplash = location == RoutePaths.splash;
      final bool onOnboarding = location == RoutePaths.onboarding;
      final bool onLogin = location == RoutePaths.login;
      final bool onSignup = location == RoutePaths.signup;
      final bool onAuthGate = onLogin || onSignup;

      return switch (auth) {
        AuthFlowSplash() => onSplash ? null : RoutePaths.splash,
        AuthFlowOnboarding() => onOnboarding ? null : RoutePaths.onboarding,
        AuthFlowUnauthenticated() => onAuthGate ? null : RoutePaths.login,
        AuthFlowAuthenticated() =>
          (onSplash || onOnboarding || onAuthGate) ? RoutePaths.home : null,
      };
    },
    routes: [
      GoRoute(
        path: RoutePaths.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RoutePaths.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: RoutePaths.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RoutePaths.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      // Pushed over the shell (full screen, no bottom nav).
      GoRoute(
        path: RoutePaths.hiveDetail,
        builder: (context, state) =>
            HiveDetailScreen(hiveId: state.pathParameters['id']!),
      ),
      // Bottom-nav shell with three tabs.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.history,
                builder: (context, state) => const AnalysisHistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.settings,
                builder: (context, state) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'profile',
                    builder: (context, state) => const ProfileEditScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
