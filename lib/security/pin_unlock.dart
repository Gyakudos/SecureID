import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:local_auth/local_auth.dart';

import '../util/ids.dart';
import 'device_key_store.dart';
import 'vault_crypto.dart';
import 'windows_dpapi.dart';

/// The Windows Hello record: the vault key wrapped with a device key that is
/// stored in a DPAPI-sealed file.
class PinVaultRecord {
  const PinVaultRecord({required this.vaultId, required this.wrappedKey});

  /// Base64 of the vault's KDF salt, used to bind this record to one vault.
  final String vaultId;

  /// AES-GCM nonce + ciphertext + MAC of the vault key.
  final List<int> wrappedKey;

  String encode() => jsonEncode({
    'format': 'secureid-pin',
    'version': 1,
    'vaultId': vaultId,
    'wrappedKey': base64Encode(wrappedKey),
  });

  factory PinVaultRecord.decode(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'secureid-pin' ||
        decoded['version'] != 1) {
      throw const FormatException('Not a SecureID Windows Hello record.');
    }
    final vaultId = decoded['vaultId'] as String? ?? '';
    final wrappedKey = base64Decode(decoded['wrappedKey'] as String? ?? '');
    if (vaultId.isEmpty ||
        wrappedKey.length < VaultCrypto.nonceLength + VaultCrypto.macLength) {
      throw const FormatException('The Windows Hello record is incomplete.');
    }
    return PinVaultRecord(vaultId: vaultId, wrappedKey: wrappedKey);
  }
}

/// The platform-specific Windows Hello / PIN integration.
abstract class PinUnlock {
  bool get isPlatformSupported;
  Future<bool> isAvailable();
  Future<bool> authenticate();
  Future<PinVaultRecord> wrapVaultKey({
    required List<int> vaultKey,
    required List<int> salt,
  });
  Future<List<int>> unwrapVaultKey(PinVaultRecord record);
  Future<void> clearDeviceKey();
}

class PinUnlockService implements PinUnlock {
  PinUnlockService({LocalAuthentication? auth, DeviceKeyStore? deviceKeyStore})
    : _auth = auth ?? LocalAuthentication(),
      _deviceKeyStore = deviceKeyStore ?? WindowsDpapiDeviceKeyStore();

  final LocalAuthentication _auth;
  final DeviceKeyStore _deviceKeyStore;

  static const String _aad = 'secureid-pin-v1';
  static final AesGcm _cipher = AesGcm.with256bits();

  @override
  bool get isPlatformSupported => Platform.isWindows;

  @override
  Future<bool> isAvailable() async {
    if (!isPlatformSupported) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    if (!isPlatformSupported) return false;
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock SecureID',
        biometricOnly: false,
        sensitiveTransaction: false,
      );
    } catch (_) {
      return false;
    }
  }

  /// Returns the device key, creating and persisting one if this is the first
  /// time Windows Hello unlock is enabled.
  Future<Uint8List> _ensureDeviceKey() async {
    final existing = await _readDeviceKey();
    if (existing != null) return existing;
    final created = Uint8List.fromList(randomBytes(32));
    await _deviceKeyStore.write(created);
    return created;
  }

  /// Reads the existing device key. Returns null when none has been stored;
  /// this never silently creates a new key, because that would make an
  /// existing Windows Hello record permanently undecryptable.
  Future<Uint8List?> _readDeviceKey() async {
    try {
      final stored = await _deviceKeyStore.read();
      if (stored == null) return null;
      if (stored.length != 32) {
        throw const FormatException('The stored device key is invalid.');
      }
      return Uint8List.fromList(stored);
    } on WindowsDpapiException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clearDeviceKey() => _deviceKeyStore.delete();

  @override
  Future<PinVaultRecord> wrapVaultKey({
    required List<int> vaultKey,
    required List<int> salt,
  }) async {
    final deviceKey = await _ensureDeviceKey();
    final box = await _cipher.encrypt(
      vaultKey,
      secretKey: SecretKey(deviceKey),
      aad: utf8.encode(_aad),
    );
    return PinVaultRecord(
      vaultId: base64Encode(salt),
      wrappedKey: box.concatenation(),
    );
  }

  @override
  Future<List<int>> unwrapVaultKey(PinVaultRecord record) async {
    final deviceKey = await _readDeviceKey();
    if (deviceKey == null) {
      throw const FormatException(
        'The device key for this Windows Hello record is missing.',
      );
    }
    final box = SecretBox.fromConcatenation(
      record.wrappedKey,
      nonceLength: VaultCrypto.nonceLength,
      macLength: VaultCrypto.macLength,
    );
    return _cipher.decrypt(
      box,
      secretKey: SecretKey(deviceKey),
      aad: utf8.encode(_aad),
    );
  }
}
