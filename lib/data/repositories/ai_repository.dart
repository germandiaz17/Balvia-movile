import 'package:dio/dio.dart';

import '../models/ai_settings.dart';

/// A category suggestion returned by the AI categorize endpoint.
/// [categoryId] is null when the model could not confidently pick a category.
class AiSuggestion {
  const AiSuggestion({required this.categoryId, required this.confidence});

  final String? categoryId;
  final double confidence;

  factory AiSuggestion.fromJson(Map<String, dynamic> json) => AiSuggestion(
    categoryId: json['category_id'] as String?,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
  );
}

/// Handles the AI auto-categorization feature (BYOK).
/// Auth is added by the dio interceptor. Mirrors the backend `/ai/*` endpoints.
class AiRepository {
  AiRepository(this._dio);

  final Dio _dio;

  /// Returns the user's current AI configuration status.
  Future<AiSettings> getSettings() async {
    final res = await _dio.get('/ai/settings');
    return AiSettings.fromJson(res.data as Map<String, dynamic>);
  }

  /// Stores/updates the provider + API key. [baseUrl]/[model] are sent only
  /// when non-null and non-empty. Returns the resulting (configured) settings.
  Future<AiSettings> setSettings({
    required String provider,
    required String apiKey,
    String? baseUrl,
    String? model,
  }) async {
    final body = <String, dynamic>{'provider': provider, 'api_key': apiKey};
    if (baseUrl != null && baseUrl.isNotEmpty) {
      body['base_url'] = baseUrl;
    }
    if (model != null && model.isNotEmpty) {
      body['model'] = model;
    }
    final res = await _dio.put('/ai/settings', data: body);
    return AiSettings.fromJson(res.data as Map<String, dynamic>);
  }

  /// Removes the stored AI configuration (and the encrypted key).
  Future<void> deleteSettings() async {
    await _dio.delete('/ai/settings');
  }

  /// Asks the AI to categorize a transaction. Best-effort: callers should
  /// swallow errors (422 not configured, 502 bad key, 503 disabled, offline).
  Future<AiSuggestion> categorize({
    required String description,
    String? amount,
    String? merchant,
    String? transactionType,
  }) async {
    final body = <String, dynamic>{'description': description};
    if (amount != null && amount.isNotEmpty) {
      body['amount'] = amount;
    }
    if (merchant != null && merchant.isNotEmpty) {
      body['merchant'] = merchant;
    }
    if (transactionType != null && transactionType.isNotEmpty) {
      body['transaction_type'] = transactionType;
    }
    final res = await _dio.post('/ai/categorize', data: body);
    return AiSuggestion.fromJson(res.data as Map<String, dynamic>);
  }
}
