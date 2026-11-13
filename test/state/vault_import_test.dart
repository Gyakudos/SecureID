import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/vault_item.dart';
import 'package:secure_id/security/vault_crypto.dart';
import 'package:secure_id/state/vault_controller.dart';

import '../support/fake_pin_unlock.dart';
import '../support/in_memory_vault_storage.dart';

VaultItem login(
  String id,
  String title, {
  String username = 'user',
  String url = 'https://example.com',
  String password = 'pw',
}) {
  return VaultItem(
    id: id,
    kind: VaultItemKind.login,
    title: title,
    username: username,
    url: url,
    password: password,
  );
}

void main() {
  late InMemoryVaultStorage storage;
  late VaultController controller;
  const password = 'correct horse battery staple';

  setUp(() {
    storage = InMemoryVaultStorage();
    controller = VaultController(
      storage: storage,
      pinUnlock: FakePinUnlock(),
      kdf: VaultKdfConfig.test,
    );
  });

  tearDown(() => controller.dispose());

  Future<void> createVault() async {
    await controller.init();
    expect(await controller.createVault(password), isTrue);
  }

  test('imports new logins and skips existing ones', () async {
    await createVault();
    await controller.upsertItem(
      login(
        'existing',
        'Example',
        username: 'user',
        url: 'https://www.example.com/login',
        password: 'old',
      ),
    );

    final incoming = <VaultItem>[
      login(
        'duplicate',
        'Example',
        username: 'USER',
        url: 'https://example.com/sign-in',
        password: 'new',
      ),
      login(
        'new',
        'Other',
        username: 'other',
        url: 'https://other.example',
        password: 'pw',
      ),
    ];

    expect(controller.countImportDuplicates(incoming), 1);
    expect(await controller.importItems(incoming), 1);

    expect(controller.items, hasLength(2));
    expect(controller.items.map((item) => item.title), contains('Other'));
  });

  test('imports duplicates when skipping is disabled', () async {
    await createVault();
    await controller.upsertItem(login('existing', 'Example'));
    final incoming = <VaultItem>[
      login('duplicate', 'Example', password: 'new'),
    ];

    expect(await controller.importItems(incoming, skipDuplicates: false), 1);
    expect(controller.items, hasLength(2));
  });

  test('persists the imported logins in the encrypted vault', () async {
    await createVault();
    final added = await controller.importItems(<VaultItem>[
      login('one', 'One'),
      login('two', 'Two'),
    ]);
    expect(added, 2);

    controller.lock();
    expect(controller.status, VaultStatus.locked);
    expect(await controller.unlock(password), isTrue);

    expect(controller.items, hasLength(2));
    expect(
      controller.items.map((item) => item.title),
      containsAll(<String>['One', 'Two']),
    );
  });

  test('returns zero for an empty import', () async {
    await createVault();

    expect(await controller.importItems(const <VaultItem>[]), 0);
    expect(controller.items, isEmpty);
  });
}
