/// Subscription DTO — hand-written (no codegen), mirrors the auth pattern.
///
/// Backend contract (`frontend-api-integration.md` §5):
/// `GET /v1/subscriptions/me` ->
/// `{ plan, status, trialEndsAt, currentPeriodEnd,
///    features: { openaiFallback, monthlyAnalysisQuota } }`.
/// `monthlyAnalysisQuota` is 4 for free, `null` for an active paid plan
/// (= unlimited).
library;

class SubscriptionMe {
  const SubscriptionMe({
    required this.plan,
    required this.status,
    this.trialEndsAt,
    this.currentPeriodEnd,
    this.openaiFallback = false,
    this.monthlyAnalysisQuota,
  });

  final String plan; // 'free' | 'basic' | 'pro'
  final String status; // 'active' | ...
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodEnd;
  final bool openaiFallback;
  final int? monthlyAnalysisQuota; // null = unlimited

  bool get isUnlimited => monthlyAnalysisQuota == null;

  factory SubscriptionMe.fromJson(Map<String, dynamic> json) {
    final rawFeatures = json['features'];
    final features = rawFeatures is Map
        ? rawFeatures.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    return SubscriptionMe(
      plan: (json['plan'] as String?) ?? 'free',
      status: (json['status'] as String?) ?? 'active',
      trialEndsAt: _date(json['trialEndsAt']),
      currentPeriodEnd: _date(json['currentPeriodEnd']),
      openaiFallback: (features['openaiFallback'] as bool?) ?? false,
      monthlyAnalysisQuota: _int(features['monthlyAnalysisQuota']),
    );
  }
}

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString());

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}
