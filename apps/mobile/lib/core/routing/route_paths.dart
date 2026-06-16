/// Canonical route path constants. The router (owned by the AuthUI agent)
/// and any `context.go(...)` call must reference these — no string literals.
class RoutePaths {
  const RoutePaths._();

  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String signup = '/signup';

  // ── Bottom-nav tabs (inside the AppShell) ──
  static const String home = '/home';
  static const String history = '/history';
  static const String settings = '/settings';

  /// Profile edit (nested under the settings tab).
  static const String profileEdit = '/settings/profile';

  /// Hive detail (pushed on top of the shell). `:id` is the hive uuid.
  static const String hiveDetail = '/hives/:id';

  /// Builds a concrete hive-detail path (e.g. `/hives/abc-123`).
  static String hiveDetailTo(String id) => '/hives/$id';

  // ── Diagnosis flow (full-screen, pushed over the shell; args via extra) ──
  /// Camera capture (CaptureArgs).
  static const String capture = '/capture';

  /// Photo review before analysis (PhotoArgs).
  static const String review = '/photo-review';

  /// Upload + analyze in progress (PhotoArgs).
  static const String analyzing = '/analyzing';

  /// Diagnosis report (ReportArgs).
  static const String report = '/report';
}
