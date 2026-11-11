import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/app.dart';
import 'package:secure_id/config/app_version.dart';
import 'package:secure_id/models/accessibility_settings.dart';
import 'package:secure_id/security/vault_crypto.dart';
import 'package:secure_id/state/vault_controller.dart';
import 'package:secure_id/ui/theme.dart';

import 'support/fake_pin_unlock.dart';
import 'support/in_memory_accessibility_store.dart';
import 'support/in_memory_vault_storage.dart';

void main() {
  const password = 'correct horse battery staple';

  VaultController buildController(InMemoryVaultStorage storage) {
    return VaultController(
      storage: storage,
      pinUnlock: FakePinUnlock(),
      kdf: VaultKdfConfig.test,
    );
  }

  testWidgets('creates a vault and reaches the vault screen', (tester) async {
    final controller = buildController(InMemoryVaultStorage());
    addTearDown(controller.dispose);
    await controller.init();

    await tester.pumpWidget(SecureIdApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Create your vault'), findsOneWidget);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), password);
    await tester.enterText(fields.at(1), password);
    await tester.pump();

    await tester.tap(find.text('Create secure vault'));
    await tester.pumpAndSettle();

    expect(controller.status, VaultStatus.unlocked);
    expect(find.text('Your vault is empty'), findsOneWidget);
    expect(find.text('Add item'), findsOneWidget);
    // The version pill doubles as the update button once the vault is open.
    expect(find.text('v$appVersion'), findsOneWidget);

    controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('validates the setup form', (tester) async {
    final controller = buildController(InMemoryVaultStorage());
    addTearDown(controller.dispose);
    await controller.init();

    await tester.pumpWidget(SecureIdApp(controller: controller));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'a sufficiently long password');
    await tester.enterText(fields.at(1), 'a different long password');
    await tester.tap(find.text('Create secure vault'));
    await tester.pump();

    expect(find.text('The two passwords do not match.'), findsOneWidget);
    expect(controller.status, VaultStatus.needsSetup);
  });

  testWidgets('unlocks with the master password', (tester) async {
    final controller = buildController(InMemoryVaultStorage());
    addTearDown(controller.dispose);
    await controller.init();
    await controller.createVault(password);
    controller.lock();

    await tester.pumpWidget(SecureIdApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, password);
    await tester.tap(find.text('Unlock vault'));
    await tester.pumpAndSettle();

    expect(controller.status, VaultStatus.unlocked);
    expect(find.text('Your vault is empty'), findsOneWidget);

    controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('applies saved vision settings before the vault is unlocked', (
    tester,
  ) async {
    final store = InMemoryAccessibilityStore(
      const AccessibilitySettings(
        textScale: AccessibilitySettings.extraLargeScale,
        highContrast: true,
      ),
    );
    final controller = VaultController(
      storage: InMemoryVaultStorage(),
      pinUnlock: FakePinUnlock(),
      kdf: VaultKdfConfig.test,
      accessibilityStore: store,
    );
    addTearDown(controller.dispose);
    await controller.init();

    await tester.pumpWidget(SecureIdApp(controller: controller));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Create your vault'));
    expect(MediaQuery.of(context).textScaler.scale(10), closeTo(16, 0.01));
    expect(isHighContrast(context), isTrue);

    await tester.ensureVisible(find.text('Vision & reading'));
    await tester.tap(find.text('Vision & reading'));
    await tester.pumpAndSettle();

    expect(find.text('Text size'), findsOneWidget);
    expect(find.text('High contrast'), findsOneWidget);
    expect(find.text('Enable spoken accounts'), findsOneWidget);
  });
}
