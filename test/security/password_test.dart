import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/security/password_generator.dart';
import 'package:secure_id/security/password_strength.dart';

void main() {
  test('generates a password of the requested length', () {
    final password = PasswordGenerator.generate(length: 32);
    expect(password, hasLength(32));
  });

  test('includes every selected character class', () {
    for (var run = 0; run < 50; run++) {
      final password = PasswordGenerator.generate(
        length: 16,
        upper: true,
        lower: true,
        useDigits: true,
        useSymbols: true,
      );
      expect(password.contains(RegExp(r'[A-Z]')), isTrue);
      expect(password.contains(RegExp(r'[a-z]')), isTrue);
      expect(password.contains(RegExp(r'[0-9]')), isTrue);
      expect(password.contains(RegExp(r'[^A-Za-z0-9]')), isTrue);
    }
  });

  test('honours disabled character classes', () {
    final password = PasswordGenerator.generate(
      length: 20,
      upper: false,
      lower: false,
      useDigits: true,
      useSymbols: false,
    );
    expect(password.contains(RegExp(r'^[0-9]+$')), isTrue);
  });

  test('can exclude ambiguous characters', () {
    for (var run = 0; run < 40; run++) {
      final password = PasswordGenerator.generate(
        length: 40,
        excludeAmbiguous: true,
      );
      for (final character in PasswordGenerator.ambiguous.split('')) {
        expect(password.contains(character), isFalse);
      }
    }
  });

  test('throws when no character class is selected', () {
    expect(
      () => PasswordGenerator.generate(
        upper: false,
        lower: false,
        useDigits: false,
        useSymbols: false,
      ),
      throwsArgumentError,
    );
  });

  test('estimates stronger passwords as stronger', () {
    expect(estimatePasswordStrength('').score, 0);
    expect(estimatePasswordStrength('password').score, lessThan(2));
    expect(
      estimatePasswordStrength(r'vN7$qZ2!tR9#xL4@wK8&').score,
      greaterThanOrEqualTo(3),
    );
  });
}
