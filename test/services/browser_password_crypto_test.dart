import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/services/browser_password_crypto.dart';

void main() {
  test('decrypts a v10 AES-256-GCM password blob', () async {
    final key = List<int>.generate(32, (index) => index);
    final nonce = List<int>.generate(12, (index) => 200 + index);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode('correct horse'),
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    final blob = Uint8List.fromList(<int>[
      ...ascii.encode('v10'),
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);

    final result = await decryptChromiumPassword(blob, key: key);

    expect(result.state, ChromiumPasswordState.decrypted);
    expect(result.password, 'correct horse');
  });

  test('reports app-bound encryption instead of guessing', () async {
    final blob = Uint8List.fromList(<int>[...ascii.encode('v20'), 1, 2, 3]);

    final result = await decryptChromiumPassword(
      blob,
      key: List<int>.filled(32, 0),
    );

    expect(result.state, ChromiumPasswordState.appBound);
  });

  test('falls back to the legacy per-password DPAPI blob', () async {
    final blob = Uint8List.fromList(<int>[1, 2, 3, 4]);

    final result = await decryptChromiumPassword(
      blob,
      key: null,
      legacyUnprotect: (data) => utf8.encode('legacy secret'),
    );

    expect(result.state, ChromiumPasswordState.decrypted);
    expect(result.password, 'legacy secret');
  });

  test('fails safely when a v10 key is missing', () async {
    final blob = Uint8List.fromList(<int>[
      ...ascii.encode('v10'),
      ...List<int>.filled(40, 0),
    ]);

    final result = await decryptChromiumPassword(blob, key: null);

    expect(result.state, ChromiumPasswordState.failed);
    expect(result.password, isNull);
  });

  test('fails safely for an empty blob', () async {
    final result = await decryptChromiumPassword(
      Uint8List(0),
      key: List<int>.filled(32, 0),
    );

    expect(result.state, ChromiumPasswordState.failed);
  });
}
