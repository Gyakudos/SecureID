import 'package:secure_id/storage/vault_storage.dart';

/// In-memory storage used by unit and widget tests.
class InMemoryVaultStorage implements VaultStorage {
  String? vault;
  String? pin;
  String? quickUnlock;

  @override
  Future<bool> exists() async => vault != null;

  @override
  Future<String?> read() async => vault;

  @override
  Future<void> write(String contents) async {
    vault = contents;
  }

  @override
  Future<void> delete() async {
    vault = null;
  }

  @override
  Future<String> location() async => 'memory://vault.json';

  @override
  Future<bool> pinExists() async => pin != null;

  @override
  Future<String?> readPin() async => pin;

  @override
  Future<void> writePin(String contents) async {
    pin = contents;
  }

  @override
  Future<void> deletePin() async {
    pin = null;
  }

  @override
  Future<bool> quickUnlockExists() async => quickUnlock != null;

  @override
  Future<String?> readQuickUnlock() async => quickUnlock;

  @override
  Future<void> writeQuickUnlock(String contents) async {
    quickUnlock = contents;
  }

  @override
  Future<void> deleteQuickUnlock() async {
    quickUnlock = null;
  }
}
