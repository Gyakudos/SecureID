import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// The outcome of reading one Chromium password blob.
enum ChromiumPasswordState {
  /// The value was decrypted successfully.
  decrypted,

  /// The value uses app-bound encryption, which another application cannot
  /// open. The browser must be asked to export a CSV instead.
  appBound,

  /// The value is present but could not be decrypted.
  failed,
}

class ChromiumPasswordResult {
  const ChromiumPasswordResult(this.state, [this.password]);

  final ChromiumPasswordState state;
  final String? password;
}

/// Decrypts a Chromium `password_value` column.
///
/// Chromium stores passwords as `v10`/`v11` AES-256-GCM blobs whose key lives
/// in `Local State` (`os_crypt.encrypted_key`, sealed with DPAPI on Windows).
/// Older profiles store a bare DPAPI blob instead. Newer Chrome and Edge builds
/// may use `v20` app-bound encryption, which is deliberately unreadable from
/// other processes; [ChromiumPasswordState.appBound] lets the UI explain that
/// and point at the browser's CSV export instead.
Future<ChromiumPasswordResult> decryptChromiumPassword(
  Uint8List blob, {
  required List<int>? key,
  List<int> Function(Uint8List data)? legacyUnprotect,
}) async {
  if (blob.isEmpty) {
    return const ChromiumPasswordResult(ChromiumPasswordState.failed);
  }

  final prefix = blob.length >= 3
      ? ascii.decode(blob.sublist(0, 3), allowInvalid: true)
      : '';

  if (prefix == 'v10' || prefix == 'v11') {
    if (key == null || key.length != 32) {
      return const ChromiumPasswordResult(ChromiumPasswordState.failed);
    }
    if (blob.length < 3 + 12 + 16) {
      return const ChromiumPasswordResult(ChromiumPasswordState.failed);
    }
    try {
      final nonce = blob.sublist(3, 15);
      final ciphertext = blob.sublist(15, blob.length - 16);
      final mac = blob.sublist(blob.length - 16);
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKey(key),
      );
      return ChromiumPasswordResult(
        ChromiumPasswordState.decrypted,
        utf8.decode(clear),
      );
    } catch (_) {
      return const ChromiumPasswordResult(ChromiumPasswordState.failed);
    }
  }

  if (prefix == 'v20' || prefix == 'v21') {
    return const ChromiumPasswordResult(ChromiumPasswordState.appBound);
  }

  if (legacyUnprotect == null) {
    return const ChromiumPasswordResult(ChromiumPasswordState.failed);
  }
  try {
    final clear = legacyUnprotect(blob);
    return ChromiumPasswordResult(
      ChromiumPasswordState.decrypted,
      utf8.decode(clear),
    );
  } catch (_) {
    return const ChromiumPasswordResult(ChromiumPasswordState.failed);
  }
}
