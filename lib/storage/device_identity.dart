import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../util/ids.dart';

/// Stable identity for this installation, used for the account device list.
class DeviceIdentity {
  const DeviceIdentity({
    required this.id,
    required this.name,
    required this.platform,
  });

  final String id;
  final String name;
  final String platform;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'id': id,
    'name': name,
    'platform': platform,
  };

  factory DeviceIdentity.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    if (id.isEmpty) throw const FormatException('Invalid device identity.');
    return DeviceIdentity(
      id: id,
      name: json['name'] as String? ?? 'SecureID device',
      platform: json['platform'] as String? ?? 'unknown',
    );
  }
}

/// Stores `device.json` next to the encrypted vault.
class DeviceIdentityStore {
  DeviceIdentityStore({this.fileName = 'device.json'});

  final String fileName;

  Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    await base.create(recursive: true);
    return File(p.join(base.path, fileName));
  }

  Future<DeviceIdentity> load() async {
    final file = await _file();
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          return DeviceIdentity.fromJson(decoded);
        }
      } catch (_) {
        // A damaged identity file is replaced with a fresh one.
      }
    }
    final identity = DeviceIdentity(
      id: newId(18),
      name: defaultDeviceName(),
      platform: defaultPlatformName(),
    );
    await _write(identity);
    return identity;
  }

  Future<void> _write(DeviceIdentity identity) async {
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(identity.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}

String defaultDeviceName() {
  if (Platform.isWindows) {
    final host = Platform.localHostname.trim();
    return host.isEmpty ? 'Windows PC' : host;
  }
  if (Platform.isAndroid) return 'Android phone';
  final host = Platform.localHostname.trim();
  return host.isEmpty ? 'SecureID device' : host;
}

String defaultPlatformName() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isAndroid) return 'android';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  if (Platform.isIOS) return 'ios';
  return Platform.operatingSystem;
}
