/// Where the encrypted vault and its optional Windows Hello record live.
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
}
