import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/totp.dart';

/// A generated one-time code plus its remaining lifetime.
class TotpCode {
  const TotpCode({
    required this.code,
    required this.secondsRemaining,
    required this.period,
  });

  final String code;
  final int secondsRemaining;
  final int period;

  double get fraction => period <= 0 ? 0 : secondsRemaining / period;
}

class TotpException implements Exception {
  const TotpException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Normalizes a Base32 secret for storage: uppercase, no spaces, hyphens or
/// padding.
String normalizeTotpSecret(String input) {
  final cleaned = input
      .toUpperCase()
      .replaceAll(RegExp(r'[\s\-_]'), '')
      .replaceAll('=', '');
  if (cleaned.isEmpty) return '';
  if (!RegExp(r'^[A-Z2-7]+$').hasMatch(cleaned)) {
    throw const TotpException('The secret must be Base32 (A-Z and 2-7).');
  }
  return cleaned;
}

/// Decodes RFC 4648 Base32. Throws [TotpException] on invalid input.
Uint8List decodeBase32(String input) {
  final cleaned = normalizeTotpSecret(input);
  if (cleaned.isEmpty) {
    throw const TotpException('Enter the Base32 secret.');
  }
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var buffer = 0;
  var bits = 0;
  final output = <int>[];
  for (final unit in cleaned.codeUnits) {
    final value = alphabet.indexOf(String.fromCharCode(unit));
    if (value < 0) {
      throw const TotpException('The secret is not valid Base32.');
    }
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      output.add((buffer >> bits) & 0xff);
      buffer &= (1 << bits) - 1;
    }
  }
  if (output.isEmpty) {
    throw const TotpException('The secret is too short.');
  }
  return Uint8List.fromList(output);
}

/// Generates the TOTP code for [data] at [at] (defaults to now).
TotpCode generateTotp(TotpData data, {DateTime? at}) {
  final secret = decodeBase32(data.secret);
  if (secret.length < 10) {
    throw const TotpException('The secret is shorter than 10 bytes.');
  }
  if (data.digits < 6 || data.digits > 8) {
    throw const TotpException('Digits must be between 6 and 8.');
  }
  if (data.period < 15 || data.period > 120) {
    throw const TotpException('The period must be between 15 and 120 seconds.');
  }

  final now = at ?? DateTime.now();
  final epochSeconds = now.millisecondsSinceEpoch ~/ 1000;
  var counter = epochSeconds ~/ data.period;
  final message = Uint8List(8);
  for (var index = 7; index >= 0; index--) {
    message[index] = counter & 0xff;
    counter >>= 8;
  }

  final hash = switch (data.algorithm) {
    TotpAlgorithm.sha1 => sha1,
    TotpAlgorithm.sha256 => sha256,
    TotpAlgorithm.sha512 => sha512,
  };
  final digest = Hmac(hash, secret).convert(message).bytes;
  final offset = digest[digest.length - 1] & 0x0f;
  final binary =
      ((digest[offset] & 0x7f) << 24) |
      (digest[offset + 1] << 16) |
      (digest[offset + 2] << 8) |
      digest[offset + 3];
  final code = (binary % pow(10, data.digits).toInt()).toString().padLeft(
    data.digits,
    '0',
  );

  final remaining = data.period - (epochSeconds % data.period);
  return TotpCode(code: code, secondsRemaining: remaining, period: data.period);
}

/// Parses a standard `otpauth://totp/...` enrollment URI.
TotpData parseOtpAuthUri(String raw) {
  final trimmed = raw.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.scheme.toLowerCase() != 'otpauth') {
    throw const TotpException('That QR code is not an otpauth:// link.');
  }
  if (uri.host.toLowerCase() != 'totp') {
    throw const TotpException(
      'Only time-based (TOTP) codes are supported. This looks like a counter-based HOTP code.',
    );
  }

  final label = Uri.decodeComponent(uri.pathSegments.join('/')).trim();
  final query = uri.queryParameters;
  final rawIssuer = (query['issuer'] ?? '').trim();
  String issuer = rawIssuer;
  var accountName = label;
  final colon = label.indexOf(':');
  if (colon >= 0) {
    final labelIssuer = label.substring(0, colon).trim();
    accountName = label.substring(colon + 1).trim();
    if (issuer.isEmpty) issuer = labelIssuer;
  }

  final secret = normalizeTotpSecret(query['secret'] ?? '');
  if (secret.isEmpty) {
    throw const TotpException('The QR code is missing its secret.');
  }
  decodeBase32(secret);

  final digits = int.tryParse(query['digits'] ?? '') ?? 6;
  final period = int.tryParse(query['period'] ?? '') ?? 30;
  if (digits < 6 || digits > 8) {
    throw const TotpException('Only 6 to 8 digit codes are supported.');
  }
  if (period < 15 || period > 120) {
    throw const TotpException('The code period must be 15 to 120 seconds.');
  }

  return TotpData(
    issuer: issuer,
    accountName: accountName,
    secret: secret,
    algorithm: TotpAlgorithmLabel.fromUri(query['algorithm']),
    digits: digits,
    period: period,
  );
}
