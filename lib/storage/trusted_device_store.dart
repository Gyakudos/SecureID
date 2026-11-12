import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/trusted_device.dart';
import '../security/device_seal.dart';

/// Raised when the trusted-device list cannot be read or written.
class TrustedDeviceStoreException implements Exception {
  const TrustedDeviceStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Keeps the local trusted-device records in one sealed file.
///
/// The file lives next to the vault but outside it: receiving a vault while the
/// app is locked or at setup still needs the trust records. It contains trust
/// keys only, never vault contents or the master password.
class TrustedDeviceStore {
  TrustedDeviceStore({
    required DeviceSeal seal,
    this.fileName = 'trusted_devices.bin',
    Future<Directory> Function()? directory,
    // ignore: prefer_initializing_formals
  }) : _seal = seal,
       _directory = directory ?? getApplicationSupportDirectory;

  final DeviceSeal _seal;
  final String fileName;
  final Future<Directory> Function() _directory;

  List<TrustedDevice> _devices = const [];
  bool _loaded = false;
  String? _lastError;

  /// Why the last load failed, if it did. A failed load leaves the file in
  /// place instead of silently forgetting paired devices.
  String? get lastError => _lastError;

  String get sealLabel => _seal.label;

  Future<File> _file() async {
    final base = await _directory();
    await base.create(recursive: true);
    return File(p.join(base.path, fileName));
  }

  Future<List<TrustedDevice>> load({bool force = false}) async {
    if (_loaded && !force) return List<TrustedDevice>.unmodifiable(_devices);
    _loaded = true;
    _lastError = null;

    final file = await _file();
    if (!await file.exists()) {
      _devices = const [];
      return const [];
    }

    try {
      final sealed = await file.readAsBytes();
      if (sealed.isEmpty) {
        _devices = const [];
        return const [];
      }
      final clear = await _seal.unseal(sealed);
      final text = utf8.decode(clear);
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid trusted-device file.');
      }
      final list = decoded['devices'];
      if (list is! List) {
        throw const FormatException('Invalid trusted-device file.');
      }
      final devices = <TrustedDevice>[];
      for (final entry in list) {
        if (entry is Map<String, dynamic>) {
          try {
            devices.add(TrustedDevice.fromJson(entry));
          } on FormatException {
            // Skip one damaged record rather than losing the whole list.
          }
        }
      }
      _devices = List<TrustedDevice>.unmodifiable(devices);
      return _devices;
    } catch (exception) {
      _devices = const [];
      _lastError = exception is DeviceSealException
          ? exception.message
          : 'The trusted-device list could not be read.';
      return const [];
    }
  }

  Future<void> _save(List<TrustedDevice> devices) async {
    final file = await _file();
    final payload = jsonEncode({
      'version': 1,
      'devices': [for (final device in devices) device.toJson()],
    });
    final sealed = await _seal.seal(utf8.encode(payload));
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');

    await temp.writeAsBytes(sealed, flush: true);
    if (await file.exists()) {
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
    }
    try {
      await temp.rename(file.path);
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }

    _devices = List<TrustedDevice>.unmodifiable(devices);
    _loaded = true;
    _lastError = null;
  }

  Future<TrustedDevice?> find(String deviceId) async {
    final devices = await load();
    for (final device in devices) {
      if (device.deviceId == deviceId) return device;
    }
    return null;
  }

  Future<void> remember(TrustedDevice device) async {
    final devices = [...await load()]
      ..removeWhere((existing) => existing.deviceId == device.deviceId)
      ..add(device);
    await _save(devices);
  }

  Future<void> forget(String deviceId) async {
    final devices = [...await load()]
      ..removeWhere((device) => device.deviceId == deviceId);
    await _save(devices);
  }

  Future<void> touch(String deviceId, {String? address, DateTime? at}) async {
    final devices = [...await load()];
    final index = devices.indexWhere((device) => device.deviceId == deviceId);
    if (index < 0) return;
    devices[index] = devices[index].copyWith(
      lastUsedAt: at ?? DateTime.now(),
      lastAddress: address ?? devices[index].lastAddress,
    );
    await _save(devices);
  }

  Future<void> setAutoAccept(String deviceId, bool autoAccept) async {
    final devices = [...await load()];
    final index = devices.indexWhere((device) => device.deviceId == deviceId);
    if (index < 0) return;
    devices[index] = devices[index].copyWith(autoAccept: autoAccept);
    await _save(devices);
  }

  /// Removes every trusted device but keeps the sealing key for future pairing.
  Future<void> clear() async {
    final file = await _file();
    for (final target in [
      file,
      File('${file.path}.tmp'),
      File('${file.path}.bak'),
    ]) {
      if (await target.exists()) await target.delete();
    }
    _devices = const [];
    _loaded = true;
    _lastError = null;
  }

  /// Removes every trusted device and the platform wrapping key.
  Future<void> reset() async {
    await clear();
    await _seal.deleteKey();
  }
}
