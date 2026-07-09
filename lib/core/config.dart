import 'dart:io' show Platform;

/// App-wide configuration. Base URL differs by platform: the Android emulator
/// reaches the host machine via 10.0.2.2, while desktop/dev uses localhost.
class AppConfig {
  const AppConfig._();

  static String get apiBaseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8080/api/v1';
    }
    return 'http://localhost:8080/api/v1';
  }
}
