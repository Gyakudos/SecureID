/// Where the encrypted vault and its device-local unlock records live.
abstract class VaultStorage {
  Future<bool> exists();
  Future<String?> read();
  Future<void> write(String contents);
  Future<void> delete();
  Future<String> location();

  Future<bool> pinExists();
  Future<String?> readPin();
  Future<void> writePin(String contents);
  Future<void> deletePin();

  Future<bool> quickUnlockExists();
  Future<String?> readQuickUnlock();
  Future<void> writeQuickUnlock(String contents);
  Future<void> deleteQuickUnlock();
}
