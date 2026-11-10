import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/accessibility_settings.dart';
import 'package:secure_id/models/vault_item.dart';
import 'package:secure_id/security/vault_crypto.dart';
import 'package:secure_id/state/vault_controller.dart';
import 'package:secure_id/util/speech_text.dart';

import '../support/fake_pin_unlock.dart';
import '../support/fake_speech_service.dart';
import '../support/in_memory_accessibility_store.dart';
import '../support/in_memory_vault_storage.dart';

void main() {
  const password = 'correct horse battery staple';

  late InMemoryVaultStorage storage;
  late InMemoryAccessibilityStore accessibilityStore;
  late FakeSpeechService speech;
  late VaultController controller;

  setUp(() {
    storage = InMemoryVaultStorage();
    accessibilityStore = InMemoryAccessibilityStore();
    speech = FakeSpeechService();
    controller = VaultController(
      storage: storage,
      pinUnlock: FakePinUnlock(),
      kdf: VaultKdfConfig.test,
      accessibilityStore: accessibilityStore,
      speechService: speech,
    );
  });

  tearDown(() => controller.dispose());

  test('loads saved accessibility preferences before unlock', () async {
    accessibilityStore.settings = const AccessibilitySettings(
      textScale: AccessibilitySettings.largeScale,
      readAloud: true,
      highContrast: true,
    );

    await controller.init();
    expect(controller.status, VaultStatus.needsSetup);
    expect(controller.accessibility.textScale, 1.3);
    expect(controller.accessibility.readAloud, isTrue);
    expect(controller.accessibility.highContrast, isTrue);
    expect(controller.speechAvailable, isTrue);
  });

  test('persists updated accessibility preferences', () async {
    await controller.init();
    const next = AccessibilitySettings(
      textScale: AccessibilitySettings.hugeScale,
      highContrast: true,
    );

    await controller.updateAccessibility(next);

    expect(controller.accessibility.textScale, AccessibilitySettings.hugeScale);
    expect(controller.accessibility.highContrast, isTrue);
    expect(
      accessibilityStore.settings?.textScale,
      AccessibilitySettings.hugeScale,
    );
    expect(accessibilityStore.writes, 1);
  });

  test('speaks and stops through the speech service', () async {
    await controller.init();
    await controller.speak('Hello from SecureID');
    expect(speech.spoken, ['Hello from SecureID']);

    await controller.stopSpeaking();
    expect(speech.stops, greaterThan(0));
    expect(controller.isSpeaking, isFalse);
  });

  test('turning read aloud off stops speech', () async {
    await controller.init();
    await controller.updateAccessibility(
      const AccessibilitySettings(readAloud: true),
    );
    await controller.updateAccessibility(const AccessibilitySettings());

    expect(speech.stops, greaterThan(0));
  });

  test('a speech failure never breaks the vault', () async {
    speech.fail = true;
    await controller.init();
    await controller.speak('This will fail');
    expect(controller.isSpeaking, isFalse);
  });

  test('locking stops any in-progress speech', () async {
    await controller.init();
    await controller.createVault(password);
    controller.lock();
    expect(speech.stops, greaterThan(0));
  });

  test('item summaries never include passwords', () {
    final item = VaultItem.newLogin()
      ..title = 'GitHub'
      ..username = 'alice'
      ..password = 'hunter2'
      ..url = 'https://github.com';

    final summary = itemSpeech(item);
    expect(summary, contains('GitHub'));
    expect(summary, contains('alice'));
    expect(summary, isNot(contains('hunter2')));

    final details = itemSpeech(item, includeSecrets: true);
    expect(details, contains('hunter2'));
  });

  test('items summary counts accounts without secrets', () {
    final items = [
      VaultItem.newLogin()
        ..title = 'Bank'
        ..password = 'secret',
      VaultItem.newTotp()
        ..title = 'Mail'
        ..totp!.secret = 'JBSWY3DPEHPK3PXP',
    ];

    final summary = itemsSpeech(items);
    expect(summary, contains('2 accounts'));
    expect(summary, contains('Bank'));
    expect(summary, contains('Mail'));
    expect(summary, isNot(contains('secret')));
    expect(summary, isNot(contains('JBSWY3DP')));
  });
}
