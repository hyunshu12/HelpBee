/// Canonical route path constants. The router (owned by the AuthUI agent)
/// and any `context.go(...)` call must reference these — no string literals.
class RoutePaths {
  const RoutePaths._();

  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String home = '/home';

  /// Hive detail (pushed on top of /home). `:id` is the hive uuid.
  static const String hiveDetail = '/hives/:id';

  /// Builds a concrete hive-detail path (e.g. `/hives/abc-123`).
  static String hiveDetailTo(String id) => '/hives/$id';
}
