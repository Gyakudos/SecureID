import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/passkey.dart';
import 'package:secure_id/models/totp.dart';
import 'package:secure_id/models/vault_item.dart';
import 'package:secure_id/security/vault_crypto.dart';
import 'package:secure_id/state/vault_controller.dart';
import 'package:secure_id/state/vault_scope.dart';
import 'package:secure_id/ui/theme.dart';
import 'package:secure_id/ui/widgets/item_detail_sheet.dart';
import 'package:secure_id/ui/widgets/totp_display.dart';

import '../support/fake_pin_unlock.dart';
import '../support/in_memory_vault_storage.dart';

void main() {
  const password = 'correct horse battery staple';

  late String clipboard;
  late VaultController controller;

  setUp(() async {
    clipboard = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboard = (call.arguments as Map)['text'] as String? ?? '';
              return null;
            case 'Clipboard.getData':
              return <String, dynamic>{'text': clipboard};
          }
          return null;
        });
    controller = VaultController(
      storage: InMemoryVaultStorage(),
      pinUnlock: FakePinUnlock(),
      kdf: VaultKdfConfig.test,
    );
    await controller.init();
    await controller.createVault(password);
    // No delayed clear timer, so the test ends without pending timers.
    controller.settings.clipboardClearSeconds = 0;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    controller.dispose();
  });

  Future<void> pumpSheet(WidgetTester tester, VaultItem item) async {
    await tester.pumpWidget(
      VaultScope(
        controller: controller,
        child: MaterialApp(
          theme: buildSecureIdTheme(),
          home: Scaffold(body: ItemDetailSheet(item: item)),
        ),
      ),
    );
    await tester.pump();
  }

  Finder block(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

  testWidgets('tapping the username block copies it', (tester) async {
    await pumpSheet(
      tester,
      VaultItem(
        id: 'login-1',
        kind: VaultItemKind.login,
        title: 'Mail',
        username: 'alice@example.com',
        password: 'hunter2',
        url: 'https://example.com',
      ),
    );

    expect(find.byIcon(Icons.copy_rounded), findsNothing);

    await tester.tap(block('USERNAME'));
    await tester.pump();

    expect(clipboard, 'alice@example.com');
    expect(find.textContaining('Username copied'), findsOneWidget);
  });

  testWidgets('tapping the password block copies it while hidden', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      VaultItem(
        id: 'login-1',
        kind: VaultItemKind.login,
        title: 'Mail',
        username: 'alice@example.com',
        password: 'hunter2',
      ),
    );

    await tester.tap(block('PASSWORD'));
    await tester.pump();

    expect(clipboard, 'hunter2');
    expect(find.textContaining('Password copied'), findsOneWidget);
  });

  testWidgets('tapping the one-time code block copies the code', (
    tester,
  ) async {
    final totp = TotpData(
      issuer: 'GitHub',
      accountName: 'alice',
      secret: 'JBSWY3DPEHPK3PXP',
    );
    await pumpSheet(
      tester,
      VaultItem(
        id: 'login-1',
        kind: VaultItemKind.login,
        title: 'GitHub',
        username: 'alice',
        totp: totp,
      ),
    );

    expect(find.byType(TotpCodeView), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsNothing);

    await tester.tap(find.text('ONE-TIME CODE'));
    await tester.pump();

    expect(clipboard, matches(RegExp(r'^\d{6,8}$')));
    expect(find.textContaining('Code copied'), findsOneWidget);
  });

  testWidgets('tapping a passkey block copies that field', (tester) async {
    await pumpSheet(
      tester,
      VaultItem(
        id: 'passkey-1',
        kind: VaultItemKind.passkey,
        title: 'GitHub passkey',
        passkey: PasskeyData(
          relyingPartyId: 'github.com',
          accountName: 'alice',
          credentialId: 'credential-abc',
        ),
      ),
    );

    await tester.tap(block('RELYING PARTY'));
    await tester.pump();
    expect(clipboard, 'github.com');
    expect(find.textContaining('Relying party copied'), findsOneWidget);

    await tester.tap(block('CREDENTIAL ID'));
    await tester.pump();
    expect(clipboard, 'credential-abc');
  });
}
