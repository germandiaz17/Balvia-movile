/// Tests for the UserSettings model and its repository.
///
/// The repository test guards the COALESCE contract: the backend leaves a
/// column alone only when the key is absent, so a partial update must not send
/// keys the user did not change.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balvia_mobile/data/models/user_settings.dart';
import 'package:balvia_mobile/data/repositories/user_settings_repository.dart';

import 'fake_http_adapter.dart';

void main() {
  Map<String, dynamic> settingsJson({
    int trackingStartDay = 15,
    int trackingDurationDays = 30,
    String? activePeriodEndDate = '2026-08-13',
    String updatedAt = '2026-08-01T02:09:08Z',
  }) => <String, dynamic>{
    'tracking_start_day': trackingStartDay,
    'tracking_duration_days': trackingDurationDays,
    'default_currency': 'COP',
    'country_code': 'CO',
    'locale': 'es-CO',
    'theme': 'system',
    'default_period_view': 'full',
    'subscription_tier': 'free',
    'updated_at': updatedAt,
    'applies_to_next_period': true,
    'active_period_end_date': activePeriodEndDate,
  };

  group('UserSettings.fromJson', () {
    test('parses the full payload', () {
      final s = UserSettings.fromJson(settingsJson());

      expect(s.trackingStartDay, 15);
      expect(s.trackingDurationDays, 30);
      expect(s.defaultCurrency, 'COP');
      expect(s.countryCode, 'CO');
      expect(s.locale, 'es-CO');
      expect(s.theme, 'system');
      expect(s.defaultPeriodView, 'full');
      expect(s.subscriptionTier, 'free');
      expect(s.appliesToNextPeriod, isTrue);
      expect(s.activePeriodEndDate, DateTime(2026, 8, 13));
      expect(s.updatedAt, isNotNull);
    });

    test('a user with no active period parses fine', () {
      final s = UserSettings.fromJson(settingsJson(activePeriodEndDate: null));
      expect(s.activePeriodEndDate, isNull);
      expect(s.nextPeriodStartDate, isNull);
    });

    test('an empty updated_at is treated as absent', () {
      final s = UserSettings.fromJson(settingsJson(updatedAt: ''));
      expect(s.updatedAt, isNull);
    });

    test('nextPeriodStartDate is the day after the current period ends', () {
      final s = UserSettings.fromJson(settingsJson());
      expect(s.nextPeriodStartDate, DateTime(2026, 8, 14));
    });

    test('nextPeriodStartDate crosses a month boundary', () {
      final s = UserSettings.fromJson(
        settingsJson(activePeriodEndDate: '2026-08-31'),
      );
      expect(s.nextPeriodStartDate, DateTime(2026, 9, 1));
    });
  });

  group('kTrackingDurations', () {
    test('offers exactly the range the CHECK constraint allows', () {
      expect(kTrackingDurations, [28, 29, 30, 31]);
    });
  });

  group('longDate', () {
    test('renders the Spanish month name', () {
      expect(longDate(DateTime(2026, 8, 13)), '13 de agosto');
      expect(longDate(DateTime(2026, 1, 1)), '1 de enero');
      expect(longDate(DateTime(2026, 12, 31)), '31 de diciembre');
    });
  });

  group('UserSettingsRepository', () {
    (UserSettingsRepository, FakeHttpAdapter) build(
      List<FakeResponse> responses,
    ) {
      final adapter = FakeHttpAdapter(responses);
      final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))
        ..httpClientAdapter = adapter;
      return (UserSettingsRepository(dio), adapter);
    }

    test('get hits the singleton path', () async {
      final (repo, adapter) = build([FakeResponse(body: settingsJson())]);

      final s = await repo.get();

      expect(s.trackingDurationDays, 30);
      expect(adapter.request.method, 'GET');
      expect(adapter.request.path, '/settings');
    });

    test('a partial update sends ONLY the changed key', () async {
      final (repo, adapter) = build([
        FakeResponse(body: settingsJson(trackingDurationDays: 31)),
      ]);

      await repo.update(trackingDurationDays: 31);

      final body = adapter.request.body!;
      expect(adapter.request.method, 'PUT');
      expect(adapter.request.path, '/settings');
      expect(body, {'tracking_duration_days': 31});
      // COALESCE only preserves a column when its key is absent.
      expect(body.containsKey('tracking_start_day'), isFalse);
      expect(body.containsKey('theme'), isFalse);
      expect(body.containsKey('default_currency'), isFalse);
      expect(body.containsKey('locale'), isFalse);
      expect(body.containsKey('default_period_view'), isFalse);
    });

    test('several fields at once all travel', () async {
      final (repo, adapter) = build([FakeResponse(body: settingsJson())]);

      await repo.update(
        trackingStartDay: 5,
        trackingDurationDays: 28,
        theme: 'dark',
        locale: 'es-CO',
        defaultCurrency: 'COP',
        defaultPeriodView: 'weekly',
      );

      expect(adapter.request.body, {
        'tracking_start_day': 5,
        'tracking_duration_days': 28,
        'default_currency': 'COP',
        'locale': 'es-CO',
        'theme': 'dark',
        'default_period_view': 'weekly',
      });
    });

    test('an update with no arguments sends an empty body', () async {
      final (repo, adapter) = build([FakeResponse(body: settingsJson())]);

      await repo.update();

      expect(adapter.request.body, isEmpty);
    });

    test('surfaces a 422 from the backend', () async {
      final (repo, _) = build([
        FakeResponse(
          statusCode: 422,
          body: {'error': 'invalid tracking configuration'},
        ),
      ]);

      expect(
        () => repo.update(trackingDurationDays: 27),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            422,
          ),
        ),
      );
    });
  });

  group('tracking period mode', () {
    test('defaults to rolling when a legacy backend omits the field', () {
      final s = UserSettings.fromJson(settingsJson());

      expect(s.trackingPeriodMode, kPeriodModeRolling);
      expect(s.usesCalendarMonths, isFalse);
    });

    test('parses calendar month', () {
      final json = settingsJson()..['tracking_period_mode'] = 'calendar_month';
      final s = UserSettings.fromJson(json);

      expect(s.trackingPeriodMode, kPeriodModeCalendar);
      expect(s.usesCalendarMonths, isTrue);
    });

    test('applies_to_next_period false survives the onboarding carve-out', () {
      final json = settingsJson()..['applies_to_next_period'] = false;

      expect(UserSettings.fromJson(json).appliesToNextPeriod, isFalse);
    });

    test('update sends only the mode when only the mode changed', () async {
      final adapter = FakeHttpAdapter([
        FakeResponse(
          body: settingsJson()..['tracking_period_mode'] = 'calendar_month',
        ),
      ]);
      final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))
        ..httpClientAdapter = adapter;

      await UserSettingsRepository(
        dio,
      ).update(trackingPeriodMode: kPeriodModeCalendar);

      final body = adapter.request.body!;
      expect(body, {'tracking_period_mode': 'calendar_month'});
      // Absent, not null — that is what COALESCE needs to leave columns alone.
      expect(body.containsKey('tracking_duration_days'), isFalse);
      expect(body.containsKey('tracking_start_day'), isFalse);
    });
  });
}
