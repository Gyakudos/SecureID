import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/device_login.dart';
import 'package:secure_id/models/vault_data.dart';
import 'package:secure_id/security/quick_unlock.dart';
import 'package:secure_id/security/vault_crypto.dart';
import 'package:secure_id/state/vault_controller.dart';

import '../support/fake_device_login_store.dart';
import '../support/fake_pin_unlock.dart';
import '../support/in_memory_vault_storage.dart';

/// Builds a valid envelope for a different vault, so the salt (and therefore
/// the vault id) differs from the local one.
Future<String> otherVault(String password) async {
  final sealed = await VaultCrypto.create(
    password: password,
    plaintext: jsonEncode(VaultData().toJson()),
    config: VaultKdfConfig.test,
  );
  return sealed.envelope.encode();
}

void main() {
  late InMemoryVaultStorage storage;
  late FakePinUnlock pin;
  late FakeDeviceLoginStore loginStore;
  late VaultController controller;
  const password = 'correct horse battery staple';
  const otherPassword = 'another master password entirely';

  void build({bool silentRewrap = true}) {
    storage = InMemoryVaultStorage();
    pin = FakePinUnlock(supportsSilentRewrap: silentRewrap);
    loginStore = FakeDeviceLoginStore();
    controller = VaultController(
      storage: storage,
      pinUnlock: pin,
      kdf: VaultKdfConfig.test,
      deviceLoginStore: loginStore,
      quickUnlockConfig: QuickUnlockConfig.test,
    );
  }

  setUp(() => build());

  tearDown(() => controller.dispose());

  Future<void> createWithDeviceAndPin() async {
    await controller.init();
    expect(await controller.createVault(password), isTrue);
    expect(await controller.enablePinUnlock(), isTrue);
    expect(
      await controller.enableQuickUnlock(
        style: PasswordStyle.pin,
        pin: '123456',
      ),
      isTrue,
    );
  }

  test('same-vault import keeps Windows Hello and the chosen login', () async {
    await createWithDeviceAndPin();
    expect(
      await controller.setDefaultLogin(DefaultLoginMethod.deviceUnlock),
      isTrue,
    );
    final original = storage.vault!;
    // Creating a fresh vault clears the old device key once; same-vault import
    // must not clear it again.
    pin.cleared = false;

    expect(await controller.importEnvelope(original), isTrue);

    expect(controller.status, VaultStatus.locked);
    expect(controller.pinEnabled, isTrue);
    expect(controller.quickUnlockEnabled, isTrue);
    expect(controller.pendingDeviceUnlock, isFalse);
    expect(controller.defaultLogin, DefaultLoginMethod.deviceUnlock);
    expect(controller.effectiveDefaultLogin, DefaultLoginMethod.deviceUnlock);
    expect(controller.passwordStyle, PasswordStyle.pin);
    expect(storage.pin, isNotNull);
    expect(storage.quickUnlock, isNotNull);
    expect(pin.cleared, isFalse);

    expect(await controller.unlockWithPin(), isTrue);
    expect(controller.status, VaultStatus.unlocked);
  });

  test('same-vault import keeps the PIN quick unlock working', () async {
    await createWithDeviceAndPin();
    final original = storage.vault!;

    expect(await controller.importEnvelope(original), isTrue);
    expect(await controller.unlockWithQuick('123456'), isTrue);
    expect(controller.status, VaultStatus.unlocked);
    expect(controller.defaultLogin, DefaultLoginMethod.passwordStyle);
  });

  test(
    'different-vault import pauses device unlock but keeps the method',
    () async {
      await createWithDeviceAndPin();
      expect(
        await controller.setDefaultLogin(DefaultLoginMethod.deviceUnlock),
        isTrue,
      );
      final incoming = await otherVault(otherPassword);

      expect(await controller.importEnvelope(incoming), isTrue);

      expect(controller.status, VaultStatus.locked);
      expect(controller.pinEnabled, isFalse);
      expect(controller.quickUnlockEnabled, isFalse);
      expect(controller.pendingDeviceUnlock, isTrue);
      // The preference survives; the lock screen falls back to the password
      // until the record can be recreated for the new vault.
      expect(controller.defaultLogin, DefaultLoginMethod.deviceUnlock);
      expect(controller.effectiveDefaultLogin, DefaultLoginMethod.password);
      expect(controller.passwordStyle, PasswordStyle.pin);
      expect(storage.pin, isNull);
      expect(storage.quickUnlock, isNull);
      expect(loginStore.settings?.pendingDeviceUnlock, isTrue);
      expect(loginStore.settings?.method, DefaultLoginMethod.deviceUnlock);
    },
  );

  test('a password unlock silently rewraps the device key', () async {
    await createWithDeviceAndPin();
    expect(
      await controller.setDefaultLogin(DefaultLoginMethod.deviceUnlock),
      isTrue,
    );
    expect(
      await controller.importEnvelope(await otherVault(otherPassword)),
      isTrue,
    );

    expect(await controller.unlock(otherPassword), isTrue);

    expect(controller.pendingDeviceUnlock, isFalse);
    expect(controller.pinEnabled, isTrue);
    expect(storage.pin, isNotNull);
    expect(controller.defaultLogin, DefaultLoginMethod.deviceUnlock);
    expect(controller.effectiveDefaultLogin, DefaultLoginMethod.deviceUnlock);
    expect(loginStore.settings?.pendingDeviceUnlock, isFalse);
  });

  test('a platform without silent rewrap waits for a confirmation', () async {
    controller.dispose();
    build(silentRewrap: false);
    await createWithDeviceAndPin();
    expect(
      await controller.setDefaultLogin(DefaultLoginMethod.deviceUnlock),
      isTrue,
    );
    expect(
      await controller.importEnvelope(await otherVault(otherPassword)),
      isTrue,
    );

    expect(await controller.unlock(otherPassword), isTrue);
    expect(controller.pendingDeviceUnlock, isTrue);
    expect(controller.pinEnabled, isFalse);
    expect(controller.effectiveDefaultLogin, DefaultLoginMethod.password);

    expect(await controller.resumeDeviceUnlock(), isTrue);
    expect(controller.pendingDeviceUnlock, isFalse);
    expect(controller.pinEnabled, isTrue);
    expect(controller.defaultLogin, DefaultLoginMethod.deviceUnlock);
  });

  test('restoring a different backup keeps the login preferences', () async {
    await createWithDeviceAndPin();
    expect(
      await controller.setDefaultLogin(DefaultLoginMethod.deviceUnlock),
      isTrue,
    );
    final incoming = await otherVault(otherPassword);

    expect(await controller.restoreFromBackup(incoming, otherPassword), isTrue);

    expect(controller.status, VaultStatus.unlocked);
    expect(controller.pendingDeviceUnlock, isFalse);
    expect(controller.pinEnabled, isTrue);
    expect(controller.defaultLogin, DefaultLoginMethod.deviceUnlock);
    expect(controller.passwordStyle, PasswordStyle.pin);
    expect(storage.pin, isNotNull);
  });
}
