/// Hive DTOs — hand-written (no freezed / json_serializable codegen).
///
/// Mirrors the auth feature's manual-DTO approach (build_runner is incompatible
/// with this Dart 3.10 toolchain). Backend contract
/// (`docs/01-development/frontend-api-integration.md` §2):
/// `Hive = { id, userId, name, note, latitude, longitude, address, installedAt,
/// createdAt, updatedAt, deletedAt }`.
///
/// ⚠️ `latitude` / `longitude` arrive as **strings** (PostgreSQL numeric, e.g.
/// `"37.491200"`) and are parsed to [double] here. `note` / `address` /
/// `installedAt` / `deletedAt` may be null.
library;

class Hive {
  const Hive({
    required this.id,
    required this.userId,
    required this.name,
    this.note,
    this.latitude,
    this.longitude,
    this.address,
    this.installedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final String name;
  final String? note;
  final double? latitude;
  final double? longitude;
  final String? address;
  final DateTime? installedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// True when both coordinates are present (the backend sends them as a pair).
  bool get hasLocation => latitude != null && longitude != null;

  factory Hive.fromJson(Map<String, dynamic> json) => Hive(
        id: json['id'] as String,
        userId: json['userId'] as String,
        name: json['name'] as String,
        note: json['note'] as String?,
        latitude: _asDouble(json['latitude']),
        longitude: _asDouble(json['longitude']),
        address: json['address'] as String?,
        installedAt: _asDateOrNull(json['installedAt']),
        createdAt: _asDate(json['createdAt']),
        updatedAt: _asDate(json['updatedAt']),
        deletedAt: _asDateOrNull(json['deletedAt']),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Hive &&
          other.id == id &&
          other.userId == userId &&
          other.name == name &&
          other.note == note &&
          other.latitude == latitude &&
          other.longitude == longitude &&
          other.address == address &&
          other.installedAt == installedAt &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, userId, name, note, latitude, longitude,
      address, installedAt, createdAt, updatedAt, deletedAt);
}

/// `DELETE /v1/hives/:id` -> `{ id, deletedAt }` (soft delete).
class HiveDeletion {
  const HiveDeletion({required this.id, this.deletedAt});

  final String id;
  final DateTime? deletedAt;

  factory HiveDeletion.fromJson(Map<String, dynamic> json) => HiveDeletion(
        id: json['id'] as String,
        deletedAt: _asDateOrNull(json['deletedAt']),
      );
}

// ── parsing helpers ──────────────────────────────────────────────────────────

double? _asDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

DateTime _asDate(Object? v) {
  final parsed = DateTime.tryParse(v?.toString() ?? '');
  return parsed ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

DateTime? _asDateOrNull(Object? v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}
