import '../data/hive_dto.dart';

/// Domain contract for hive (양봉장) management.
///
/// The presentation layer depends ONLY on this interface (never on `data/`).
/// Every method throws an [AppException] on failure; the presentation layer
/// catches and maps it to a localized Korean message.
abstract class HivesRepository {
  /// Lists the current user's hives.
  Future<List<Hive>> listHives({int? limit, int? offset});

  /// Fetches a single owned hive. Throws (NOT_FOUND) if missing / not owned.
  Future<Hive> getHive(String id);

  /// Creates a hive. Coordinates are optional but must be a pair when given.
  Future<Hive> createHive({
    required String name,
    String? note,
    double? latitude,
    double? longitude,
    String? address,
    DateTime? installedAt,
  });

  /// Partially updates an owned hive (caller supplies >= 1 field).
  Future<Hive> updateHive(
    String id, {
    String? name,
    String? note,
    double? latitude,
    double? longitude,
    String? address,
    DateTime? installedAt,
  });

  /// Soft-deletes an owned hive.
  Future<void> deleteHive(String id);
}
