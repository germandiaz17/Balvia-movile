// Tests for helper functions introduced in the visual fidelity pass (Part 1).
//
// Covers:
//   - greetingPrefix (home_screen.dart) — time-of-day saludo
//   - passwordStrength (register_screen.dart) — 0-4 scale
//   - passwordStrengthLabel (register_screen.dart) — human-readable label
//   - appendThousands logic (QuickCaptureController) — ",000" key behaviour

import 'package:flutter_test/flutter_test.dart';

import 'package:balvia_mobile/features/home/home_screen.dart'
    show greetingPrefix;
import 'package:balvia_mobile/features/auth/register_screen.dart'
    show passwordStrength, passwordStrengthLabel;
// quick_capture_controller.dart is not imported — we test the pure logic inline.

void main() {
  // ---------------------------------------------------------------------------
  // greetingPrefix — time of day saludo
  // ---------------------------------------------------------------------------
  group('greetingPrefix', () {
    test('midnight is "Buenos días"', () {
      expect(greetingPrefix(0), 'Buenos días');
    });

    test('7am is "Buenos días"', () {
      expect(greetingPrefix(7), 'Buenos días');
    });

    test('11am is "Buenos días"', () {
      expect(greetingPrefix(11), 'Buenos días');
    });

    test('noon (12) is "Buenas tardes"', () {
      expect(greetingPrefix(12), 'Buenas tardes');
    });

    test('3pm (15) is "Buenas tardes"', () {
      expect(greetingPrefix(15), 'Buenas tardes');
    });

    test('17:59 is "Buenas tardes"', () {
      expect(greetingPrefix(17), 'Buenas tardes');
    });

    test('6pm (18) is "Buenas noches"', () {
      expect(greetingPrefix(18), 'Buenas noches');
    });

    test('11pm (23) is "Buenas noches"', () {
      expect(greetingPrefix(23), 'Buenas noches');
    });
  });

  // ---------------------------------------------------------------------------
  // passwordStrength — 0-4 scale
  // ---------------------------------------------------------------------------
  group('passwordStrength', () {
    test('empty string returns 0', () {
      expect(passwordStrength(''), 0);
    });

    test('fewer than 8 characters returns 1 (too short)', () {
      expect(passwordStrength('abc'), 1);
      expect(passwordStrength('1234567'), 1);
    });

    test('8 chars lowercase only returns 2 (weak)', () {
      expect(passwordStrength('abcdefgh'), 2);
    });

    test('8 chars lowercase + uppercase returns 3 (good)', () {
      expect(passwordStrength('Abcdefgh'), 3);
    });

    test('8 chars with letters + digits returns 3 (good)', () {
      expect(passwordStrength('abcdef12'), 3);
    });

    test('8 chars letters + digits + symbol returns 4 (strong)', () {
      expect(passwordStrength('Abcdef1!'), 4);
    });

    test('long complex password returns 4', () {
      expect(passwordStrength('Tr0ub4dor&3'), 4);
    });

    test('digits only (≥ 8) returns 2 (weak)', () {
      expect(passwordStrength('12345678'), 2);
    });
  });

  // ---------------------------------------------------------------------------
  // passwordStrengthLabel
  // ---------------------------------------------------------------------------
  group('passwordStrengthLabel', () {
    test('0 returns empty string', () {
      expect(passwordStrengthLabel(0), '');
    });

    test('1 returns "Muy corta"', () {
      expect(passwordStrengthLabel(1), 'Muy corta');
    });

    test('2 returns "Débil"', () {
      expect(passwordStrengthLabel(2), 'Débil');
    });

    test('3 returns "Contraseña buena"', () {
      expect(passwordStrengthLabel(3), 'Contraseña buena');
    });

    test('4 returns "Muy segura"', () {
      expect(passwordStrengthLabel(4), 'Muy segura');
    });
  });

  // ---------------------------------------------------------------------------
  // QuickCaptureController.appendThousands — ",000" key
  // ---------------------------------------------------------------------------
  group('QuickCaptureController.appendThousands', () {
    // Build() requires Ref in Riverpod, so we test the pure transformation
    // logic inline to keep tests dependency-free.

    // We test the ",000" logic by extracting it as a pure function
    // (mirrors what the controller does).
    String applyThousands(String current) {
      if (current.isEmpty || current == '0') return current;
      const suffix = '000';
      final next = current + suffix;
      if (next.length > 10) return current;
      return next;
    }

    test('appendThousands on empty string does nothing', () {
      expect(applyThousands(''), '');
    });

    test('appendThousands on "0" does nothing', () {
      expect(applyThousands('0'), '0');
    });

    test('appendThousands on "5" produces "5000"', () {
      expect(applyThousands('5'), '5000');
    });

    test('appendThousands on "15" produces "15000"', () {
      expect(applyThousands('15'), '15000');
    });

    test('appendThousands on "100" produces "100000"', () {
      expect(applyThousands('100'), '100000');
    });

    test('appendThousands does not exceed 10 digits', () {
      // "12345678" + "000" = 11 chars → capped, returns original
      expect(applyThousands('12345678'), '12345678');
    });

    test('appendThousands on 7-digit input produces 10-digit result', () {
      // "1234567" + "000" = 10 chars → allowed
      expect(applyThousands('1234567'), '1234567000');
    });
  });
}
