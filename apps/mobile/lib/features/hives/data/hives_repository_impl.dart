import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/hives_repository.dart';
import 'hive_dto.dart';
import 'hives_api.dart';

/// Default [HivesRepository] backed by [HivesApi].
class HivesRepositoryImpl implements HivesRepository {
  HivesRepositoryImpl(this._ref);

  final Ref _ref;

  HivesApi get _api => _ref.read(hivesApiProvider);

  @override
  Future<List<Hive>> listHives({int? limit, int? offset}) async {
    final result = await _api.list(limit: limit, offset: offset);
    return result.items;
  }

  @override
  Future<Hive> getHive(String id) => _api.getById(id);

  @override
  Future<Hive> createHive({
    required String name,
    String? note,
    double? latitude,
    double? longitude,
    String? address,
    DateTime? installedAt,
  }) =>
      _api.create(
        name: name,
        note: note,
        latitude: latitude,
        longitude: longitude,
        address: address,
        installedAt: installedAt,
      );

  @override
  Future<Hive> updateHive(
    String id, {
    String? name,
    String? note,
    double? latitude,
    double? longitude,
    String? address,
    DateTime? installedAt,
  }) =>
      _api.update(
        id,
        name: name,
        note: note,
        latitude: latitude,
        longitude: longitude,
        address: address,
        installedAt: installedAt,
      );

  @override
  Future<void> deleteHive(String id) => _api.delete(id);
}

/// App-wide [HivesRepository] singleton.
final hivesRepositoryProvider =
    Provider<HivesRepository>((ref) => HivesRepositoryImpl(ref));
