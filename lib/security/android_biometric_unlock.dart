import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'pin_unlock.dart';

/// Android biometric unlock backed by a hardware-protected Keystore key.
///
/// The vault key is encrypted with an AES-256-GCM key that lives inside the
/// Android Keystore. The key is created with user authentication required, so
/// the ciphertext can only be opened after a successful fingerprint or face
/// prompt. Only the ciphertext is written to `vault.pin.json`; neither the
/// Keystore key nor the vault key ever reaches the disk in plaintext.
class AndroidBiometricUnlock implements PinUnlock {
  AndroidBiometricUnlock({MethodChannel? channel, bool? platformSupported})
    : _channel = channel ?? const MethodChannel(channelName),
      _platformSupported = platformSupported ?? Platform.isAndroid;

  /// Must match the channel name registered by `MainActivity`.
  static const String channelName = 'com.local.secure_id/biometric';

  /// The Keystore alias. A device holds a single vault, so one alias is enough.
  static const String keyAlias = 'secureid_vault_key';

  final MethodChannel _channel;
  final bool _platformSupported;

  @override
  bool get isPlatformSupported => _platformSupported;

  @override
  String get featureName => 'Biometric unlock';

  @override
  String get unlockButtonLabel => 'Unlock with biometrics';

  @override
  String get availableHint =>
      'Use your fingerprint or face to unwrap the vault key. Your master '
      'password always remains valid.';

  @override
  String get unavailableHint =>
      'No fingerprint or face is enrolled on this phone. Add one in Android '
      'Settings first.';

  @override
  Future<bool> isAvailable() async {
    if (!isPlatformSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<PinVaultRecord> wrapVaultKey({
    required List<int> vaultKey,
    required List<int> salt,
  }) async {
    final wrapped = await _invokeBytes('wrap', {
      'alias': keyAlias,
      'key': Uint8List.fromList(vaultKey),
    });
    if (wrapped.length <= 12) {
      throw const PinUnlockException(
        'Android returned an incomplete biometric record.',
      );
    }
    return PinVaultRecord(vaultId: base64Encode(salt), wrappedKey: wrapped);
  }

  @override
  Future<List<int>> unwrapVaultKey(PinVaultRecord record) {
    return _invokeBytes('unwrap', {
      'alias': keyAlias,
      'data': Uint8List.fromList(record.wrappedKey),
    });
  }

  @override
  Future<void> clearDeviceKey() async {
    try {
      await _channel.invokeMethod<void>('deleteKey', {'alias': keyAlias});
    } on MissingPluginException {
      // Nothing was stored by this build.
    } on PlatformException {
      // The record is already gone; the stale key is harmless.
    }
  }

  Future<Uint8List> _invokeBytes(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>(method, arguments);
      if (result == null || result.isEmpty) {
        throw const PinUnlockException('Android returned no key data.');
      }
      return result;
    } on PlatformException catch (exception) {
      if (exception.code == 'cancelled') throw const PinUnlockCancelled();
      throw PinUnlockException(
        exception.message ?? 'Android biometric unlock failed.',
      );
    } on MissingPluginException {
      throw const PinUnlockException(
        'Biometric unlock is not available in this build.',
      );
    }
  }
}
