import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/security/windows_dpapi.dart';

void main() {
  if (!Platform.isWindows) {
    test('Windows DPAPI', () {}, skip: 'DPAPI is Windows-only.');
    return;
  }

  final entropy = Uint8List.fromList('SecureID device key v1'.codeUnits);

  test('round-trips a key through DPAPI', () {
    final key = Uint8List.fromList(List<int>.generate(32, (index) => index));

    final sealed = WindowsDpapi.instance.protect(key, entropy: entropy);
    expect(sealed, isNotEmpty);
    expect(sealed, isNot(equals(key)));

    final opened = WindowsDpapi.instance.unprotect(sealed, entropy: entropy);
    expect(opened, equals(key));
  });

  test('rejects the wrong entropy', () {
    final key = Uint8List.fromList(List<int>.generate(32, (index) => index));
    final sealed = WindowsDpapi.instance.protect(key, entropy: entropy);

    expect(
      () => WindowsDpapi.instance.unprotect(
        sealed,
        entropy: Uint8List.fromList('wrong entropy'.codeUnits),
      ),
      throwsA(isA<WindowsDpapiException>()),
    );
  });

  test('rejects an empty buffer', () {
    expect(
      () => WindowsDpapi.instance.protect(Uint8List(0)),
      throwsA(isA<WindowsDpapiException>()),
    );
  });
}
