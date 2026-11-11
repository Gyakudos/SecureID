import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/config/app_version.dart';
import 'package:secure_id/security/vault_crypto.dart';
import 'package:secure_id/services/update_service.dart';
import 'package:secure_id/state/vault_controller.dart';
import 'package:secure_id/state/vault_scope.dart';
import 'package:secure_id/ui/widgets/update_dialog.dart';

import '../support/fake_pin_unlock.dart';
import '../support/fake_update_service.dart';
import '../support/in_memory_vault_storage.dart';

void main() {
  Future<VaultController> pumpApp(
    WidgetTester tester,
    FakeUpdateService updates,
  ) async {
    final controller = VaultController(
      storage: InMemoryVaultStorage(),
      pinUnlock: FakePinUnlock(),
      kdf: VaultKdfConfig.test,
      updateService: updates,
    );
    addTearDown(controller.dispose);
    await controller.init();

    await tester.pumpWidget(
      VaultScope(
        controller: controller,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showUpdateCheck(context),
                  child: const Text('Check'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('offers a newer release with a download action', (tester) async {
    await pumpApp(tester, FakeUpdateService(release: buildUpdate('9.9.9')));

    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();

    expect(find.text('SecureID 9.9.9 is available'), findsOneWidget);
    expect(
      find.text('You are on $appVersion. The newest release is 9.9.9.'),
      findsOneWidget,
    );
    expect(find.text('Release notes for 9.9.9'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    // No assets in the fixture, so the fallback opens the release page.
    expect(find.text('Open release page'), findsOneWidget);
  });

  testWidgets('reports when the build is current', (tester) async {
    await pumpApp(tester, FakeUpdateService(release: buildUpdate(appVersion)));

    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();

    expect(find.text('You are up to date'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
  });

  testWidgets('shows a readable failure with a retry', (tester) async {
    await pumpApp(
      tester,
      FakeUpdateService(
        error: const UpdateException('Could not reach GitHub.'),
      ),
    );

    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();

    expect(find.text('Update check failed'), findsOneWidget);
    expect(find.text('Could not reach GitHub.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('closing the dialog keeps the result for the settings tile', (
    tester,
  ) async {
    final controller = await pumpApp(
      tester,
      FakeUpdateService(release: buildUpdate('9.9.9')),
    );

    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.byType(UpdateDialog), findsNothing);
    expect(controller.updateStatus, UpdateStatus.available);
    expect(controller.latestUpdate?.version, '9.9.9');
  });
}
