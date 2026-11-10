import 'dart:math';

/// A rough strength estimate for a password the user typed themselves.
class PasswordStrength {
  const PasswordStrength({
    required this.bits,
    required this.label,
    required this.score,
  });

  final double bits;
  final String label;

  /// 0 (very weak) to 4 (very strong).
  final int score;
}

final RegExp _lower = RegExp(r'[a-z]');
final RegExp _upper = RegExp(r'[A-Z]');
final RegExp _digit = RegExp(r'[0-9]');
final RegExp _other = RegExp(r'[^A-Za-z0-9]');
const List<String> _common = [
  'password',
  '123456',
  'qwerty',
  'letmein',
  'admin',
  'welcome',
  'iloveyou',
  'monkey',
  'dragon',
  'abc123',
  '111111',
  '000000',
  'passw0rd',
];

PasswordStrength estimatePasswordStrength(String password) {
  if (password.isEmpty) {
    return const PasswordStrength(bits: 0, label: 'Empty', score: 0);
  }

  var pool = 0;
  if (_lower.hasMatch(password)) pool += 26;
  if (_upper.hasMatch(password)) pool += 26;
  if (_digit.hasMatch(password)) pool += 10;
  if (_other.hasMatch(password)) pool += 32;
  if (pool == 0) pool = 1;

  var bits = password.length * (log(pool) / ln2);
  final unique = password.split('').toSet().length;
  if (unique <= 2) {
    bits *= 0.35;
  } else if (unique < password.length * 0.5) {
    bits *= 0.75;
  }

  final lower = password.toLowerCase();
  if (_common.any(lower.contains)) bits -= 25;

  var runs = 0;
  for (var index = 1; index < password.length; index++) {
    if (password[index] == password[index - 1]) runs++;
  }
  bits -= runs * 1.5;
  if (bits < 0) bits = 0;

  final score = bits < 28
      ? 0
      : bits < 45
      ? 1
      : bits < 65
      ? 2
      : bits < 90
      ? 3
      : 4;
  const labels = ['Very weak', 'Weak', 'Fair', 'Strong', 'Very strong'];
  return PasswordStrength(bits: bits, label: labels[score], score: score);
}
