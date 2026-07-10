import 'package:flutter_test/flutter_test.dart';
import 'package:balvia_mobile/data/models/tracking_period.dart';

void main() {
  // A period that starts 2026-07-04 and ends 2026-08-02 (30 days).
  final sampleJson = {
    'id': 'tp-1',
    'sequence_number': 1,
    'start_date': '2026-07-04',
    'end_date': '2026-08-02',
    'status': 'active',
    'config_start_day': 4,
    'config_duration_days': 30,
    'closed_at': null,
  };

  group('TrackingPeriod.fromJson', () {
    test('parses all fields correctly', () {
      final tp = TrackingPeriod.fromJson(sampleJson);
      expect(tp.id, 'tp-1');
      expect(tp.sequenceNumber, 1);
      expect(tp.startDate, '2026-07-04');
      expect(tp.endDate, '2026-08-02');
      expect(tp.status, 'active');
      expect(tp.configStartDay, 4);
      expect(tp.configDurationDays, 30);
      expect(tp.closedAt, isNull);
    });

    test('isActive is true when status is active', () {
      final tp = TrackingPeriod.fromJson(sampleJson);
      expect(tp.isActive, isTrue);
    });

    test('isActive is false when status is closed', () {
      final json = Map<String, dynamic>.from(sampleJson)
        ..['status'] = 'closed'
        ..['closed_at'] = '2026-08-03T00:00:00Z';
      final tp = TrackingPeriod.fromJson(json);
      expect(tp.isActive, isFalse);
    });

    test('parses closed_at as DateTime when present', () {
      final json = Map<String, dynamic>.from(sampleJson)
        ..['status'] = 'closed'
        ..['closed_at'] = '2026-08-03T10:30:00Z';
      final tp = TrackingPeriod.fromJson(json);
      expect(tp.closedAt, isNotNull);
      expect(tp.closedAt!.year, 2026);
      expect(tp.closedAt!.month, 8);
    });
  });

  group('TrackingPeriod computed properties', () {
    test('durationDays is correct (inclusive)', () {
      // 2026-07-04 to 2026-08-02 = 29 diff + 1 = 30 days.
      final tp = TrackingPeriod.fromJson(sampleJson);
      expect(tp.durationDays, 30);
    });

    test('progressFraction is between 0 and 1', () {
      final tp = TrackingPeriod.fromJson(sampleJson);
      expect(tp.progressFraction, greaterThanOrEqualTo(0.0));
      expect(tp.progressFraction, lessThanOrEqualTo(1.0));
    });

    test('daysElapsed + daysRemaining <= durationDays', () {
      final tp = TrackingPeriod.fromJson(sampleJson);
      expect(
        tp.daysElapsed + tp.daysRemaining,
        lessThanOrEqualTo(tp.durationDays),
      );
    });

    test('single-day period has durationDays = 1', () {
      final json = Map<String, dynamic>.from(sampleJson)
        ..['start_date'] = '2026-07-10'
        ..['end_date'] = '2026-07-10';
      final tp = TrackingPeriod.fromJson(json);
      expect(tp.durationDays, 1);
    });
  });
}
