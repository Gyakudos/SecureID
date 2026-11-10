import 'package:secure_id/services/remote_vault_store.dart';

/// In-memory account vault with the same revision semantics as Supabase.
class FakeRemoteVaultStore implements RemoteVaultStore {
  final Map<String, RemoteVault> vaults = {};
  int uploadCount = 0;
  bool failNextFetch = false;

  @override
  Future<RemoteVault?> fetch(String userId) async {
    if (failNextFetch) throw const FormatException('offline');
    return vaults[userId];
  }

  @override
  Future<RemoteVault> upload({
    required String userId,
    required String vaultId,
    required String envelope,
    required String contentHash,
    required int expectedRevision,
  }) async {
    final existing = vaults[userId];
    final currentRevision = existing?.revision ?? 0;
    if (expectedRevision != currentRevision) {
      throw const RemoteVaultConflict();
    }
    uploadCount++;
    final next = RemoteVault(
      vaultId: vaultId,
      envelope: envelope,
      revision: currentRevision + 1,
      contentHash: contentHash,
      updatedAt: DateTime.now().toUtc(),
    );
    vaults[userId] = next;
    return next;
  }

  @override
  Future<void> delete(String userId) async {
    vaults.remove(userId);
  }
}
