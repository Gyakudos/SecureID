import 'dart:convert';

import 'package:secure_id/security/pin_unlock.dart';

/// A deterministic Windows Hello stand-in for tests.
class FakePinUnlock implements PinUnlock {
  FakePinUnlock({
    this.isPlatformSupported = true,
    this.available = true,
    this.authenticated = true,
  });

  @override
  final bool isPlatformSupported;

  bool available;
  bool authenticated;
  bool cleared = false;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate() async => authenticated;

  @override
  Future<PinVaultRecord> wrapVaultKey({
    required List<int> vaultKey,
    required List<int> salt,
  }) async {
    return PinVaultRecord(
      vaultId: base64Encode(salt),
      wrappedKey: List<int>.of(vaultKey),
    );
  }

  @override
  Future<List<int>> unwrapVaultKey(PinVaultRecord record) async =>
      List<int>.of(record.wrappedKey);

  @override
  Future<void> clearDeviceKey() async {
    cleared = true;
  }
}
