import 'package:dio/dio.dart';

import '../errors/app_exception.dart';

/// Pagination block from `meta.pagination` on list responses.
class Pagination {
  final int limit;
  final int offset;
  final int total;

  const Pagination({
    required this.limit,
    required this.offset,
    required this.total,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      limit: _asInt(json['limit']) ?? 0,
      offset: _asInt(json['offset']) ?? 0,
      total: _asInt(json['total']) ?? 0,
    );
  }
}

/// Parsed `meta` block of a success envelope.
class ResponseMeta {
  final String? requestId;
  final String? timestamp;
  final Pagination? pagination;

  const ResponseMeta({this.requestId, this.timestamp, this.pagination});

  factory ResponseMeta.fromJson(Map<String, dynamic> json) {
    final pag = json['pagination'];
    return ResponseMeta(
      requestId: json['requestId'] as String?,
      timestamp: json['timestamp'] as String?,
      pagination: pag is Map
          ? Pagination.fromJson(pag.map((k, v) => MapEntry(k.toString(), v)))
          : null,
    );
  }
}

/// Every 2xx response is `{ data, meta }`. This unwraps `data` and lets the
/// caller parse it into [T]. `meta` is ignored here (use [unwrapEnvelope] when
/// pagination is needed).
///
/// Throws [AppException] (unknown) if the body is not a well-formed envelope.
T unwrapData<T>(Response<dynamic> res, T Function(Object? data) parse) {
  final body = res.data;
  if (body is Map && body.containsKey('data')) {
    return parse(body['data']);
  }
  throw AppException.unknown('malformed success envelope (missing "data")');
}

/// Like [unwrapData] but also returns the parsed [ResponseMeta] for list
/// responses that carry pagination.
({T data, ResponseMeta meta}) unwrapEnvelope<T>(
  Response<dynamic> res,
  T Function(Object? data) parse,
) {
  final body = res.data;
  if (body is Map && body.containsKey('data')) {
    final rawMeta = body['meta'];
    final meta = rawMeta is Map
        ? ResponseMeta.fromJson(rawMeta.map((k, v) => MapEntry(k.toString(), v)))
        : const ResponseMeta();
    return (data: parse(body['data']), meta: meta);
  }
  throw AppException.unknown('malformed success envelope (missing "data")');
}

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}
