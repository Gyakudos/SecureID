import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/device_login.dart';
import 'package:secure_id/security/quick_unlock.dart';

void main() {
  final vaultKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final vaultSalt = Uint8List.fromList(List<int>.generate(16, (i) => 200 + i));

  test('validates six-digit PINs', () {
    expect(QuickUnlockCrypto.isValidPin('123456'), isTrue);
    expect(QuickUnlockCrypto.isValidPin('000000'), isTrue);
    expect(QuickUnlockCrypto.isValidPin('12345'), isFalse);
    expect(QuickUnlockCrypto.isValidPin('1234567'), isFalse);
    expect(QuickUnlockCrypto.isValidPin('12345a'), isFalse);
    expect(QuickUnlockCrypto.pinLength, 6);
  });

  test('validates patterns with at least four unique dots', () {
    expect(QuickUnlockCrypto.isValidPattern([0, 1, 2, 5]), isTrue);
    expect(QuickUnlockCrypto.isValidPattern([0, 1, 2]), isFalse);
    expect(QuickUnlockCrypto.isValidPattern([0, 1, 1, 2]), isFalse);
    expect(QuickUnlockCrypto.isValidPattern([0, 1, 2, 9]), isFalse);
    expect(QuickUnlockCrypto.patternMinDots, 4);
  });

  test('builds a stable pattern secret', () {
    expect(QuickUnlockCrypto.patternSecret([0, 4, 8]), '0-4-8');
  });

  test('wraps and unwraps the vault key with a PIN', () async {
    final record = await QuickUnlockCrypto.create(
      vaultKey: vaultKey,
      vaultSalt: vaultSalt,
      style: PasswordStyle.pin,
      secret: '123456',
      config: QuickUnlockConfig.test,
    );

    expect(record.vaultId, base64Encode(vaultSalt));
    expect(record.style, PasswordStyle.pin);
    expect(record.failedAttempts, 0);
    expect(record.wrappedKey.length, greaterThan(28));

    final opened = await QuickUnlockCrypto.unlock(record, '123456');
    expect(opened, vaultKey);
  });

  test('rejects the wrong PIN', () async {
    final record = await QuickUnlockCrypto.create(
      vaultKey: vaultKey,
      vaultSalt: vaultSalt,
      style: PasswordStyle.pin,
      secret: '123456',
      config: QuickUnlockConfig.test,
    );

    await expectLater(
      QuickUnlockCrypto.unlock(record, '654321'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('wraps and unwraps the vault key with a pattern', () async {
    final dots = [0, 1, 2, 5, 8];
    final record = await QuickUnlockCrypto.create(
      vaultKey: vaultKey,
      vaultSalt: vaultSalt,
      style: PasswordStyle.pattern,
      secret: QuickUnlockCrypto.patternSecret(dots),
      config: QuickUnlockConfig.test,
    );

    expect(record.style, PasswordStyle.pattern);
    final opened = await QuickUnlockCrypto.unlock(
      record,
      QuickUnlockCrypto.patternSecret(dots),
    );
    expect(opened, vaultKey);
  });

  test('round-trips the stored record', () async {
    final record = await QuickUnlockCrypto.create(
      vaultKey: vaultKey,
      vaultSalt: vaultSalt,
      style: PasswordStyle.pattern,
      secret: '0-1-2-5',
      config: QuickUnlockConfig.test,
    ).then((value) => value.copyWith(failedAttempts: 2));

    final restored = QuickUnlockRecord.decode(record.encode());
    expect(restored.vaultId, record.vaultId);
    expect(restored.style, record.style);
    expect(restored.salt, record.salt);
    expect(restored.wrappedKey, record.wrappedKey);
    expect(restored.failedAttempts, 2);
    expect(restored.config.memory, QuickUnlockConfig.test.memory);
    expect(restored.config.iterations, QuickUnlockConfig.test.iterations);

    final opened = await QuickUnlockCrypto.unlock(restored, '0-1-2-5');
    expect(opened, vaultKey);
  });

  test('rejects a record with the wrong format', () {
    expect(
      () => QuickUnlockRecord.decode('{"format":"other","version":1}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects an incomplete record', () {
    expect(
      () => QuickUnlockRecord.decode(
        jsonEncode({
          'format': 'secureid-quick',
          'version': 1,
          'vaultId': 'abc',
          'style': 'pin',
          'kdf': {
            'salt': base64Encode([1, 2, 3]),
            'memory': 64,
            'iterations': 1,
            'parallelism': 1,
          },
          'wrappedKey': base64Encode([1, 2, 3]),
        }),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('limits quick unlock to five attempts', () {
    expect(QuickUnlockCrypto.maxAttempts, 5);
  });
}
