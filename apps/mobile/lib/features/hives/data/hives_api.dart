import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_envelope.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/api/problem_details.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/app_exception.dart';
import 'hive_dto.dart';

/// Result of a paginated hive list call.
class HiveListResult {
  const HiveListResult({required this.items, this.pagination});

  final List<Hive> items;
  final Pagination? pagination;
}

/// Thin remote datasource for `/v1/hives`
/// (`docs/01-development/frontend-api-integration.md` §2).
///
/// - Every route is authenticated; the [dioProvider] attaches the bearer and
///   the refresh-on-401 retry.
/// - Sends/receives the `{ data, meta }` success envelope.
/// - Throws a typed [AppException] (never a raw [DioException]).
class HivesApi {
  HivesApi(this._dio);

  final Dio _dio;

  static String _path([String suffix = '']) =>
      '${AppConfig.apiPrefix}/hives$suffix';

  /// GET /v1/hives?limit=&offset= -> Hive[] + pagination.
  Future<HiveListResult> list({int? limit, int? offset}) async {
    return _guard(() async {
      final res = await _dio.get<dynamic>(
        _path(),
        queryParameters: <String, dynamic>{
          'limit': ?limit,
          'offset': ?offset,
        },
      );
      final unwrapped = unwrapEnvelope(res, _parseList);
      return HiveListResult(
        items: unwrapped.data,
        pagination: unwrapped.meta.pagination,
      );
    });
  }

  /// GET /v1/hives/:id -> Hive (404 NOT_FOUND if missing / not owned — IDOR).
  Future<Hive> getById(String id) async {
    return _guard(() async {
      final res = await _dio.get<dynamic>(_path('/$id'));
      return unwrapData(res, _parseOne);
    });
  }

  /// POST /v1/hives -> 201 Hive. Coordinates must be a pair or omitted.
  Future<Hive> create({
    required String name,
    String? note,
    double? latitude,
    double? longitude,
    String? address,
    DateTime? installedAt,
  }) async {
    return _guard(() async {
      final res = await _dio.post<dynamic>(
        _path(),
        data: _writeBody(
          name: name,
          note: note,
          latitude: latitude,
          longitude: longitude,
          address: address,
          installedAt: installedAt,
        ),
      );
      return unwrapData(res, _parseOne);
    });
  }

  /// PATCH /v1/hives/:id -> 200 Hive (partial; caller sends >= 1 field).
  Future<Hive> update(
    String id, {
    String? name,
    String? note,
    double? latitude,
    double? longitude,
    String? address,
    DateTime? installedAt,
  }) async {
    return _guard(() async {
      final res = await _dio.patch<dynamic>(
        _path('/$id'),
        data: _writeBody(
          name: name,
          note: note,
          latitude: latitude,
          longitude: longitude,
          address: address,
          installedAt: installedAt,
        ),
      );
      return unwrapData(res, _parseOne);
    });
  }

  /// DELETE /v1/hives/:id -> 200 { id, deletedAt } (soft delete).
  Future<HiveDeletion> delete(String id) async {
    return _guard(() async {
      final res = await _dio.delete<dynamic>(_path('/$id'));
      return unwrapData(res, _parseDeletion);
    });
  }

  // --- body / parsing helpers ---

  /// Builds a write body, omitting nulls. The backend rejects unknown keys
  /// (mass-assignment guard), and `latitude`/`longitude` must be a pair.
  Map<String, dynamic> _writeBody({
    String? name,
    String? note,
    double? latitude,
    double? longitude,
    String? address,
    DateTime? installedAt,
  }) {
    // Mirror the backend coordinate-pair rule (createHive/updateHive schemas
    // refine `(lat == null) === (lng == null)`): fail fast on a half-pair
    // instead of round-tripping to a 400 VALIDATION_FAILED.
    if ((latitude == null) != (longitude == null)) {
      throw ArgumentError(
        'latitude and longitude must be provided together',
      );
    }
    return <String, dynamic>{
      'name': ?name,
      'note': ?note,
      'latitude': ?latitude,
      'longitude': ?longitude,
      'address': ?address,
      if (installedAt != null)
        'installedAt': installedAt.toUtc().toIso8601String(),
    };
  }

  List<Hive> _parseList(Object? data) {
    if (data is List) {
      return data.map((e) => Hive.fromJson(_asMap(e))).toList(growable: false);
    }
    throw AppException.unknown('unexpected hives list payload shape');
  }

  Hive _parseOne(Object? data) => Hive.fromJson(_asMap(data));

  HiveDeletion _parseDeletion(Object? data) =>
      HiveDeletion.fromJson(_asMap(data));

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    throw AppException.unknown('unexpected hive payload shape');
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on AppException {
      rethrow;
    } on DioException catch (e) {
      final wrapped = e.error;
      if (wrapped is AppException) throw wrapped;
      throw appExceptionFromDio(e);
    }
  }
}

/// Uses the authenticated [dioProvider].
final hivesApiProvider =
    Provider<HivesApi>((ref) => HivesApi(ref.read(dioProvider)));
