import 'package:dio/dio.dart';

import '../../core/token_storage.dart';
import '../models/auth_tokens.dart';
import '../models/user.dart';

/// Talks to the backend /auth endpoints and persists tokens on success.
class AuthRepository {
  AuthRepository(this._dio, this._storage);

  final Dio _dio;
  final TokenStorage _storage;

  Future<User> register({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final res = await _dio.post(
      '/auth/register',
      data: {
        'email': email,
        'password': password,
        if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
      },
    );
    final data = res.data as Map<String, dynamic>;
    await _storage.save(AuthTokens.fromJson(data));
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<User> login({required String email, required String password}) async {
    final res = await _dio.post(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    final data = res.data as Map<String, dynamic>;
    await _storage.save(AuthTokens.fromJson(data));
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<User> me() async {
    final res = await _dio.get('/auth/me');
    return User.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> logout() async {
    final refresh = await _storage.refreshToken();
    if (refresh != null) {
      try {
        await _dio.post('/auth/logout', data: {'refresh_token': refresh});
      } on DioException {
        // Best-effort; we clear locally regardless.
      }
    }
    await _storage.clear();
  }
}
