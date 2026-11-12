import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'windows_dpapi.dart';

/// Raised when the platform cannot seal local trust records.
class DeviceSealException implements Exception {
  const DeviceSealException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Protects the local trusted-device file with a platform key.
///
/// The trust keys must never be written in plaintext. Windows binds the file to
/// the current user with DPAPI; Android wraps it with a non-authentication
/// Keystore key so a paired transfer can complete while the vault is locked.
abstract class DeviceSeal {
  /// A short platform label for diagnostics.
  String get label;

  Future<List<int>> seal(List<int> data);

  Future<List<int>> unseal(List<int> data);

  /// Deletes the wrapping key, making every existing sealed record unreadable.
  Future<void> deleteKey();
}

/// Returns the best seal for the current platform.
DeviceSeal createDeviceSeal() {
  if (Platform.isWindows) return WindowsDeviceSeal();
  if (Platform.isAndroid) return AndroidDeviceSeal();
  return const UnsupportedDeviceSeal();
}

/// DPAPI seal bound to the current Windows user.
class WindowsDeviceSeal implements DeviceSeal {
  static final Uint8List _entropy = Uint8List.fromList(
    utf8.encode('SecureID trusted devices v1'),
  );

  @override
  String get label => 'Windows DPAPI';

  @override
  Future<List<int>> seal(List<int> data) async {
    if (data.isEmpty) {
      throw const DeviceSealException('Nothing to seal.');
    }
    try {
      return WindowsDpapi.instance.protect(
        Uint8List.fromList(data),
        entropy: _entropy,
      );
    } on WindowsDpapiException catch (exception) {
      throw DeviceSealException(
        'Could not protect the trusted-device list: ${exception.message}',
      );
    }
  }

  @override
  Future<List<int>> unseal(List<int> data) async {
    if (data.isEmpty) {
      throw const DeviceSealException('The sealed record is empty.');
    }
    try {
      return WindowsDpapi.instance.unprotect(
        Uint8List.fromList(data),
        entropy: _entropy,
      );
    } on WindowsDpapiException {
      throw const DeviceSealException(
        'The trusted-device list could not be read on this Windows account.',
      );
    }
  }

  @override
  Future<void> deleteKey() async {
    // DPAPI has no separate key to delete; removing the file is enough.
  }
}

/// Android Keystore seal using a non-authentication AES-256-GCM key.
class AndroidDeviceSeal implements DeviceSeal {
  static const MethodChannel _channel = MethodChannel(
    'com.local.secure_id/trust_store',
  );

  @override
  String get label => 'Android Keystore';

  @override
  Future<List<int>> seal(List<int> data) async {
    if (data.isEmpty) {
      throw const DeviceSealException('Nothing to seal.');
    }
    try {
      final result = await _channel.invokeMethod<Uint8List>('seal', {
        'data': Uint8List.fromList(data),
      });
      if (result == null || result.isEmpty) {
        throw const DeviceSealException('The phone returned an empty record.');
      }
      return result;
    } on PlatformException catch (exception) {
      throw DeviceSealException(
        exception.message ?? 'Could not protect the trusted-device list.',
      );
    }
  }

  @override
  Future<List<int>> unseal(List<int> data) async {
    if (data.isEmpty) {
      throw const DeviceSealException('The sealed record is empty.');
    }
    try {
      final result = await _channel.invokeMethod<Uint8List>('unseal', {
        'data': Uint8List.fromList(data),
      });
      if (result == null) {
        throw const DeviceSealException(
          'The trusted-device list could not be read.',
        );
      }
      return result;
    } on PlatformException catch (exception) {
      throw DeviceSealException(
        exception.message ?? 'The trusted-device list could not be read.',
      );
    }
  }

  @override
  Future<void> deleteKey() async {
    try {
      await _channel.invokeMethod<void>('deleteKey');
    } on PlatformException {
      // A missing key is already the desired state.
    }
  }
}

/// Used on platforms without a supported keystore.
class UnsupportedDeviceSeal implements DeviceSeal {
  const UnsupportedDeviceSeal();

  @override
  String get label => 'Not available';

  @override
  Future<List<int>> seal(List<int> data) async {
    throw const DeviceSealException(
      'Trusted devices are not supported on this platform.',
    );
  }

  @override
  Future<List<int>> unseal(List<int> data) async {
    throw const DeviceSealException(
      'Trusted devices are not supported on this platform.',
    );
  }

  @override
  Future<void> deleteKey() async {}
}
