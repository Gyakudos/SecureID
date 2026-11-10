import 'dart:convert';
import 'dart:math';

final Random _secureRandom = Random.secure();

/// A URL-safe random identifier. 16 bytes is 128 bits of entropy.
String newId([int bytes = 16]) {
  final data = List<int>.generate(bytes, (_) => _secureRandom.nextInt(256));
  return base64UrlEncode(data).replaceAll('=', '');
}

/// Cryptographically secure random bytes for salts and nonces.
List<int> randomBytes(int count) =>
    List<int>.generate(count, (_) => _secureRandom.nextInt(256));
