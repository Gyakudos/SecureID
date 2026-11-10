import 'dart:math';

/// Generates random passwords from cryptographically secure random bytes.
class PasswordGenerator {
  const PasswordGenerator._();

  static const String lowercase = 'abcdefghijklmnopqrstuvwxyz';
  static const String uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String digits = '0123456789';
  static const String symbols = r'!@#$%^&*()-_=+[]{};:,.?/';
  static const String ambiguous = 'Il1O0o';

  static final Random _secure = Random.secure();

  /// Builds a password that contains at least one character from every
  /// selected class. Throws [ArgumentError] when [length] is smaller than the
  /// number of selected classes.
  static String generate({
    int length = 20,
    bool upper = true,
    bool lower = true,
    bool useDigits = true,
    bool useSymbols = true,
    bool excludeAmbiguous = false,
    Random? random,
  }) {
    final rng = random ?? _secure;
    String clean(String pool) {
      if (!excludeAmbiguous) return pool;
      return pool
          .split('')
          .where((character) => !ambiguous.contains(character))
          .join();
    }

    final pools = <String>[
      if (lower) clean(lowercase),
      if (upper) clean(uppercase),
      if (useDigits) clean(digits),
      if (useSymbols) clean(symbols),
    ].where((pool) => pool.isNotEmpty).toList(growable: false);

    if (pools.isEmpty) {
      throw ArgumentError('Select at least one character type.');
    }
    if (length < pools.length) {
      throw ArgumentError(
        'The password must be at least ${pools.length} characters long.',
      );
    }

    final characters = <String>[
      for (final pool in pools) pool[rng.nextInt(pool.length)],
    ];
    final all = pools.join();
    while (characters.length < length) {
      characters.add(all[rng.nextInt(all.length)]);
    }

    for (var index = characters.length - 1; index > 0; index--) {
      final swapWith = rng.nextInt(index + 1);
      final value = characters[index];
      characters[index] = characters[swapWith];
      characters[swapWith] = value;
    }
    return characters.join();
  }
}
