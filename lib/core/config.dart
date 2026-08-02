import 'dart:io' show Platform;

/// App-wide configuration. Base URL differs by platform: the Android emulator
/// reaches the host machine via 10.0.2.2, while desktop/dev uses localhost.
class AppConfig {
  const AppConfig._();

  /// Currency every amount is created with. Colombia-only for the MVP; this
  /// constant exists so new code has one place to read it from instead of
  /// repeating the literal, and so making it user-configurable later is a
  /// single change.
  static const defaultCurrency = 'COP';

  /// Compile-time override for physical devices on the LAN:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.1.6:8080/api/v1
  static const _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8080/api/v1';
    }
    return 'http://localhost:8080/api/v1';
  }
}
