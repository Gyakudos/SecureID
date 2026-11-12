import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/trusted_device.dart';
import 'package:secure_id/security/device_seal.dart';
import 'package:secure_id/storage/trusted_device_store.dart';

class _TestSeal implements DeviceSeal {
  static const List<int> _prefix = [0x53, 0x49, 0x44];

  bool deleted = false;

  @override
  String get label => 'Test seal';

  @override
  Future<List<int>> seal(List<int> data) async => [..._prefix, ...data];

  @override
  Future<List<int>> unseal(List<int> data) async {
    if (data.length < _prefix.length) {
      throw const DeviceSealException('The sealed record is invalid.');
    }
    for (var index = 0; index < _prefix.length; index++) {
      if (data[index] != _prefix[index]) {
        throw const DeviceSealException('The sealed record is invalid.');
      }
    }
    return data.sublist(_prefix.length);
  }

  @override
  Future<void> deleteKey() async {
    deleted = true;
  }
}

TrustedDevice device(String id, {bool autoAccept = false}) => TrustedDevice(
  deviceId: id,
  name: 'Device $id',
  platform: 'android',
  trustKey: List<int>.generate(32, (index) => index + id.length),
  createdAt: DateTime.utc(2026, 1, 1),
  lastUsedAt: DateTime.utc(2026, 1, 2),
  lastAddress: '192.168.1.10:47823',
  autoAccept: autoAccept,
);

void main() {
  late Directory tempDir;
  late _TestSeal seal;
  late TrustedDeviceStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('secureid_trust_test_');
    seal = _TestSeal();
    store = TrustedDeviceStore(seal: seal, directory: () async => tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('starts empty when no file exists', () async {
    expect(await store.load(), isEmpty);
    expect(store.lastError, isNull);
  });

  test('remembers, loads and finds a device', () async {
    await store.remember(device('a'));

    final loaded = await TrustedDeviceStore(
      seal: seal,
      directory: () async => tempDir,
    ).load();
    expect(loaded, hasLength(1));
    expect(loaded.single.deviceId, 'a');
    expect(loaded.single.trustKey, hasLength(32));
    expect(loaded.single.lastAddress, '192.168.1.10:47823');

    final found = await store.find('a');
    expect(found, isNotNull);
    expect(await store.find('missing'), isNull);
  });

  test('replaces an existing record with the same id', () async {
    await store.remember(device('a'));
    await store.remember(device('a', autoAccept: true));

    final loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.autoAccept, isTrue);
  });

  test('touches and updates auto-accept', () async {
    await store.remember(device('a'));
    await store.touch('a', address: '10.0.0.2:9000');
    await store.setAutoAccept('a', true);

    final loaded = await store.load();
    expect(loaded.single.lastAddress, '10.0.0.2:9000');
    expect(loaded.single.autoAccept, isTrue);

    // Unknown ids are ignored instead of creating records.
    await store.touch('missing');
    await store.setAutoAccept('missing', true);
    expect(await store.load(), hasLength(1));
  });

  test('forgets a device', () async {
    await store.remember(device('a'));
    await store.remember(device('b'));
    await store.forget('a');

    final loaded = await store.load();
    expect(loaded.map((entry) => entry.deviceId), ['b']);
  });

  test('clear removes records but keeps the sealing key', () async {
    await store.remember(device('a'));
    await store.clear();

    expect(await store.load(force: true), isEmpty);
    expect(seal.deleted, isFalse);
  });

  test('reset removes records and the sealing key', () async {
    await store.remember(device('a'));
    await store.reset();

    expect(await store.load(force: true), isEmpty);
    expect(seal.deleted, isTrue);
  });

  test('reports a damaged file without throwing', () async {
    await File('${tempDir.path}/trusted_devices.bin').writeAsBytes([1, 2, 3]);

    expect(await store.load(), isEmpty);
    expect(store.lastError, isNotNull);
    // A damaged file is left in place so a later build can try to recover it.
    expect(await File('${tempDir.path}/trusted_devices.bin').exists(), isTrue);
  });
}
