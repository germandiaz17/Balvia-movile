import 'package:dio/dio.dart';

/// Turns an error into a user-facing message, surfacing the backend's
/// `{"error": "..."}` body when present.
String apiErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['error'] is String) {
      return data['error'] as String;
    }
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return 'No se pudo conectar con el servidor. ¿Está corriendo el backend?';
      default:
        return error.message ?? 'Error de red';
    }
  }
  return error.toString();
}
