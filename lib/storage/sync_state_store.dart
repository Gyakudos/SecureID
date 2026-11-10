import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The last known relationship between the local vault and the account vault.
///
/// Only sync metadata is stored here; no vault contents or keys.
class SyncState {
  const SyncState({
    required this.userId,
    required this.vaultId,
    required this.remoteRevision,
    required this.localHash,
    this.syncedAt,
  });

  final String userId;
  final String vaultId;
  final int remoteRevision;

  /// SHA-256 of the envelope that was last synced.
  final String localHash;
  final DateTime? syncedAt;

  bool belongsTo(String user) => userId == user;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'userId': userId,
    'vaultId': vaultId,
    'remoteRevision': remoteRevision,
    'localHash': localHash,
    'syncedAt': syncedAt?.toUtc().toIso8601String(),
  };

  factory SyncState.fromJson(Map<String, dynamic> json) {
    final userId = json['userId'] as String? ?? '';
    final vaultId = json['vaultId'] as String? ?? '';
    final localHash = json['localHash'] as String? ?? '';
    final revision = (json['remoteRevision'] as num?)?.toInt() ?? 0;
    if (userId.isEmpty ||
        vaultId.isEmpty ||
        localHash.isEmpty ||
        revision < 0) {
      throw const FormatException('Invalid sync state.');
    }
    return SyncState(
      userId: userId,
      vaultId: vaultId,
      remoteRevision: revision,
      localHash: localHash,
      syncedAt: DateTime.tryParse(json['syncedAt'] as String? ?? ''),
    );
  }
}

abstract class SyncStateStore {
  Future<SyncState?> read();
  Future<void> write(SyncState state);
  Future<void> clear();
}

/// Stores sync metadata in `sync.json` next to the encrypted vault.
class FileSyncStateStore implements SyncStateStore {
  FileSyncStateStore({this.fileName = 'sync.json'});

  final String fileName;

  Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    await base.create(recursive: true);
    return File(p.join(base.path, fileName));
  }

  @override
  Future<SyncState?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return SyncState.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(SyncState state) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(state.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    for (final target in [file, File('${file.path}.tmp')]) {
      if (await target.exists()) await target.delete();
    }
  }
}
