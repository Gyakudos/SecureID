import 'dart:convert';

import 'package:secure_id/security/pin_unlock.dart';

/// A deterministic device unlock stand-in for tests.
class FakePinUnlock implements PinUnlock {
  FakePinUnlock({
    this.isPlatformSupported = true,
    this.available = true,
    this.cancel = false,
    this.failure,
  });

  @override
  final bool isPlatformSupported;

  bool available;
  bool cancel;
  PinUnlockException? failure;
  bool cleared = false;

  @override
  String get featureName => 'Windows Hello';

  @override
  String get unlockButtonLabel => 'Unlock with Windows Hello';

  @override
  String get availableHint =>
      'Use your PIN, fingerprint or face to unwrap the vault key.';

  @override
  String get unavailableHint =>
      'Windows Hello is not set up on this PC. Add a PIN in Windows Settings '
      'first.';

  @override
  Future<bool> isAvailable() async => available;

  void _checkPrompt() {
    if (cancel) throw const PinUnlockCancelled();
    final error = failure;
    if (error != null) throw error;
  }

  @override
  Future<PinVaultRecord> wrapVaultKey({
    required List<int> vaultKey,
    required List<int> salt,
  }) async {
    _checkPrompt();
    return PinVaultRecord(
      vaultId: base64Encode(salt),
      wrappedKey: List<int>.of(vaultKey),
    );
  }

  @override
  Future<List<int>> unwrapVaultKey(PinVaultRecord record) async {
    _checkPrompt();
    return List<int>.of(record.wrappedKey);
  }

  @override
  Future<void> clearDeviceKey() async {
    cleared = true;
  }
}
