import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pin_unlock.dart';

/// The biometric state reported by Android.
enum BiometricAvailability {
  ok,
  noHardware,
  noneEnrolled,
  hardwareUnavailable,
  securityUpdateRequired,
  unsupported,
  unknown;

  static BiometricAvailability parse(String? value) {
    return switch (value) {
      'ok' => BiometricAvailability.ok,
      'no_hardware' => BiometricAvailability.noHardware,
      'none_enrolled' => BiometricAvailability.noneEnrolled,
      'hw_unavailable' => BiometricAvailability.hardwareUnavailable,
      'security_update_required' =>
        BiometricAvailability.securityUpdateRequired,
      'unsupported' => BiometricAvailability.unsupported,
      _ => BiometricAvailability.unknown,
    };
  }
}

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
    return await availability() == BiometricAvailability.ok;
  }

  /// Asks Android for the exact biometric state.
  ///
  /// [isAvailable] collapses every failure to `false`, which makes a
  /// temporary hardware problem look like a missing fingerprint. The richer
  /// answer lets the UI explain what is actually wrong.
  Future<BiometricAvailability> availability() async {
    if (!isPlatformSupported) return BiometricAvailability.unsupported;
    try {
      final status = await _channel.invokeMethod<String>('availability');
      return BiometricAvailability.parse(status);
    } on MissingPluginException {
      return BiometricAvailability.unsupported;
    } on PlatformException catch (exception) {
      debugPrint(
        'SecureID biometric availability failed: '
        '${exception.code} ${exception.message}',
      );
      return BiometricAvailability.unknown;
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

  /// The Keystore key requires a fresh biometric prompt, so the vault key
  /// cannot be rewrapped silently after receiving a different vault.
  @override
  bool get supportsSilentRewrap => false;

  @override
  Future<PinVaultRecord?> rewrapVaultKey({
    required List<int> vaultKey,
    required List<int> salt,
  }) async => null;

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

  /// Codes that mean the stored record can never be used again. Everything
  /// else is treated as temporary so a lockout or a busy prompt does not throw
  /// away a working biometric enrolment.
  static const Set<String> _permanentCodes = {
    'key_invalidated',
    'key_missing',
    'bad_data',
    'bad_args',
  };

  static String _messageFor(String code, String? fallback) {
    final message = switch (code) {
      'none_enrolled' =>
        'No fingerprint or face is enrolled on this phone. Add one in Android '
            'Settings first.',
      'no_hardware' => 'This phone does not have biometric hardware.',
      'hw_unavailable' =>
        'Biometric hardware is temporarily unavailable. Try again.',
      'security_update_required' =>
        'Your phone needs a security update before biometrics can be used.',
      'locked_out' =>
        'Too many attempts. Use your master password, then try again later.',
      'locked_out_permanent' =>
        'Biometrics are locked. Use your master password, then re-enable '
            'biometric unlock.',
      'busy' => 'Another biometric prompt is already open.',
      'no_device_credential' =>
        'Set a screen lock on this phone, then add a fingerprint or face.',
      _ => null,
    };
    if (message != null) return message;
    final trimmed = fallback?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return 'Biometric unlock failed. Use your master password.';
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
      final code = exception.code;
      debugPrint(
        'SecureID biometric $method failed: $code ${exception.message}',
      );
      if (code == 'cancelled') throw const PinUnlockCancelled();
      throw PinUnlockException(
        _messageFor(code, exception.message),
        permanent: _permanentCodes.contains(code),
      );
    } on MissingPluginException {
      throw const PinUnlockException(
        'Biometric unlock is not available in this build.',
      );
    }
  }
}
