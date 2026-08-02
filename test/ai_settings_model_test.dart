import 'package:flutter_test/flutter_test.dart';
import 'package:balvia_mobile/data/models/ai_settings.dart';

void main() {
  group('AiSettings.fromJson', () {
    test('parses the "configured: false" shape', () {
      final settings = AiSettings.fromJson({'configured': false});

      expect(settings.configured, false);
      expect(settings.provider, isNull);
      expect(settings.baseUrl, isNull);
      expect(settings.model, isNull);
      expect(settings.enabled, false);
      expect(settings.hasKey, false);
    });

    test('defaults to unconfigured when "configured" is absent', () {
      final settings = AiSettings.fromJson(<String, dynamic>{});

      expect(settings.configured, false);
      expect(settings.provider, isNull);
      expect(settings.hasKey, false);
    });

    test('parses the full configured shape (anthropic)', () {
      final settings = AiSettings.fromJson({
        'configured': true,
        'provider': 'anthropic',
        'enabled': true,
        'has_key': true,
      });

      expect(settings.configured, true);
      expect(settings.provider, 'anthropic');
      expect(settings.baseUrl, isNull);
      expect(settings.model, isNull);
      expect(settings.enabled, true);
      expect(settings.hasKey, true);
    });

    test('parses the full configured shape (openai_compatible)', () {
      final settings = AiSettings.fromJson({
        'configured': true,
        'provider': 'openai_compatible',
        'base_url': 'https://api.openai.com/v1',
        'model': 'gpt-4o-mini',
        'enabled': true,
        'has_key': true,
      });

      expect(settings.configured, true);
      expect(settings.provider, 'openai_compatible');
      expect(settings.baseUrl, 'https://api.openai.com/v1');
      expect(settings.model, 'gpt-4o-mini');
      expect(settings.enabled, true);
      expect(settings.hasKey, true);
    });
  });
}
