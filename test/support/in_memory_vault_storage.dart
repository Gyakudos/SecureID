import 'package:secure_id/storage/vault_storage.dart';

/// In-memory storage used by unit and widget tests.
class InMemoryVaultStorage implements VaultStorage {
  String? vault;
  String? pin;

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
}
