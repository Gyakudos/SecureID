import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/trusted_device.dart';
import 'package:secure_id/security/device_seal.dart';
import 'package:secure_id/security/vault_crypto.dart';
import 'package:secure_id/state/vault_controller.dart';
import 'package:secure_id/storage/trusted_device_store.dart';

import '../support/fake_pin_unlock.dart';
import '../support/in_memory_vault_storage.dart';

class _TestSeal implements DeviceSeal {
  @override
  String get label => 'Test seal';

  @override
  Future<List<int>> seal(List<int> data) async => List<int>.of(data);

  @override
  Future<List<int>> unseal(List<int> data) async => List<int>.of(data);

  @override
  Future<void> deleteKey() async {}
}

TrustedDevice _device(String id) => TrustedDevice(
  deviceId: id,
  name: 'Phone $id',
  platform: 'android',
  trustKey: List<int>.generate(32, (index) => index),
  lastUsedAt: DateTime.utc(2026, 1, 1),
  lastAddress: '192.168.1.30:47823',
);

void main() {
  late Directory tempDir;
  late InMemoryVaultStorage storage;
  late TrustedDeviceStore trustStore;
  late VaultController controller;
  const password = 'correct horse battery staple';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('secureid_trust_ctrl_');
    storage = InMemoryVaultStorage();
    trustStore = TrustedDeviceStore(
      seal: _TestSeal(),
      directory: () async => tempDir,
    );
    controller = VaultController(
      storage: storage,
      pinUnlock: FakePinUnlock(),
      kdf: VaultKdfConfig.test,
      trustedDeviceStore: trustStore,
    );
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('exposes the local trusted-device list', () async {
    expect(controller.trustedDeviceAvailable, isTrue);
    expect(controller.trustedSealLabel, 'Test seal');

    await controller.loadTrustedDevices();
    expect(controller.trustedDevices, isEmpty);

    await controller.rememberTrustedDevice(_device('a'));
    expect(controller.trustedDevices, hasLength(1));
    expect(controller.trustedDevices.single.deviceId, 'a');
    expect(controller.trustedDevicesLoading, isFalse);

    final found = await controller.findTrustedDevice('a');
    expect(found, isNotNull);
    expect(await controller.findTrustedDevice('missing'), isNull);
  });

  test('updates auto-accept and forgets devices', () async {
    await controller.rememberTrustedDevice(_device('a'));

    await controller.setTrustedDeviceAutoAccept('a', true);
    expect(controller.trustedDevices.single.autoAccept, isTrue);

    await controller.touchTrustedDevice('a', address: '10.0.0.5:8080');
    expect(controller.trustedDevices.single.lastAddress, '10.0.0.5:8080');

    await controller.forgetTrustedDevice('a');
    expect(controller.trustedDevices, isEmpty);
  });

  test('resets the trust store', () async {
    await controller.rememberTrustedDevice(_device('a'));
    await controller.resetTrustedDevices();
    expect(controller.trustedDevices, isEmpty);
    expect(await trustStore.load(force: true), isEmpty);
  });

  test('imports an envelope and leaves the vault locked', () async {
    await controller.init();
    await controller.createVault(password);

    final sealed = await VaultCrypto.create(
      password: 'another master password',
      plaintext: '{"items":[],"settings":{}}',
      config: VaultKdfConfig.test,
    );
    final envelope = sealed.envelope.encode();

    expect(await controller.importEnvelope(envelope), isTrue);
    expect(controller.status, VaultStatus.locked);
    expect(await controller.readEncryptedEnvelope(), envelope);
    expect(await controller.unlock('another master password'), isTrue);
  });
}
