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

/// Top-k infested-bee evidence (v0.2.0 two-stage). Coordinates are pixels of
/// the ORIGINAL uploaded image (the app still holds it locally) — render crops
/// from `cropRegion`; no crop URL exists. `cam` is intentionally not parsed.
class Evidence {
  const Evidence({
    required this.index,
    required this.box,
    required this.cropRegion,
    required this.pInfested,
  });

  final int index;
  final List<double> box; // x1,y1,x2,y2
  final List<double> cropRegion; // x1,y1,x2,y2
  final double pInfested;

  static Evidence? fromJson(Map<String, dynamic> json) {
    final box = _doubles(json['box']);
    final region = _doubles(json['crop_region'] ?? json['cropRegion']) ?? box;
    if (box == null || region == null) return null;
    return Evidence(
      index: _int(json['index']) ?? 0,
      box: box,
      cropRegion: region,
      pInfested: _double(json['p_infested'] ?? json['pInfested']) ?? 0,
    );
  }
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
    this.vdi,
    this.vdiDisplay,
    this.vdiCiLow,
    this.vdiCiHigh,
    this.beeTotal,
    this.beeInfested,
    this.tierRaw,
    this.corrected,
    this.quality,
    this.evidence = const [],
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

  // ── v0.2.0 two-stage fields (null on legacy rows) ─────────────────────────
  final double? vdi; // 보정 VDI(%)
  final String? vdiDisplay; // 서버가 한 번 반올림한 표시 문자열 — tier 단일 소스
  final double? vdiCiLow;
  final double? vdiCiHigh;
  final int? beeTotal;
  final int? beeInfested;
  final String?
  tierRaw; // 서버 tier: low|elevated|high|insufficient|safe|watch|danger
  final bool? corrected;
  final Map<String, dynamic>? quality;
  final List<Evidence> evidence;

  bool get isTwoStage => beeTotal != null || vdiDisplay != null;

  bool get isSuccess => status == 'success';
  bool get isFailed => status == 'failed';

  /// Derived tier: prefer overallHealth, fall back to risk thresholds
  /// (<30 safe / <70 watch / else danger), unknown when not a usable success.
  RiskTier get tier {
    if (status != 'success') return RiskTier.unknown;
    // v0.2.0: the server's tier string is authoritative (computed from
    // vdi_display); never recompute from vdi on the client.
    if (tierRaw != null) {
      return riskTierFromServer(tierRaw, overallHealth: overallHealth);
    }
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
    vdi: _double(json['vdi']),
    vdiDisplay: json['vdiDisplay'] as String?,
    vdiCiLow: _ci(json['samplingCi95'], 0) ?? _double(json['vdiCiLow']),
    vdiCiHigh: _ci(json['samplingCi95'], 1) ?? _double(json['vdiCiHigh']),
    beeTotal: _int(json['beeTotal']),
    beeInfested: _int(json['beeInfested']),
    tierRaw: json['tier'] as String?,
    corrected: json['corrected'] as bool?,
    quality: json['quality'] is Map
        ? (json['quality'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : null,
    evidence: _evidence(json['evidence']),
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
        .map(
          (e) => RecommendationDto.fromJson(
            e.map((k, val) => MapEntry(k.toString(), val)),
          ),
        )
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

double? _double(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

double? _ci(Object? v, int i) =>
    (v is List && v.length > i) ? _double(v[i]) : null;

List<double>? _doubles(Object? v) {
  if (v is! List || v.length < 4) return null;
  final out = <double>[];
  for (final e in v) {
    final d = _double(e);
    if (d == null) return null;
    out.add(d);
  }
  return out;
}

List<Evidence> _evidence(Object? v) {
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map(
        (e) =>
            Evidence.fromJson(e.map((k, val) => MapEntry(k.toString(), val))),
      )
      .whereType<Evidence>()
      .toList(growable: false);
}
