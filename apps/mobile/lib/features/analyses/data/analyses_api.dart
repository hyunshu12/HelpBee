import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_envelope.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/api/problem_details.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/app_exception.dart';
import 'analysis_dto.dart';

/// One point of the per-hive risk trend (`GET /v1/analyses/trend`).
class AnalysisTrendPoint {
  const AnalysisTrendPoint({
    required this.bucket,
    this.avgRisk,
    required this.analysisCount,
  });

  final DateTime bucket;
  final double? avgRisk;
  final int analysisCount;

  factory AnalysisTrendPoint.fromJson(Map<String, dynamic> json) {
    final raw = json['avgRisk'];
    return AnalysisTrendPoint(
      bucket: DateTime.tryParse(json['bucket']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      avgRisk: raw == null
          ? null
          : (raw is num ? raw.toDouble() : double.tryParse(raw.toString())),
      analysisCount: (json['analysisCount'] is num)
          ? (json['analysisCount'] as num).toInt()
          : int.tryParse('${json['analysisCount']}') ?? 0,
    );
  }
}

class AnalysisListResult {
  const AnalysisListResult({required this.items, this.pagination});
  final List<Analysis> items;
  final Pagination? pagination;
}

/// Datasource for `/v1/analyses` (frontend-api-integration §4). All 🔐.
class AnalysesApi {
  AnalysesApi(this._dio);

  final Dio _dio;

  static String _path([String suffix = '']) =>
      '${AppConfig.apiPrefix}/analyses$suffix';

  /// GET /v1/analyses?hiveId=&limit=&offset= -> Analysis[] (most-recent first).
  Future<AnalysisListResult> listByHive(
    String hiveId, {
    int? limit,
    int? offset,
  }) async {
    return _guard(() async {
      final res = await _dio.get<dynamic>(
        _path(),
        queryParameters: <String, dynamic>{
          'hiveId': hiveId,
          'limit': ?limit,
          'offset': ?offset,
        },
      );
      final unwrapped = unwrapEnvelope(res, _parseList);
      return AnalysisListResult(
        items: unwrapped.data,
        pagination: unwrapped.meta.pagination,
      );
    });
  }

  /// GET /v1/analyses?limit=&offset= (hiveId 생략) -> 내 모든 벌통의 이력,
  /// 최신순. 진단 이력 탭이 쓴다. 소유권/삭제 벌통 제외는 백엔드 JOIN이 강제.
  Future<AnalysisListResult> listAll({int? limit, int? offset}) async {
    return _guard(() async {
      final res = await _dio.get<dynamic>(
        _path(),
        queryParameters: <String, dynamic>{
          'limit': ?limit,
          'offset': ?offset,
        },
      );
      final unwrapped = unwrapEnvelope(res, _parseList);
      return AnalysisListResult(
        items: unwrapped.data,
        pagination: unwrapped.meta.pagination,
      );
    });
  }

  /// GET /v1/analyses/:id -> Analysis.
  Future<Analysis> getById(String id) async {
    return _guard(() async {
      final res = await _dio.get<dynamic>(_path('/$id'));
      return unwrapData(res, _parseOne);
    });
  }

  /// GET /v1/analyses/trend?hiveId=&from=&to= -> trend points.
  Future<List<AnalysisTrendPoint>> trend(
    String hiveId, {
    DateTime? from,
    DateTime? to,
  }) async {
    return _guard(() async {
      final res = await _dio.get<dynamic>(
        _path('/trend'),
        queryParameters: <String, dynamic>{
          'hiveId': hiveId,
          'from': ?from?.toUtc().toIso8601String(),
          'to': ?to?.toUtc().toIso8601String(),
        },
      );
      return unwrapData(res, (data) {
        if (data is List) {
          return data
              .map((e) => AnalysisTrendPoint.fromJson(_asMap(e)))
              .toList(growable: false);
        }
        throw AppException.unknown('unexpected trend payload shape');
      });
    });
  }

  /// POST /v1/analyses { hiveId, imageId } -> Analysis (201 new / 200 idempotent).
  /// Synchronous: the returned resource is already analyzed (may be `failed`).
  Future<Analysis> create({
    required String hiveId,
    required String imageId,
  }) async {
    return _guard(() async {
      final res = await _dio.post<dynamic>(
        _path(),
        data: {'hiveId': hiveId, 'imageId': imageId},
      );
      return unwrapData(res, _parseOne);
    });
  }

  List<Analysis> _parseList(Object? data) {
    if (data is List) {
      return data
          .map((e) => Analysis.fromJson(_asMap(e)))
          .toList(growable: false);
    }
    throw AppException.unknown('unexpected analyses list payload shape');
  }

  Analysis _parseOne(Object? data) => Analysis.fromJson(_asMap(data));

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    throw AppException.unknown('unexpected analysis payload shape');
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

final analysesApiProvider =
    Provider<AnalysesApi>((ref) => AnalysesApi(ref.read(dioProvider)));

/// Latest analysis for a hive (home card tier/score). null = no analysis yet.
/// autoDispose family so it resets across users / when the home is gone.
final latestAnalysisProvider =
    FutureProvider.autoDispose.family<Analysis?, String>((ref, hiveId) async {
  final result =
      await ref.read(analysesApiProvider).listByHive(hiveId, limit: 1);
  return result.items.isEmpty ? null : result.items.first;
});

/// Every analysis across the user's hives (진단 이력 탭), most-recent first.
///
/// Caps at the backend's max page size (100) rather than paging: the beta's
/// per-user volume is far below that, and an offset-paged infinite list would
/// need cursor semantics to stay stable. If a user ever exceeds 100 analyses
/// the tab shows the newest 100 — revisit with a cursor endpoint then.
final allAnalysesProvider =
    FutureProvider.autoDispose<List<Analysis>>((ref) async {
  final result = await ref.read(analysesApiProvider).listAll(limit: 100);
  return result.items;
});

/// Recent analyses for a hive (detail timeline, most-recent first).
final hiveAnalysesProvider =
    FutureProvider.autoDispose.family<List<Analysis>, String>((ref, hiveId) async {
  final result =
      await ref.read(analysesApiProvider).listByHive(hiveId, limit: 20);
  return result.items;
});
