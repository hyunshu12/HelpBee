import '../data/auth_dto.dart';

/// The top-level auth/navigation state the router redirects on.
///
/// - [AuthFlowSplash]          — boot in progress (token check / restore).
/// - [AuthFlowOnboarding]      — first launch, onboarding not yet completed.
/// - [AuthFlowUnauthenticated] — onboarding done, no valid session -> login.
/// - [AuthFlowAuthenticated]   — restored/just-authenticated session -> home.
///
/// Native Dart 3 sealed class (no freezed): exhaustive `switch` in
/// router/widgets is compiler-checked.
sealed class AuthFlowState {
  const AuthFlowState();

  const factory AuthFlowState.splash() = AuthFlowSplash;
  const factory AuthFlowState.onboarding() = AuthFlowOnboarding;
  const factory AuthFlowState.unauthenticated() = AuthFlowUnauthenticated;
  const factory AuthFlowState.authenticated(PublicUser user) =
      AuthFlowAuthenticated;
}

final class AuthFlowSplash extends AuthFlowState {
  const AuthFlowSplash();
}

final class AuthFlowOnboarding extends AuthFlowState {
  const AuthFlowOnboarding();
}

final class AuthFlowUnauthenticated extends AuthFlowState {
  const AuthFlowUnauthenticated();
}

final class AuthFlowAuthenticated extends AuthFlowState {
  const AuthFlowAuthenticated(this.user);

  final PublicUser user;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthFlowAuthenticated && other.user == user;

  @override
  int get hashCode => user.hashCode;
}
