import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_envelope.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/api/problem_details.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/app_exception.dart';
import 'subscription_dto.dart';

/// Datasource for `/v1/subscriptions/me` (frontend-api-integration §5).
class SubscriptionsApi {
  SubscriptionsApi(this._dio);

  final Dio _dio;

  Future<SubscriptionMe> getMe() async {
    try {
      final res = await _dio.get<dynamic>(
        '${AppConfig.apiPrefix}/subscriptions/me',
      );
      return unwrapData(res, (data) {
        if (data is Map) {
          return SubscriptionMe.fromJson(
            data.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
        throw AppException.unknown('unexpected subscription payload shape');
      });
    } on AppException {
      rethrow;
    } on DioException catch (e) {
      final wrapped = e.error;
      if (wrapped is AppException) throw wrapped;
      throw appExceptionFromDio(e);
    }
  }
}

final subscriptionsApiProvider =
    Provider<SubscriptionsApi>((ref) => SubscriptionsApi(ref.read(dioProvider)));

/// Current user's subscription (settings / quota banner). autoDispose so it
/// refetches per session and resets across users.
final subscriptionMeProvider = FutureProvider.autoDispose<SubscriptionMe>(
  (ref) => ref.read(subscriptionsApiProvider).getMe(),
);
