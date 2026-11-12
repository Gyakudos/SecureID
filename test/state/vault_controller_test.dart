import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/vault_item.dart';
import 'package:secure_id/security/pin_unlock.dart';
import 'package:secure_id/security/vault_crypto.dart';
import 'package:secure_id/state/vault_controller.dart';

import '../support/fake_pin_unlock.dart';
import '../support/in_memory_vault_storage.dart';

void main() {
  late InMemoryVaultStorage storage;
  late FakePinUnlock pin;
  late VaultController controller;
  const password = 'correct horse battery staple';

  setUp(() {
    storage = InMemoryVaultStorage();
    pin = FakePinUnlock();
    controller = VaultController(
      storage: storage,
      pinUnlock: pin,
      kdf: VaultKdfConfig.test,
    );
  });

  tearDown(() => controller.dispose());

  test('creates, saves, locks and unlocks a vault', () async {
    await controller.init();
    expect(controller.status, VaultStatus.needsSetup);

    expect(await controller.createVault(password), isTrue);
    expect(controller.status, VaultStatus.unlocked);
    expect(storage.vault, isNotNull);

    final item = VaultItem.newLogin()
      ..title = 'GitHub'
      ..username = 'alice'
      ..password = 'hunter2';
    await controller.upsertItem(item);
    expect(controller.items, hasLength(1));

    controller.lock();
    expect(controller.status, VaultStatus.locked);
    expect(controller.items, isEmpty);

    expect(await controller.unlock('wrong password'), isFalse);
    expect(controller.status, VaultStatus.locked);

    expect(await controller.unlock(password), isTrue);
    expect(controller.items.single.title, 'GitHub');
    expect(controller.items.single.password, 'hunter2');
  });

  test('requires a long master password', () async {
    await controller.init();
    expect(await controller.createVault('short'), isFalse);
    expect(controller.status, VaultStatus.needsSetup);
  });

  test('updates and deletes items', () async {
    await controller.init();
    await controller.createVault(password);

    final item = VaultItem.newTotp()
      ..title = 'Mail'
      ..totp!.secret = 'JBSWY3DPEHPK3PXP';
    await controller.upsertItem(item);
    expect(controller.totpCount, 1);

    item.title = 'Mail (work)';
    await controller.upsertItem(item);
    expect(controller.items.single.title, 'Mail (work)');

    await controller.toggleFavorite(item.id);
    expect(controller.items.single.favorite, isTrue);

    await controller.deleteItem(item.id);
    expect(controller.items, isEmpty);
  });

  test('changes the master password', () async {
    await controller.init();
    await controller.createVault(password);

    expect(
      await controller.changeMasterPassword(
        currentPassword: 'not the password',
        newPassword: 'another very long password',
      ),
      isFalse,
    );

    expect(
      await controller.changeMasterPassword(
        currentPassword: password,
        newPassword: 'another very long password',
      ),
      isTrue,
    );

    controller.lock();
    expect(await controller.unlock(password), isFalse);
    expect(await controller.unlock('another very long password'), isTrue);
  });

  test('enables Windows Hello unlock and uses it after locking', () async {
    await controller.init();
    await controller.createVault(password);

    expect(await controller.enablePinUnlock(), isTrue);
    expect(controller.pinEnabled, isTrue);
    expect(storage.pin, isNotNull);
    expect(controller.settings.pinUnlockEnabled, isTrue);

    controller.lock();
    expect(await controller.unlockWithPin(), isTrue);
    expect(controller.status, VaultStatus.unlocked);
  });

  test('disables Windows Hello unlock', () async {
    await controller.init();
    await controller.createVault(password);
    await controller.enablePinUnlock();

    await controller.disablePinUnlock();
    expect(controller.pinEnabled, isFalse);
    expect(storage.pin, isNull);
    expect(pin.cleared, isTrue);
  });

  test('cancelling the unlock prompt keeps the device record', () async {
    await controller.init();
    await controller.createVault(password);
    await controller.enablePinUnlock();
    controller.lock();

    pin.cancel = true;
    expect(await controller.unlockWithPin(), isFalse);
    expect(controller.status, VaultStatus.locked);
    expect(storage.pin, isNotNull);
    expect(controller.pinEnabled, isTrue);
    expect(controller.error, contains('cancelled'));

    pin.cancel = false;
    expect(await controller.unlockWithPin(), isTrue);
    expect(controller.status, VaultStatus.unlocked);
  });

  test('a record the platform can no longer use is discarded', () async {
    await controller.init();
    await controller.createVault(password);
    await controller.enablePinUnlock();
    controller.lock();

    pin.failure = const PinUnlockException(
      'Biometrics changed on this phone. Use your master password.',
      permanent: true,
    );
    expect(await controller.unlockWithPin(), isFalse);
    expect(controller.status, VaultStatus.locked);
    expect(storage.pin, isNull);
    expect(controller.pinEnabled, isFalse);
    expect(controller.error, contains('Biometrics changed'));
  });

  test('a temporary device failure keeps the record', () async {
    await controller.init();
    await controller.createVault(password);
    await controller.enablePinUnlock();
    controller.lock();

    pin.failure = const PinUnlockException('Too many attempts. Try later.');
    expect(await controller.unlockWithPin(), isFalse);
    expect(controller.status, VaultStatus.locked);
    expect(storage.pin, isNotNull);
    expect(controller.pinEnabled, isTrue);

    pin.failure = null;
    expect(await controller.unlockWithPin(), isTrue);
  });

  test('creating a vault makes device unlock available to the UI', () async {
    await controller.init();
    await controller.createVault(password);

    expect(controller.pinAvailable, isTrue);
    expect(controller.pinEnabled, isFalse);
  });

  test(
    'enables device unlock even when availability is a false negative',
    () async {
      pin.available = false;
      await controller.init();
      await controller.createVault(password);

      expect(await controller.enablePinUnlock(), isTrue);
      expect(controller.pinEnabled, isTrue);
      expect(storage.pin, isNotNull);
    },
  );

  test('keeps a stored record when availability reports false', () async {
    await controller.init();
    await controller.createVault(password);
    await controller.enablePinUnlock();
    controller.lock();

    pin.available = false;
    expect(await controller.unlock(password), isTrue);
    expect(controller.pinEnabled, isTrue);
    expect(storage.pin, isNotNull);
  });

  test('cancelling while enabling does not turn device unlock on', () async {
    await controller.init();
    await controller.createVault(password);

    pin.cancel = true;
    expect(await controller.enablePinUnlock(), isFalse);
    expect(controller.pinEnabled, isFalse);
    expect(storage.pin, isNull);
    expect(controller.error, contains('cancelled'));
  });

  test('exposes platform unlock wording for the UI', () async {
    expect(controller.pinFeatureName, 'Windows Hello');
    expect(controller.pinUnlockButtonLabel, 'Unlock with Windows Hello');
    expect(controller.pinAvailableHint, isNotEmpty);
    expect(controller.pinUnavailableHint, isNotEmpty);
  });

  test('exports and restores a backup', () async {
    await controller.init();
    await controller.createVault(password);
    await controller.upsertItem(VaultItem.newLogin()..title = 'Bank');
    final backup = await controller.exportBackup();

    await controller.wipeVault();
    expect(controller.status, VaultStatus.needsSetup);
    expect(storage.vault, isNull);

    expect(await controller.restoreFromBackup(backup, password), isTrue);
    expect(controller.status, VaultStatus.unlocked);
    expect(controller.items.single.title, 'Bank');
  });

  test('applies settings and auto-locks on background', () async {
    await controller.init();
    await controller.createVault(password);

    final next = controller.settings.copy()..autoLockMinutes = 15;
    await controller.updateSettings(next);
    expect(controller.settings.autoLockMinutes, 15);

    controller.handleLifecycle(AppLifecycleState.paused);
    expect(controller.status, VaultStatus.locked);
  });

  test('exports the encrypted envelope without unlocking it', () async {
    await controller.init();
    await controller.createVault(password);
    await controller.upsertItem(VaultItem.newLogin()..title = 'Bank');

    final envelope = await controller.readEncryptedEnvelope();
    expect(envelope, isNotNull);
    expect(envelope, storage.vault);
    expect(envelope, isNot(contains('Bank')));
  });

  test('imports an envelope from another device and stays locked', () async {
    await controller.init();
    await controller.createVault(password);
    await controller.upsertItem(VaultItem.newLogin()..title = 'Imported');
    final envelope = (await controller.readEncryptedEnvelope())!;

    final otherStorage = InMemoryVaultStorage();
    final other = VaultController(
      storage: otherStorage,
      pinUnlock: FakePinUnlock(),
      kdf: VaultKdfConfig.test,
    );
    addTearDown(other.dispose);
    await other.init();
    expect(other.status, VaultStatus.needsSetup);

    expect(await other.importEnvelope(envelope), isTrue);
    expect(otherStorage.vault, envelope);
    expect(other.status, VaultStatus.locked);
    expect(other.items, isEmpty);

    expect(await other.unlock(password), isTrue);
    expect(other.items.single.title, 'Imported');
  });

  test('rejects an invalid imported envelope', () async {
    await controller.init();

    expect(await controller.importEnvelope('not a vault'), isFalse);
    expect(controller.status, VaultStatus.needsSetup);
    expect(storage.vault, isNull);

    expect(await controller.importEnvelope('   '), isFalse);
    expect(controller.error, isNotNull);
  });
}
