import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_envelope.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/api/problem_details.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/app_exception.dart';
import 'auth_dto.dart';

/// Thin remote datasource for the `/v1/auth/*` endpoints.
///
/// - Sends/receives the `{ data, meta }` success envelope; unwraps `data`.
/// - `/refresh` sends `refreshToken` in the **body** (never a header).
/// - Every thrown error is a typed [AppException] (the [AuthInterceptor]
///   already wraps failures, but we unwrap here so callers never see a raw
///   [DioException]).
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  static String _path(String suffix) => '${AppConfig.apiPrefix}/auth$suffix';

  /// POST /v1/auth/signup { email, password, name } -> AuthSession.
  Future<AuthSession> signup({
    required String email,
    required String password,
    required String name,
  }) async {
    return _guard(() async {
      final res = await _dio.post<dynamic>(
        _path('/signup'),
        data: {'email': email, 'password': password, 'name': name},
      );
      return unwrapData(res, _parseSession);
    });
  }

  /// POST /v1/auth/login { email, password } -> AuthSession.
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    return _guard(() async {
      final res = await _dio.post<dynamic>(
        _path('/login'),
        data: {'email': email, 'password': password},
      );
      return unwrapData(res, _parseSession);
    });
  }

  /// POST /v1/auth/refresh { refreshToken } -> AuthTokens (new pair).
  ///
  /// NOTE: app-level refresh-on-401 is centralized in [RefreshCoordinator];
  /// this method exists for completeness / explicit flows. Refresh token goes
  /// in the BODY.
  Future<AuthTokens> refresh(String refreshToken) async {
    return _guard(() async {
      final res = await _dio.post<dynamic>(
        _path('/refresh'),
        data: {'refreshToken': refreshToken},
      );
      return unwrapData(res, _parseTokens);
    });
  }

  /// POST /v1/auth/logout (auth) { refreshToken } -> revoked.
  Future<void> logout(String refreshToken) async {
    return _guard(() async {
      await _dio.post<dynamic>(
        _path('/logout'),
        data: {'refreshToken': refreshToken},
      );
    });
  }

  /// GET /v1/auth/me (auth) -> { user, subscription }.
  Future<MeResult> me() async {
    return _guard(() async {
      final res = await _dio.get<dynamic>(_path('/me'));
      return unwrapData(res, _parseMe);
    });
  }

  // --- parsing helpers (kept off the freezed generated fromJson because the
  // auth envelope is FLAT) ---

  AuthSession _parseSession(Object? data) {
    final map = _asMap(data);
    return AuthSession.fromAuthData(map);
  }

  AuthTokens _parseTokens(Object? data) {
    final map = _asMap(data);
    return AuthTokens.fromJson(map);
  }

  MeResult _parseMe(Object? data) {
    final map = _asMap(data);
    return MeResult.fromJson(map);
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    throw AppException.unknown('unexpected auth payload shape');
  }

  /// Runs [body], converting any [DioException] (and its interceptor-wrapped
  /// [AppException]) into a thrown [AppException].
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
final authApiProvider =
    Provider<AuthApi>((ref) => AuthApi(ref.read(dioProvider)));
