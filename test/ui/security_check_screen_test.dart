import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/totp.dart';
import 'package:secure_id/models/vault_item.dart';
import 'package:secure_id/security/vault_crypto.dart';
import 'package:secure_id/state/vault_controller.dart';
import 'package:secure_id/state/vault_scope.dart';
import 'package:secure_id/ui/screens/security_check_screen.dart';
import 'package:secure_id/ui/theme.dart';
import 'package:secure_id/ui/widgets/item_detail_sheet.dart';

import '../support/fake_pin_unlock.dart';
import '../support/in_memory_vault_storage.dart';

void main() {
  const password = 'correct horse battery staple';

  late VaultController controller;

  setUp(() async {
    controller = VaultController(
      storage: InMemoryVaultStorage(),
      pinUnlock: FakePinUnlock(),
      kdf: VaultKdfConfig.test,
    );
    await controller.init();
    await controller.createVault(password);
  });

  tearDown(() => controller.dispose());

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      VaultScope(
        controller: controller,
        child: MaterialApp(
          theme: buildSecureIdTheme(),
          home: const SecurityCheckScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  VaultItem login(String id, String title, String password) => VaultItem(
    id: id,
    kind: VaultItemKind.login,
    title: title,
    username: '$id@example.com',
    password: password,
  );

  testWidgets('shows the score and the grouped issues', (tester) async {
    // Saving encrypts the vault, so it must run with the real clock.
    await tester.runAsync(() async {
      await controller.upsertItem(login('a', 'Alpha', ''));
      await controller.upsertItem(login('b', 'Bravo', 'vN7#qL2!tR9@wX4\$'));
    });
    await pumpScreen(tester);

    expect(find.text('70'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('2 logins checked'), findsOneWidget);
    expect(find.text('2 issues found'), findsOneWidget);

    expect(find.text('No password'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('No two-factor code'), findsOneWidget);
    expect(find.text('Bravo'), findsOneWidget);

    await tester.tap(find.text('Alpha'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ItemDetailSheet), findsOneWidget);
  });

  testWidgets('reports a clean vault', (tester) async {
    await tester.runAsync(() async {
      await controller.upsertItem(
        VaultItem(
          id: 'a',
          kind: VaultItemKind.login,
          title: 'Alpha',
          password: 'vN7#qL2!tR9@wX4\$',
          totp: TotpData(secret: 'JBSWY3DPEHPK3PXP'),
        ),
      );
    });
    await pumpScreen(tester);

    expect(find.text('100'), findsOneWidget);
    expect(find.text('Excellent'), findsOneWidget);
    expect(find.text('No issues found'), findsOneWidget);
    expect(find.text('Nothing to fix'), findsOneWidget);
  });

  testWidgets('handles a vault with no logins', (tester) async {
    await pumpScreen(tester);

    expect(find.text('No logins to check'), findsOneWidget);
    expect(find.text('Nothing to check yet'), findsOneWidget);
  });
}
