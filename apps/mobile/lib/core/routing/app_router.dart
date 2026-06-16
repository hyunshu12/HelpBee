import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/auth_flow_state.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/home/presentation/home_placeholder_screen.dart';
import 'route_paths.dart';

/// App-wide router. Declarative tree + a redirect that is fully driven by the
/// [authControllerProvider] flow state.
///
/// Redirect policy (by current [AuthFlowState]):
/// - [AuthFlowSplash]         → `/splash` (boot in progress).
/// - [AuthFlowOnboarding]     → `/onboarding`.
/// - [AuthFlowUnauthenticated]→ allow `/login` and `/signup`; anything else →
///   `/login`.
/// - [AuthFlowAuthenticated]  → if currently on an auth/splash/onboarding route,
///   go `/home`; otherwise stay (return null).
///
/// `refreshListenable` is bridged from the Riverpod provider: a [ValueNotifier]
/// is bumped whenever the auth state changes, so go_router re-evaluates the
/// redirect.
final routerProvider = Provider<GoRouter>((ref) {
  // Bridge: pump the router whenever auth state changes.
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
      GoRoute(
        path: RoutePaths.home,
        builder: (context, state) => const HomePlaceholderScreen(),
      ),
    ],
  );
});
