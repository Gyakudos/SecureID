import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'windows_dpapi.dart';

/// Storage for the 256-bit device key that wraps the vault key for Windows
/// Hello unlock.
abstract class DeviceKeyStore {
  Future<Uint8List?> read();
  Future<void> write(Uint8List key);
  Future<void> delete();
}

/// Keeps the device key in a DPAPI-sealed file in the app support folder.
///
/// The file is bound to the current Windows user, so copying it to another
/// account or machine does not expose the key. The plaintext key never touches
/// disk.
class WindowsDpapiDeviceKeyStore implements DeviceKeyStore {
  WindowsDpapiDeviceKeyStore({this.fileName = 'device.key'});

  final String fileName;

  /// Additional entropy mixed into the DPAPI blob. It is not a secret; it only
  /// scopes the blob to SecureID.
  static final Uint8List _entropy = Uint8List.fromList(
    utf8.encode('SecureID device key v1'),
  );

  Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    await base.create(recursive: true);
    return File(p.join(base.path, fileName));
  }

  @override
  Future<Uint8List?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final sealed = await file.readAsBytes();
    if (sealed.isEmpty) return null;
    return WindowsDpapi.instance.unprotect(sealed, entropy: _entropy);
  }

  @override
  Future<void> write(Uint8List key) async {
    final file = await _file();
    final sealed = WindowsDpapi.instance.protect(key, entropy: _entropy);
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(sealed, flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  @override
  Future<void> delete() async {
    final file = await _file();
    for (final target in [file, File('${file.path}.tmp')]) {
      if (await target.exists()) await target.delete();
    }
  }
}
