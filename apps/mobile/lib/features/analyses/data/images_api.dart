import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_envelope.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/api/problem_details.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/app_exception.dart';

/// `POST /v1/images/presign` result (frontend-api-integration §3).
class PresignResult {
  const PresignResult({
    required this.uploadUrl,
    required this.objectKey,
    required this.expiresIn,
  });

  final String uploadUrl;
  final String objectKey;
  final int expiresIn; // seconds (server hardcodes 300)

  factory PresignResult.fromJson(Map<String, dynamic> json) => PresignResult(
    uploadUrl: json['uploadUrl'] as String,
    objectKey: json['objectKey'] as String,
    expiresIn: (json['expiresIn'] is num)
        ? (json['expiresIn'] as num).toInt()
        : int.tryParse('${json['expiresIn']}') ?? 300,
  );
}

/// `POST /v1/images/confirm` result — the stored AnalysisImage row. `id` is the
/// `imageId` input for `POST /v1/analyses`. Server normalizes to image/jpeg.
class AnalysisImage {
  const AnalysisImage({
    required this.id,
    required this.hiveId,
    this.mimeType,
    this.width,
    this.height,
    this.byteSize,
    this.capturedAt,
    this.createdAt,
  });

  final String id;
  final String hiveId;
  final String? mimeType;
  final int? width;
  final int? height;
  final int? byteSize;
  final DateTime? capturedAt;
  final DateTime? createdAt;

  factory AnalysisImage.fromJson(Map<String, dynamic> json) => AnalysisImage(
    id: json['id'] as String,
    hiveId: json['hiveId'] as String,
    mimeType: json['mimeType'] as String?,
    width: _int(json['width']),
    height: _int(json['height']),
    byteSize: _int(json['byteSize']),
    capturedAt: _dateOrNull(json['capturedAt']),
    createdAt: _dateOrNull(json['createdAt']),
  );
}

/// Datasource for the image-upload leg of the diagnosis pipeline:
/// presign → S3 PUT (no auth) → confirm. The authenticated [Dio] signs
/// presign/confirm; the bare [Dio] sends the S3 PUT with NO Authorization
/// header (the presigned URL is self-authenticating).
class ImagesApi {
  ImagesApi(this._dio, this._bareDio);

  final Dio _dio;
  final Dio _bareDio;

  static String _path(String suffix) => '${AppConfig.apiPrefix}/images$suffix';

  /// POST /v1/images/presign { filename, contentType } -> { uploadUrl, objectKey, expiresIn }.
  Future<PresignResult> presign({
    required String filename,
    required String contentType,
  }) async {
    return _guard(() async {
      final res = await _dio.post<dynamic>(
        _path('/presign'),
        data: {'filename': filename, 'contentType': contentType},
      );
      return unwrapData(res, (d) => PresignResult.fromJson(_asMap(d)));
    });
  }

  /// PUT the bytes straight to S3 via the presigned URL. The `Content-Type`
  /// MUST equal the value sent to presign or S3 rejects the signature.
  Future<void> uploadToS3({
    required String uploadUrl,
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      await _bareDio.put<dynamic>(
        uploadUrl,
        data: Stream<List<int>>.fromIterable([bytes]),
        options: Options(
          headers: <String, dynamic>{
            Headers.contentTypeHeader: contentType,
            Headers.contentLengthHeader: bytes.length,
          },
        ),
      );
    } on DioException catch (e) {
      // S3 failures aren't problem+json; surface as a generic upload failure.
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw AppException.timeout();
      }
      throw AppException.network();
    }
  }

  /// POST /v1/images/confirm { objectKey, hiveId, capturedAt? } -> AnalysisImage.
  Future<AnalysisImage> confirm({
    required String objectKey,
    required String hiveId,
    DateTime? capturedAt,
  }) async {
    return _guard(() async {
      final res = await _dio.post<dynamic>(
        _path('/confirm'),
        data: <String, dynamic>{
          'objectKey': objectKey,
          'hiveId': hiveId,
          'capturedAt': ?capturedAt?.toUtc().toIso8601String(),
        },
      );
      return unwrapData(res, (d) => AnalysisImage.fromJson(_asMap(d)));
    });
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    throw AppException.unknown('unexpected image payload shape');
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

final imagesApiProvider = Provider<ImagesApi>(
  (ref) => ImagesApi(ref.read(dioProvider), ref.read(bareDioProvider)),
);

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

DateTime? _dateOrNull(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString());
