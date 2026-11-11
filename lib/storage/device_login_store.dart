import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/device_login.dart';

/// Persists the chosen default login method outside the encrypted vault.
///
/// The lock screen reads this before the vault is unlocked, so it cannot live
/// inside the vault itself.
abstract class DeviceLoginStore {
  Future<DeviceLoginSettings?> read();
  Future<void> write(DeviceLoginSettings settings);
}

/// Stores unlock preferences in `login.json`.
class FileDeviceLoginStore implements DeviceLoginStore {
  FileDeviceLoginStore({this.fileName = 'login.json'});

  final String fileName;

  Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    await base.create(recursive: true);
    return File(p.join(base.path, fileName));
  }

  @override
  Future<DeviceLoginSettings?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['format'] != 'secureid-login') return null;
      return DeviceLoginSettings.fromJson(decoded);
    } catch (_) {
      // A damaged preferences file should never block the app.
      return null;
    }
  }

  @override
  Future<void> write(DeviceLoginSettings settings) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}
