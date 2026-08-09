import 'package:balvia_mobile/core/period_math.dart';
import 'package:balvia_mobile/data/models/user_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// This table mirrors TestNextPeriodRange in the backend's
/// internal/domain/period_test.go, case for case. The two implementations are a
/// deliberate duplication (see period_math.dart); keeping the tables identical
/// is what stops them drifting apart unnoticed.
void main() {
  DateTime d(String s) => DateTime.parse(s);

  group('nextPeriodRange', () {
    final cases = <String, Map<String, dynamic>>{
      'rolling chains a block of the configured length': {
        'prevEnd': '2026-09-03',
        'mode': kPeriodModeRolling,
        'duration': 30,
        'start': '2026-09-04',
        'end': '2026-10-03',
        'transition': false,
        'days': 30,
      },
      'rolling honours a 28 day duration': {
        'prevEnd': '2026-09-03',
        'mode': kPeriodModeRolling,
        'duration': 28,
        'start': '2026-09-04',
        'end': '2026-10-01',
        'transition': false,
        'days': 28,
      },
      'calendar already aligned yields a clean month': {
        'prevEnd': '2026-08-31',
        'mode': kPeriodModeCalendar,
        'duration': 30,
        'start': '2026-09-01',
        'end': '2026-09-30',
        'transition': false,
        'days': 30,
      },
      'calendar mid month with room to spare bridges short': {
        'prevEnd': '2026-09-03',
        'mode': kPeriodModeCalendar,
        'duration': 30,
        'start': '2026-09-04',
        'end': '2026-09-30',
        'transition': true,
        'days': 27,
      },
      'calendar with exactly the floor left bridges short': {
        'prevEnd': '2026-09-15',
        'mode': kPeriodModeCalendar,
        'duration': 30,
        'start': '2026-09-16',
        'end': '2026-09-30',
        'transition': true,
        'days': 15,
      },
      'calendar one day under the floor bridges long': {
        'prevEnd': '2026-09-16',
        'mode': kPeriodModeCalendar,
        'duration': 30,
        'start': '2026-09-17',
        'end': '2026-10-31',
        'transition': true,
        'days': 45,
      },
      'calendar with too little left absorbs the next month': {
        'prevEnd': '2026-09-25',
        'mode': kPeriodModeCalendar,
        'duration': 30,
        'start': '2026-09-26',
        'end': '2026-10-31',
        'transition': true,
        'days': 36,
      },
      'calendar bridging out of January lands on a leap February': {
        'prevEnd': '2028-01-20',
        'mode': kPeriodModeCalendar,
        'duration': 30,
        'start': '2028-01-21',
        'end': '2028-02-29',
        'transition': true,
        'days': 40,
      },
      'calendar bridging out of January lands on a common February': {
        'prevEnd': '2026-01-20',
        'mode': kPeriodModeCalendar,
        'duration': 30,
        'start': '2026-01-21',
        'end': '2026-02-28',
        'transition': true,
        'days': 39,
      },
      'calendar steady state through February': {
        'prevEnd': '2026-01-31',
        'mode': kPeriodModeCalendar,
        'duration': 30,
        'start': '2026-02-01',
        'end': '2026-02-28',
        'transition': false,
        'days': 28,
      },
      'calendar steady state across a year boundary': {
        'prevEnd': '2026-12-31',
        'mode': kPeriodModeCalendar,
        'duration': 30,
        'start': '2027-01-01',
        'end': '2027-01-31',
        'transition': false,
        'days': 31,
      },
      'calendar bridging from the last day of a month': {
        'prevEnd': '2026-09-29',
        'mode': kPeriodModeCalendar,
        'duration': 30,
        'start': '2026-09-30',
        'end': '2026-10-31',
        'transition': true,
        'days': 32,
      },
      'switching back to rolling from a calendar month needs no bridge': {
        'prevEnd': '2026-09-30',
        'mode': kPeriodModeRolling,
        'duration': 30,
        'start': '2026-10-01',
        'end': '2026-10-30',
        'transition': false,
        'days': 30,
      },
    };

    cases.forEach((name, c) {
      test(name, () {
        final got = nextPeriodRange(
          prevEnd: d(c['prevEnd'] as String),
          mode: c['mode'] as String,
          durationDays: c['duration'] as int,
        );

        expect(got.start, d(c['start'] as String), reason: 'start');
        expect(got.end, d(c['end'] as String), reason: 'end');
        expect(got.isTransition, c['transition'], reason: 'isTransition');
        expect(got.durationDays, c['days'], reason: 'durationDays');
      });
    });
  });

  // The point of kMinBridgeDays is that a bridge is never absurd. Sweep every
  // possible hand-off date for two years so a future tweak cannot quietly
  // produce a two-day "seguimiento".
  test(
    'a calendar bridge always stays within bounds and lands on a boundary',
    () {
      for (
        var day = DateTime(2026, 1, 1);
        day.isBefore(DateTime(2028, 1, 1));
        day = day.add(const Duration(days: 1))
      ) {
        final got = nextPeriodRange(
          prevEnd: day,
          mode: kPeriodModeCalendar,
          durationDays: 30,
        );
        final label = day.toIso8601String().substring(0, 10);

        expect(
          got.end.isBefore(got.start),
          isFalse,
          reason: 'inverted at $label',
        );

        if (!got.isTransition) {
          expect(
            got.durationDays,
            inInclusiveRange(28, 31),
            reason: 'month at $label',
          );
          continue;
        }

        expect(
          got.durationDays,
          greaterThanOrEqualTo(kMinBridgeDays),
          reason: 'short at $label',
        );
        expect(
          got.durationDays,
          lessThanOrEqualTo(62),
          reason: 'long at $label',
        );
        // A bridge must land on a month boundary, otherwise the period after it
        // would need bridging too and calendar mode would never settle.
        expect(
          got.end.add(const Duration(days: 1)).day,
          1,
          reason: 'not a boundary at $label',
        );
      }
    },
  );

  test('monthTitle names the month in Spanish', () {
    expect(monthTitle(DateTime(2026, 8, 1)), 'Agosto 2026');
    expect(monthTitle(DateTime(2027, 1, 31)), 'Enero 2027');
  });
}
