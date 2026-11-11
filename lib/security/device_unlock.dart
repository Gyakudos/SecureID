import 'dart:io';

import 'android_biometric_unlock.dart';
import 'pin_unlock.dart';

/// Builds the unlock implementation for the current platform.
///
/// Android gets biometric unlock backed by the Keystore; Windows gets Windows
/// Hello with a DPAPI-sealed device key. Other platforms keep the master
/// password only.
PinUnlock createDeviceUnlock() {
  if (Platform.isAndroid) return AndroidBiometricUnlock();
  return PinUnlockService();
}
