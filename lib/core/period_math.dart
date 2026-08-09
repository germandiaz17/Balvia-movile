import '../data/models/user_settings.dart';

/// Date arithmetic for tracking periods, mirroring `internal/domain/period.go`
/// in the backend.
///
/// This is a deliberate duplication. The backend remains the authority — it is
/// what actually creates periods — but the settings screen has to answer "what
/// happens if I switch?" *before* anything is saved, and a dry-run endpoint
/// would be a lot of API surface for ten lines of pure date math. The Go tests
/// and the Dart tests run the same table of cases; if this logic ever grows
/// past trivial, move it to the server instead of letting the copies drift.

/// Floor for a transition period, matching `minBridgeDays` in the backend.
/// Below this, the leftover is absorbed into the following month rather than
/// becoming a period of its own.
const kMinBridgeDays = 15;

/// An inclusive [start, end] date range, plus whether it is a one-off bridge.
class PeriodRange {
  const PeriodRange({
    required this.start,
    required this.end,
    this.isTransition = false,
  });

  final DateTime start;
  final DateTime end;
  final bool isTransition;

  /// Inclusive length in days: a single-day range is 1, not 0.
  int get durationDays => end.difference(start).inDays + 1;
}

/// The period that follows one ending on [prevEnd].
///
/// Rolling mode chains a block of [durationDays]. Calendar mode returns a real
/// calendar month, except on the first hop after a switch, where [prevEnd]
/// rarely lands on a month boundary and the gap has to be bridged.
PeriodRange nextPeriodRange({
  required DateTime prevEnd,
  required String mode,
  required int durationDays,
}) {
  final start = _dayStart(prevEnd).add(const Duration(days: 1));

  if (mode != kPeriodModeCalendar) {
    return PeriodRange(
      start: start,
      end: start.add(Duration(days: durationDays - 1)),
    );
  }

  // Already on a month boundary: a clean month, no bridging needed.
  if (start.day == 1) {
    return PeriodRange(start: start, end: _endOfMonth(start));
  }

  return PeriodRange(start: start, end: _bridgeEnd(start), isTransition: true);
}

/// Where a transition period stops: the end of [start]'s own month when that
/// leaves a usable stretch, otherwise the end of the month after.
DateTime _bridgeEnd(DateTime start) {
  final end = _endOfMonth(start);
  if (end.difference(start).inDays + 1 < kMinBridgeDays) {
    return _endOfMonth(DateTime(start.year, start.month + 1, 1));
  }
  return end;
}

/// Last day of [d]'s month. DateTime normalises a month overflow, so day 0 of
/// the next month is the last day of this one — and it stays leap-safe.
DateTime _endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

const _monthNamesCapitalized = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

/// "Agosto 2026" — the title a whole calendar month gets instead of a range.
String monthTitle(DateTime d) =>
    '${_monthNamesCapitalized[d.month - 1]} ${d.year}';
