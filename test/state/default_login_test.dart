import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/device_login.dart';
import 'package:secure_id/security/quick_unlock.dart';
import 'package:secure_id/security/vault_crypto.dart';
import 'package:secure_id/state/vault_controller.dart';

import '../support/fake_device_login_store.dart';
import '../support/fake_pin_unlock.dart';
import '../support/in_memory_vault_storage.dart';

void main() {
  late InMemoryVaultStorage storage;
  late FakePinUnlock pin;
  late FakeDeviceLoginStore loginStore;
  late VaultController controller;
  const password = 'correct horse battery staple';

  setUp(() {
    storage = InMemoryVaultStorage();
    pin = FakePinUnlock();
    loginStore = FakeDeviceLoginStore();
    controller = VaultController(
      storage: storage,
      pinUnlock: pin,
      kdf: VaultKdfConfig.test,
      deviceLoginStore: loginStore,
      quickUnlockConfig: QuickUnlockConfig.test,
    );
  });

  tearDown(() => controller.dispose());

  Future<void> createWithPin() async {
    await controller.init();
    await controller.createVault(password);
    expect(
      await controller.enableQuickUnlock(
        style: PasswordStyle.pin,
        pin: '123456',
      ),
      isTrue,
    );
  }

  test('defaults to the master password', () async {
    await controller.init();
    await controller.createVault(password);

    expect(controller.defaultLogin, DefaultLoginMethod.password);
    expect(controller.effectiveDefaultLogin, DefaultLoginMethod.password);
    expect(controller.quickUnlockEnabled, isFalse);
    expect(
      controller.quickUnlockAttemptsRemaining,
      QuickUnlockCrypto.maxAttempts,
    );
  });

  test('sets up a PIN and makes it the default login', () async {
    await createWithPin();

    expect(controller.quickUnlockEnabled, isTrue);
    expect(controller.defaultLogin, DefaultLoginMethod.passwordStyle);
    expect(controller.effectiveDefaultLogin, DefaultLoginMethod.passwordStyle);
    expect(controller.passwordStyle, PasswordStyle.pin);
    expect(storage.quickUnlock, isNotNull);
    expect(loginStore.settings?.method, DefaultLoginMethod.passwordStyle);
    expect(loginStore.settings?.style, PasswordStyle.pin);
  });

  test('unlocks with the PIN after locking', () async {
    await createWithPin();
    controller.lock();

    expect(await controller.unlockWithQuick('123456'), isTrue);
    expect(controller.status, VaultStatus.unlocked);
    expect(
      controller.quickUnlockAttemptsRemaining,
      QuickUnlockCrypto.maxAttempts,
    );
  });

  test('counts wrong attempts and resets after a success', () async {
    await createWithPin();
    controller.lock();

    expect(await controller.unlockWithQuick('654321'), isFalse);
    expect(controller.error, contains('4 attempts left'));
    expect(controller.quickUnlockAttemptsRemaining, 4);

    expect(await controller.unlockWithQuick('123456'), isTrue);
    expect(
      controller.quickUnlockAttemptsRemaining,
      QuickUnlockCrypto.maxAttempts,
    );

    controller.lock();
    expect(
      controller.quickUnlockAttemptsRemaining,
      QuickUnlockCrypto.maxAttempts,
    );
  });

  test(
    'locks out after five wrong attempts but keeps the master password',
    () async {
      await createWithPin();
      controller.lock();

      for (var i = 0; i < QuickUnlockCrypto.maxAttempts; i++) {
        expect(await controller.unlockWithQuick('000000'), isFalse);
      }

      expect(controller.quickUnlockLockedOut, isTrue);
      expect(controller.quickUnlockAttemptsRemaining, 0);
      expect(controller.effectiveDefaultLogin, DefaultLoginMethod.password);
      expect(await controller.unlockWithQuick('123456'), isFalse);
      expect(controller.error, contains('Too many attempts'));

      expect(await controller.unlock(password), isTrue);
      expect(controller.status, VaultStatus.unlocked);
    },
  );

  test('rejects an invalid PIN before storing a record', () async {
    await controller.init();
    await controller.createVault(password);

    expect(
      await controller.enableQuickUnlock(
        style: PasswordStyle.pin,
        pin: '12345',
      ),
      isFalse,
    );
    expect(controller.error, contains('six-digit'));
    expect(controller.quickUnlockEnabled, isFalse);
    expect(storage.quickUnlock, isNull);
  });

  test('sets up and unlocks with a pattern', () async {
    await controller.init();
    await controller.createVault(password);
    expect(
      await controller.enableQuickUnlock(
        style: PasswordStyle.pattern,
        pattern: [0, 1, 2, 5, 8],
      ),
      isTrue,
    );
    expect(controller.passwordStyle, PasswordStyle.pattern);

    controller.lock();
    expect(await controller.unlockWithQuick('0-1-2-5'), isFalse);
    expect(await controller.unlockWithQuick('0-1-2-5-8'), isTrue);
    expect(controller.status, VaultStatus.unlocked);
  });

  test('rejects a pattern with fewer than four dots', () async {
    await controller.init();
    await controller.createVault(password);

    expect(
      await controller.enableQuickUnlock(
        style: PasswordStyle.pattern,
        pattern: [0, 1, 2],
      ),
      isFalse,
    );
    expect(controller.error, contains('four dots'));
  });

  test('changing the style clears the old record', () async {
    await createWithPin();

    await controller.setPasswordStyle(PasswordStyle.pattern);

    expect(controller.passwordStyle, PasswordStyle.pattern);
    expect(controller.quickUnlockEnabled, isFalse);
    expect(storage.quickUnlock, isNull);
    expect(loginStore.settings?.style, PasswordStyle.pattern);
  });

  test('disabling quick unlock returns to the master password', () async {
    await createWithPin();

    await controller.disableQuickUnlock();

    expect(controller.quickUnlockEnabled, isFalse);
    expect(storage.quickUnlock, isNull);
    expect(controller.defaultLogin, DefaultLoginMethod.password);
    expect(loginStore.settings?.method, DefaultLoginMethod.password);
  });

  test('changing the master password clears quick unlock', () async {
    await createWithPin();

    expect(
      await controller.changeMasterPassword(
        currentPassword: password,
        newPassword: 'another very long password',
      ),
      isTrue,
    );

    expect(controller.quickUnlockEnabled, isFalse);
    expect(storage.quickUnlock, isNull);
    expect(controller.defaultLogin, DefaultLoginMethod.password);
  });

  test('wiping the vault clears quick unlock and the login choice', () async {
    await createWithPin();

    await controller.wipeVault();

    expect(controller.quickUnlockEnabled, isFalse);
    expect(storage.quickUnlock, isNull);
    expect(controller.defaultLogin, DefaultLoginMethod.password);
    expect(loginStore.settings?.method, DefaultLoginMethod.password);
  });

  test('device unlock can become the default login', () async {
    await controller.init();
    await controller.createVault(password);

    expect(
      await controller.setDefaultLogin(DefaultLoginMethod.deviceUnlock),
      isTrue,
    );
    expect(controller.defaultLogin, DefaultLoginMethod.deviceUnlock);
    expect(controller.pinEnabled, isTrue);
    expect(controller.effectiveDefaultLogin, DefaultLoginMethod.deviceUnlock);
    expect(loginStore.settings?.method, DefaultLoginMethod.deviceUnlock);
  });

  test('password style cannot be the default before setup', () async {
    await controller.init();
    await controller.createVault(password);

    expect(
      await controller.setDefaultLogin(DefaultLoginMethod.passwordStyle),
      isFalse,
    );
    expect(controller.error, contains('Set up'));
    expect(controller.defaultLogin, DefaultLoginMethod.password);
  });

  test('loads the saved login choice on init', () async {
    loginStore.settings = const DeviceLoginSettings(
      method: DefaultLoginMethod.passwordStyle,
      style: PasswordStyle.pattern,
    );

    await controller.init();

    expect(controller.defaultLogin, DefaultLoginMethod.passwordStyle);
    expect(controller.passwordStyle, PasswordStyle.pattern);
    // No matching record exists yet, so the lock screen still asks for the
    // master password.
    expect(controller.effectiveDefaultLogin, DefaultLoginMethod.password);
  });

  test('discards a quick-unlock record from a different vault', () async {
    await createWithPin();
    final other = await VaultCrypto.create(
      password: password,
      plaintext: '{}',
      config: VaultKdfConfig.test,
    );
    await storage.write(other.envelope.encode());

    final reloaded = VaultController(
      storage: storage,
      pinUnlock: pin,
      kdf: VaultKdfConfig.test,
      deviceLoginStore: loginStore,
      quickUnlockConfig: QuickUnlockConfig.test,
    );
    addTearDown(reloaded.dispose);
    await reloaded.init();

    expect(reloaded.quickUnlockEnabled, isFalse);
    expect(storage.quickUnlock, isNull);
  });
}
