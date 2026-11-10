import 'package:supabase_flutter/supabase_flutter.dart';

/// The encrypted vault envelope as stored on the server.
///
/// The server only ever sees this already-encrypted blob plus sync metadata.
class RemoteVault {
  const RemoteVault({
    required this.vaultId,
    required this.envelope,
    required this.revision,
    required this.contentHash,
    this.updatedAt,
  });

  /// Identifier derived from the envelope salt. Two devices share a vault id
  /// only when they share the same encryption salt (and therefore the same
  /// master password).
  final String vaultId;

  /// The complete encrypted `vault.json` contents.
  final String envelope;

  /// Monotonically increasing revision used for optimistic concurrency.
  final int revision;

  /// SHA-256 of [envelope], used to compare local and remote contents.
  final String contentHash;

  final DateTime? updatedAt;
}

/// Raised when an upload was based on an outdated revision.
class RemoteVaultConflict implements Exception {
  const RemoteVaultConflict();

  @override
  String toString() => 'The account vault changed on another device.';
}

/// Storage boundary for the synced encrypted vault.
abstract class RemoteVaultStore {
  Future<RemoteVault?> fetch(String userId);

  /// Uploads [envelope] only if the server still has [expectedRevision].
  ///
  /// Pass `0` to create the first row. Throws [RemoteVaultConflict] when the
  /// server revision moved on in the meantime.
  Future<RemoteVault> upload({
    required String userId,
    required String vaultId,
    required String envelope,
    required String contentHash,
    required int expectedRevision,
  });

  Future<void> delete(String userId);
}

/// Supabase implementation backed by the `vaults` table.
///
/// See `supabase/schema.sql` for the table and row-level security policies.
class SupabaseRemoteVaultStore implements RemoteVaultStore {
  SupabaseRemoteVaultStore(this._client);

  static const String table = 'vaults';

  final SupabaseClient _client;

  @override
  Future<RemoteVault?> fetch(String userId) async {
    final row = await _client
        .from(table)
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return _fromRow(row);
  }

  @override
  Future<RemoteVault> upload({
    required String userId,
    required String vaultId,
    required String envelope,
    required String contentHash,
    required int expectedRevision,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    if (expectedRevision <= 0) {
      try {
        final row = await _client
            .from(table)
            .insert({
              'user_id': userId,
              'vault_id': vaultId,
              'envelope': envelope,
              'content_hash': contentHash,
              'revision': 1,
              'updated_at': now,
            })
            .select()
            .single();
        return _fromRow(row);
      } on PostgrestException catch (error) {
        if (error.code == '23505') throw const RemoteVaultConflict();
        rethrow;
      }
    }

    // The revision predicate makes this an atomic compare-and-swap: only one
    // device can move revision N to N+1.
    final rows = await _client
        .from(table)
        .update({
          'vault_id': vaultId,
          'envelope': envelope,
          'content_hash': contentHash,
          'revision': expectedRevision + 1,
          'updated_at': now,
        })
        .eq('user_id', userId)
        .eq('revision', expectedRevision)
        .select();
    if (rows.isEmpty) throw const RemoteVaultConflict();
    return _fromRow(rows.first);
  }

  @override
  Future<void> delete(String userId) async {
    await _client.from(table).delete().eq('user_id', userId);
  }

  static RemoteVault _fromRow(Map<String, dynamic> row) {
    return RemoteVault(
      vaultId: row['vault_id'] as String? ?? '',
      envelope: row['envelope'] as String? ?? '',
      revision: (row['revision'] as num?)?.toInt() ?? 0,
      contentHash: row['content_hash'] as String? ?? '',
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? ''),
    );
  }
}
