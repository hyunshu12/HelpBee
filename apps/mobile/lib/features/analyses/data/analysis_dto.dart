/// Analysis DTOs — hand-written (no codegen). Backend contract
/// (`frontend-api-integration.md` §4): `Analysis = { id, hiveId, imageId,
/// modelId, status, varroaInfectionRisk(0-100|null), estimatedVarroaCount,
/// overallHealth('healthy'|'warning'|'critical'|null), rawResponse, latencyMs,
/// error, analyzedAt, createdAt, updatedAt }`.
///
/// `status:'failed'` is a graceful 200 (AI 실패) — UI must handle it. tier
/// (safe/watch/danger) is derived here (no tier column on the wire).
///
/// `recommendations` (권장 조치) are returned by POST /v1/analyses and
/// GET /v1/analyses/:id (frontend-api-integration §4); the list endpoint omits
/// them (payload size), so this field defaults to empty for list-sourced rows.
library;

import '../../../core/risk/risk_tier.dart';

/// A single prescription/precaution item (backend `recommendations[]`).
/// `severity`: 'info' | 'warn' | 'danger' (maps to tier color tokens on screen).
class RecommendationDto {
  const RecommendationDto({
    required this.order,
    required this.content,
    required this.severity,
  });

  final int order;
  final String content;
  final String severity;

  factory RecommendationDto.fromJson(Map<String, dynamic> json) =>
      RecommendationDto(
        order: _int(json['order']) ?? 0,
        content: (json['content'] as String?) ?? '',
        severity: (json['severity'] as String?) ?? 'info',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecommendationDto &&
          other.order == order &&
          other.content == content &&
          other.severity == severity;

  @override
  int get hashCode => Object.hash(order, content, severity);
}

class Analysis {
  const Analysis({
    required this.id,
    required this.hiveId,
    required this.imageId,
    this.modelId,
    required this.status,
    this.varroaInfectionRisk,
    this.estimatedVarroaCount,
    this.overallHealth,
    this.latencyMs,
    this.error,
    this.analyzedAt,
    required this.createdAt,
    required this.updatedAt,
    this.recommendations = const [],
  });

  final String id;
  final String hiveId;
  final String imageId;
  final String? modelId;
  final String status; // 'pending' | 'success' | 'failed'
  final int? varroaInfectionRisk; // 0~100
  final int? estimatedVarroaCount;
  final String? overallHealth; // healthy | warning | critical
  final int? latencyMs;
  final String? error;
  final DateTime? analyzedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<RecommendationDto> recommendations;

  bool get isSuccess => status == 'success';
  bool get isFailed => status == 'failed';

  /// Derived tier: prefer overallHealth, fall back to risk thresholds
  /// (<30 safe / <70 watch / else danger), unknown when not a usable success.
  RiskTier get tier {
    if (status != 'success') return RiskTier.unknown;
    // overallHealth is the primary signal — map it regardless of risk.
    switch (overallHealth) {
      case 'healthy':
        return RiskTier.safe;
      case 'warning':
        return RiskTier.watch;
      case 'critical':
        return RiskTier.danger;
    }
    // Fall back to risk bands only when overallHealth is absent.
    final r = varroaInfectionRisk;
    if (r == null) return RiskTier.unknown;
    return r < 30 ? RiskTier.safe : (r < 70 ? RiskTier.watch : RiskTier.danger);
  }

  factory Analysis.fromJson(Map<String, dynamic> json) => Analysis(
        id: json['id'] as String,
        hiveId: json['hiveId'] as String,
        imageId: json['imageId'] as String,
        modelId: json['modelId'] as String?,
        status: (json['status'] as String?) ?? 'pending',
        varroaInfectionRisk: _int(json['varroaInfectionRisk']),
        estimatedVarroaCount: _int(json['estimatedVarroaCount']),
        overallHealth: json['overallHealth'] as String?,
        latencyMs: _int(json['latencyMs']),
        error: json['error'] as String?,
        analyzedAt: _dateOrNull(json['analyzedAt']),
        createdAt: _date(json['createdAt']),
        updatedAt: _date(json['updatedAt']),
        recommendations: _recs(json['recommendations']),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Analysis &&
          other.id == id &&
          other.status == status &&
          other.varroaInfectionRisk == varroaInfectionRisk &&
          other.overallHealth == overallHealth &&
          other.analyzedAt == analyzedAt;

  @override
  int get hashCode =>
      Object.hash(id, status, varroaInfectionRisk, overallHealth, analyzedAt);
}

List<RecommendationDto> _recs(Object? v) {
  if (v is List) {
    return v
        .whereType<Map>()
        .map((e) => RecommendationDto.fromJson(
              e.map((k, val) => MapEntry(k.toString(), val)),
            ))
        .where((r) => r.content.isNotEmpty)
        .toList(growable: false);
  }
  return const [];
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

DateTime _date(Object? v) =>
    DateTime.tryParse(v?.toString() ?? '') ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _dateOrNull(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString());
