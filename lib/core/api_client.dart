import 'package:dio/dio.dart';

import 'config.dart';
import 'token_storage.dart';
import '../data/models/auth_tokens.dart';

/// Wraps a configured Dio:
///  - injects the Bearer access token on every request,
///  - on a 401, transparently refreshes the token once and retries,
///  - if refresh fails, clears the session and invokes [onSessionExpired].
class ApiClient {
  ApiClient(this._storage, this._onSessionExpired)
    : dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          contentType: Headers.jsonContentType,
        ),
      ) {
    // Bare client for the refresh call, so it never recurses through the interceptor.
    _refreshDio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
    dio.interceptors.add(_authInterceptor());
  }

  final Dio dio;
  late final Dio _refreshDio;
  final TokenStorage _storage;
  final Future<void> Function() _onSessionExpired;

  InterceptorsWrapper _authInterceptor() => InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await _storage.accessToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (error, handler) async {
      final isUnauthorized = error.response?.statusCode == 401;
      final isAuthRoute = error.requestOptions.path.contains('/auth/');
      if (!isUnauthorized || isAuthRoute) {
        return handler.next(error);
      }

      final refreshed = await _tryRefresh();
      if (!refreshed) {
        await _storage.clear();
        await _onSessionExpired();
        return handler.next(error);
      }

      // Retry the original request with the new token.
      try {
        final token = await _storage.accessToken();
        final opts = error.requestOptions;
        opts.headers['Authorization'] = 'Bearer $token';
        final response = await dio.fetch(opts);
        return handler.resolve(response);
      } on DioException catch (e) {
        return handler.next(e);
      }
    },
  );

  Future<bool> _tryRefresh() async {
    final refresh = await _storage.refreshToken();
    if (refresh == null) return false;
    try {
      final res = await _refreshDio.post(
        '/auth/refresh',
        data: {'refresh_token': refresh},
      );
      await _storage.save(
        AuthTokens.fromJson(res.data as Map<String, dynamic>),
      );
      return true;
    } on DioException {
      return false;
    }
  }
}
