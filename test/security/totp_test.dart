import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/totp.dart';
import 'package:secure_id/security/totp.dart';

String base32Encode(List<int> data) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var buffer = 0;
  var bits = 0;
  final output = StringBuffer();
  for (final byte in data) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      output.write(alphabet[(buffer >> bits) & 0x1f]);
      buffer &= (1 << bits) - 1;
    }
  }
  if (bits > 0) {
    output.write(alphabet[(buffer << (5 - bits)) & 0x1f]);
  }
  return output.toString();
}

void main() {
  group('RFC 6238 vectors', () {
    const times = [
      59,
      1111111109,
      1111111111,
      1234567890,
      2000000000,
      20000000000,
    ];

    test('SHA-1', () {
      final secret = base32Encode('12345678901234567890'.codeUnits);
      const expected = [
        '94287082',
        '07081804',
        '14050471',
        '89005924',
        '69279037',
        '65353130',
      ];
      for (var index = 0; index < times.length; index++) {
        final data = TotpData(
          secret: secret,
          digits: 8,
          algorithm: TotpAlgorithm.sha1,
        );
        final code = generateTotp(
          data,
          at: DateTime.fromMillisecondsSinceEpoch(times[index] * 1000),
        );
        expect(code.code, expected[index], reason: 't=${times[index]}');
      }
    });

    test('SHA-256', () {
      final secret = base32Encode('12345678901234567890123456789012'.codeUnits);
      const expected = [
        '46119246',
        '68084774',
        '67062674',
        '91819424',
        '90698825',
        '77737706',
      ];
      for (var index = 0; index < times.length; index++) {
        final data = TotpData(
          secret: secret,
          digits: 8,
          algorithm: TotpAlgorithm.sha256,
        );
        final code = generateTotp(
          data,
          at: DateTime.fromMillisecondsSinceEpoch(times[index] * 1000),
        );
        expect(code.code, expected[index], reason: 't=${times[index]}');
      }
    });

    test('SHA-512', () {
      final secret = base32Encode(
        '1234567890123456789012345678901234567890123456789012345678901234'
            .codeUnits,
      );
      const expected = [
        '90693936',
        '25091201',
        '99943326',
        '93441116',
        '38618901',
        '47863826',
      ];
      for (var index = 0; index < times.length; index++) {
        final data = TotpData(
          secret: secret,
          digits: 8,
          algorithm: TotpAlgorithm.sha512,
        );
        final code = generateTotp(
          data,
          at: DateTime.fromMillisecondsSinceEpoch(times[index] * 1000),
        );
        expect(code.code, expected[index], reason: 't=${times[index]}');
      }
    });
  });

  test('normalizes Base32 secrets', () {
    expect(normalizeTotpSecret('jbsw y3dp ehpk 3pxp'), 'JBSWY3DPEHPK3PXP');
    expect(normalizeTotpSecret('JBSW-Y3DP-EHPK-3PXP=='), 'JBSWY3DPEHPK3PXP');
    expect(
      () => normalizeTotpSecret('not base32!'),
      throwsA(isA<TotpException>()),
    );
  });

  test('parses otpauth URIs', () {
    final data = parseOtpAuthUri(
      'otpauth://totp/GitHub:alice%40example.com'
      '?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA256'
      '&digits=6&period=30',
    );
    expect(data.issuer, 'GitHub');
    expect(data.accountName, 'alice@example.com');
    expect(data.secret, 'JBSWY3DPEHPK3PXP');
    expect(data.algorithm, TotpAlgorithm.sha256);
    expect(data.digits, 6);
    expect(data.period, 30);
  });

  test('rejects non-TOTP URIs', () {
    expect(
      () => parseOtpAuthUri('https://example.com'),
      throwsA(isA<TotpException>()),
    );
    expect(
      () => parseOtpAuthUri('otpauth://hotp/a?secret=JBSWY3DPEHPK3PXP'),
      throwsA(isA<TotpException>()),
    );
  });

  test('reports the remaining lifetime', () {
    final data = TotpData(
      secret: base32Encode('12345678901234567890'.codeUnits),
      digits: 6,
      period: 30,
    );
    final code = generateTotp(
      data,
      at: DateTime.fromMillisecondsSinceEpoch(60 * 1000),
    );
    expect(code.secondsRemaining, 30);
    expect(code.fraction, 1);
  });
}
