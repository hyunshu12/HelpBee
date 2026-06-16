/// Auth DTOs — hand-written (no freezed / json_serializable codegen).
///
/// build_runner is currently incompatible with this Dart 3.10 SDK because the
/// dependency graph contains native build hooks (`objective_c` via
/// `path_provider_foundation`). Until build_runner supports `dart build`, these
/// data classes are written by hand. Public API is identical to the previous
/// freezed version (`fromJson`, `fromAuthData`, value equality), so callers are
/// unaffected. Reintroduce freezed when the toolchain catches up.
library;

/// The user object returned by `/v1/auth/*` and `/v1/auth/me`.
///
/// Backend contract: `{ id, email, name, role:'user'|'admin', emailVerified, createdAt: ISO }`.
/// `role` is kept as a plain [String] so an unexpected server role never crashes
/// deserialization.
class PublicUser {
  const PublicUser({
    required this.id,
    required this.email,
    required this.name,
    this.role = 'user',
    this.emailVerified = false,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String name;
  final String role;
  final bool emailVerified;
  final DateTime createdAt;

  /// Convenience role check (admin screens are out of scope for mobile).
  bool get isAdmin => role == 'admin';

  factory PublicUser.fromJson(Map<String, dynamic> json) => PublicUser(
        id: json['id'] as String,
        email: json['email'] as String,
        name: json['name'] as String,
        role: (json['role'] as String?) ?? 'user',
        emailVerified: (json['emailVerified'] as bool?) ?? false,
        createdAt: _parseDate(json['createdAt']),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublicUser &&
          other.id == id &&
          other.email == email &&
          other.name == name &&
          other.role == role &&
          other.emailVerified == emailVerified &&
          other.createdAt == createdAt;

  @override
  int get hashCode =>
      Object.hash(id, email, name, role, emailVerified, createdAt);
}

/// The token triple returned by signup / login / refresh.
///
/// - `accessToken`: short-lived (15m), memory only.
/// - `refreshToken`: long-lived (7d), secure storage only.
/// - `expiresIn`: access lifetime in seconds (900).
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.expiresIn = 900,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        expiresIn: _asInt(json['expiresIn']) ?? 900,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthTokens &&
          other.accessToken == accessToken &&
          other.refreshToken == refreshToken &&
          other.expiresIn == expiresIn;

  @override
  int get hashCode => Object.hash(accessToken, refreshToken, expiresIn);
}

/// A full authenticated session = user + tokens.
///
/// The signup/login envelope `data` is FLAT
/// (`{ user, accessToken, refreshToken, expiresIn }`), so [fromAuthData]
/// reshapes it into a nested [AuthTokens]. [fromJson] accepts the nested
/// form `{ user, tokens }` for completeness.
class AuthSession {
  const AuthSession({required this.user, required this.tokens});

  final PublicUser user;
  final AuthTokens tokens;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        user: PublicUser.fromJson(_asStringMap(json['user'])),
        tokens: AuthTokens.fromJson(_asStringMap(json['tokens'])),
      );

  /// Parses the FLAT auth envelope `data` payload:
  /// `{ user, accessToken, refreshToken, expiresIn }`.
  factory AuthSession.fromAuthData(Map<String, dynamic> data) => AuthSession(
        user: PublicUser.fromJson(_asStringMap(data['user'])),
        tokens: AuthTokens(
          accessToken: data['accessToken'] as String,
          refreshToken: data['refreshToken'] as String,
          expiresIn: _asInt(data['expiresIn']) ?? 900,
        ),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthSession && other.user == user && other.tokens == tokens;

  @override
  int get hashCode => Object.hash(user, tokens);
}

/// `subscription` block from `/v1/auth/me` -> `{ plan, status }`.
class SubscriptionBrief {
  const SubscriptionBrief({required this.plan, required this.status});

  final String plan;
  final String status;

  factory SubscriptionBrief.fromJson(Map<String, dynamic> json) =>
      SubscriptionBrief(
        plan: json['plan'] as String,
        status: json['status'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionBrief &&
          other.plan == plan &&
          other.status == status;

  @override
  int get hashCode => Object.hash(plan, status);
}

/// `/v1/auth/me` -> `{ user, subscription:{ plan, status } }`.
class MeResult {
  const MeResult({required this.user, required this.subscription});

  final PublicUser user;
  final SubscriptionBrief subscription;

  factory MeResult.fromJson(Map<String, dynamic> json) => MeResult(
        user: PublicUser.fromJson(_asStringMap(json['user'])),
        subscription:
            SubscriptionBrief.fromJson(_asStringMap(json['subscription'])),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeResult &&
          other.user == user &&
          other.subscription == subscription;

  @override
  int get hashCode => Object.hash(user, subscription);
}

// ── parsing helpers ──────────────────────────────────────────────────────────

Map<String, dynamic> _asStringMap(Object? v) {
  if (v is Map) {
    return v.map((k, value) => MapEntry(k.toString(), value));
  }
  throw const FormatException('expected a JSON object');
}

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

DateTime _parseDate(Object? v) {
  final parsed = DateTime.tryParse(v?.toString() ?? '');
  return parsed ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
