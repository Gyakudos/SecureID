import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/vault_item.dart';
import 'package:secure_id/security/vault_crypto.dart';
import 'package:secure_id/state/vault_controller.dart';

import '../support/fake_account_session.dart';
import '../support/fake_pin_unlock.dart';
import '../support/fake_remote_vault_store.dart';
import '../support/in_memory_sync_state_store.dart';
import '../support/in_memory_vault_storage.dart';

void main() {
  const password = 'correct horse battery staple';

  VaultController device({
    required InMemoryVaultStorage storage,
    required FakeAccountSession account,
    required FakeRemoteVaultStore remote,
    required InMemorySyncStateStore syncStore,
  }) {
    return VaultController(
      storage: storage,
      pinUnlock: FakePinUnlock(),
      kdf: VaultKdfConfig.test,
      accountSession: account,
      remoteVaultStore: remote,
      syncStateStore: syncStore,
      syncDebounce: const Duration(milliseconds: 20),
    );
  }

  test('uploads the local vault when signing in', () async {
    final storage = InMemoryVaultStorage();
    final account = FakeAccountSession();
    final remote = FakeRemoteVaultStore();
    final syncStore = InMemorySyncStateStore();
    final controller = device(
      storage: storage,
      account: account,
      remote: remote,
      syncStore: syncStore,
    );
    addTearDown(controller.dispose);

    await controller.init();
    await controller.createVault(password);
    await controller.upsertItem(VaultItem.newLogin()..title = 'GitHub');

    expect(
      await controller.signIn(
        email: 'alice@example.com',
        password: 'account-secret',
      ),
      isTrue,
    );
    expect(controller.isSignedIn, isTrue);
    expect(controller.syncStatus, SyncStatus.idle);

    final uploaded = remote.vaults['user-1'];
    expect(uploaded, isNotNull);
    expect(uploaded!.revision, 1);
    expect(uploaded.envelope, storage.vault);
    expect(controller.lastSyncedAt, isNotNull);
    expect(syncStore.state?.remoteRevision, 1);
  });

  test('downloads the account vault on a fresh device', () async {
    final remote = FakeRemoteVaultStore();

    final storageA = InMemoryVaultStorage();
    final accountA = FakeAccountSession();
    final syncA = InMemorySyncStateStore();
    final a = device(
      storage: storageA,
      account: accountA,
      remote: remote,
      syncStore: syncA,
    );
    await a.init();
    await a.createVault(password);
    await a.upsertItem(VaultItem.newLogin()..title = 'Bank');
    await a.signIn(email: 'alice@example.com', password: 'account-secret');
    expect(remote.vaults['user-1']!.revision, 1);
    a.dispose();

    final storageB = InMemoryVaultStorage();
    final accountB = FakeAccountSession();
    final syncB = InMemorySyncStateStore();
    final b = device(
      storage: storageB,
      account: accountB,
      remote: remote,
      syncStore: syncB,
    );
    await b.init();
    expect(b.status, VaultStatus.needsSetup);

    expect(
      await b.signIn(email: 'alice@example.com', password: 'account-secret'),
      isTrue,
    );
    expect(b.status, VaultStatus.locked);
    expect(storageB.vault, remote.vaults['user-1']!.envelope);

    expect(await b.unlock(password), isTrue);
    expect(b.items.single.title, 'Bank');
    b.dispose();
  });

  test('detects a conflict and keeps this device\'s vault', () async {
    final remote = FakeRemoteVaultStore();

    final storageA = InMemoryVaultStorage();
    final accountA = FakeAccountSession();
    final syncA = InMemorySyncStateStore();
    final a = device(
      storage: storageA,
      account: accountA,
      remote: remote,
      syncStore: syncA,
    );
    await a.init();
    await a.createVault(password);
    await a.upsertItem(VaultItem.newLogin()..title = 'A');
    await a.signIn(email: 'alice@example.com', password: 'account-secret');
    expect(remote.vaults['user-1']!.revision, 1);

    final storageB = InMemoryVaultStorage();
    final accountB = FakeAccountSession();
    final syncB = InMemorySyncStateStore();
    final b = device(
      storage: storageB,
      account: accountB,
      remote: remote,
      syncStore: syncB,
    );
    await b.init();
    await b.createVault(password);
    await b.upsertItem(VaultItem.newLogin()..title = 'B');
    await b.signIn(email: 'alice@example.com', password: 'account-secret');
    expect(b.syncStatus, SyncStatus.conflict);
    expect(b.syncConflict, isNotNull);

    expect(await b.resolveConflict(SyncResolution.keepLocal), isTrue);
    expect(remote.vaults['user-1']!.revision, 2);
    expect(remote.vaults['user-1']!.envelope, storageB.vault);
    expect(b.syncStatus, SyncStatus.idle);

    // Device A now has both a local change and a remote change.
    await a.upsertItem(VaultItem.newLogin()..title = 'A2');
    await a.syncNow();
    expect(a.syncStatus, SyncStatus.conflict);
    expect(a.syncConflict, isNotNull);

    expect(await a.resolveConflict(SyncResolution.keepLocal), isTrue);
    expect(remote.vaults['user-1']!.revision, 3);
    expect(remote.vaults['user-1']!.envelope, storageA.vault);
    a.dispose();
    b.dispose();
  });

  test('can replace this device with the account version', () async {
    final remote = FakeRemoteVaultStore();

    final storageA = InMemoryVaultStorage();
    final accountA = FakeAccountSession();
    final syncA = InMemorySyncStateStore();
    final a = device(
      storage: storageA,
      account: accountA,
      remote: remote,
      syncStore: syncA,
    );
    await a.init();
    await a.createVault(password);
    await a.upsertItem(VaultItem.newLogin()..title = 'Account vault');
    await a.signIn(email: 'alice@example.com', password: 'account-secret');
    a.dispose();

    final storageB = InMemoryVaultStorage();
    final accountB = FakeAccountSession();
    final syncB = InMemorySyncStateStore();
    final b = device(
      storage: storageB,
      account: accountB,
      remote: remote,
      syncStore: syncB,
    );
    await b.init();
    await b.createVault(password);
    await b.upsertItem(VaultItem.newLogin()..title = 'Local vault');
    await b.signIn(email: 'alice@example.com', password: 'account-secret');
    expect(b.syncStatus, SyncStatus.conflict);

    expect(await b.resolveConflict(SyncResolution.useRemote), isTrue);
    expect(b.status, VaultStatus.locked);
    expect(storageB.vault, remote.vaults['user-1']!.envelope);

    expect(await b.unlock(password), isTrue);
    expect(b.items.single.title, 'Account vault');
    b.dispose();
  });

  test('auto-syncs after a save', () async {
    final storage = InMemoryVaultStorage();
    final account = FakeAccountSession();
    final remote = FakeRemoteVaultStore();
    final syncStore = InMemorySyncStateStore();
    final controller = device(
      storage: storage,
      account: account,
      remote: remote,
      syncStore: syncStore,
    );
    addTearDown(controller.dispose);

    await controller.init();
    await controller.createVault(password);
    await controller.signIn(
      email: 'alice@example.com',
      password: 'account-secret',
    );
    expect(remote.vaults['user-1']!.revision, 1);

    await controller.upsertItem(VaultItem.newLogin()..title = 'Later');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(remote.vaults['user-1']!.revision, 2);
    expect(remote.vaults['user-1']!.envelope, storage.vault);
    expect(controller.syncStatus, SyncStatus.idle);
  });

  test('signing out keeps the local vault and stops syncing', () async {
    final storage = InMemoryVaultStorage();
    final account = FakeAccountSession();
    final remote = FakeRemoteVaultStore();
    final syncStore = InMemorySyncStateStore();
    final controller = device(
      storage: storage,
      account: account,
      remote: remote,
      syncStore: syncStore,
    );
    addTearDown(controller.dispose);

    await controller.init();
    await controller.createVault(password);
    await controller.signIn(
      email: 'alice@example.com',
      password: 'account-secret',
    );
    final revision = remote.vaults['user-1']!.revision;

    await controller.signOut();

    expect(controller.isSignedIn, isFalse);
    expect(controller.syncStatus, SyncStatus.signedOut);
    expect(storage.vault, isNotNull);
    expect(syncStore.state, isNull);

    await controller.syncNow();
    expect(remote.vaults['user-1']!.revision, revision);
  });

  test('surfaces account sign-in failures', () async {
    final storage = InMemoryVaultStorage();
    final account = FakeAccountSession()..failNext = true;
    account.failureMessage = 'That email and password do not match an account.';
    final remote = FakeRemoteVaultStore();
    final syncStore = InMemorySyncStateStore();
    final controller = device(
      storage: storage,
      account: account,
      remote: remote,
      syncStore: syncStore,
    );
    addTearDown(controller.dispose);

    await controller.init();
    expect(
      await controller.signIn(
        email: 'alice@example.com',
        password: 'wrong-password',
      ),
      isFalse,
    );
    expect(controller.error, account.failureMessage);
    expect(controller.syncStatus, SyncStatus.signedOut);
  });

  test('reports account sync as disabled without a backend', () async {
    final controller = VaultController(
      storage: InMemoryVaultStorage(),
      pinUnlock: FakePinUnlock(),
      kdf: VaultKdfConfig.test,
    );
    addTearDown(controller.dispose);

    await controller.init();
    expect(controller.accountAvailable, isFalse);
    expect(controller.syncStatus, SyncStatus.disabled);
    expect(
      await controller.signIn(email: 'alice@example.com', password: 'secret1'),
      isFalse,
    );
    expect(controller.error, 'Account sync is not configured in this build.');
  });
}
