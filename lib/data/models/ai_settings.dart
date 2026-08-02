/// The user's AI auto-categorization configuration (BYOK — bring your own key).
///
/// The API key itself is WRITE-ONLY: the backend never returns it, so this
/// model never carries it. Status is reflected via [configured]/[hasKey]/
/// [provider]. Mirrors the backend `GET /ai/settings` response, which comes in
/// two shapes:
///   - `{"configured": false}` → [configured] is false, everything else null.
///   - the full object when the user has configured a provider.
class AiSettings {
  const AiSettings({
    required this.configured,
    this.provider,
    this.baseUrl,
    this.model,
    this.enabled = false,
    this.hasKey = false,
  });

  final bool configured;

  /// "anthropic" | "openai_compatible" (null when not configured).
  final String? provider;

  /// Optional custom base URL (openai_compatible only).
  final String? baseUrl;

  /// Optional model override.
  final String? model;

  final bool enabled;

  /// Whether an encrypted API key is stored on the server.
  final bool hasKey;

  factory AiSettings.fromJson(Map<String, dynamic> json) {
    final configured = json['configured'] as bool? ?? false;
    if (!configured) {
      return const AiSettings(configured: false);
    }
    return AiSettings(
      configured: true,
      provider: json['provider'] as String?,
      baseUrl: json['base_url'] as String?,
      model: json['model'] as String?,
      enabled: json['enabled'] as bool? ?? false,
      hasKey: json['has_key'] as bool? ?? false,
    );
  }
}
