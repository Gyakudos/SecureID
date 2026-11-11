import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'vault_storage.dart';

/// Stores the vault as a single encrypted JSON file in the app support folder.
///
/// Writes are atomic: the new file is written to a temporary path, the old
/// file is rotated to `.bak`, and then the temporary file is renamed into
/// place. A failed rename restores the backup.
class FileVaultStorage implements VaultStorage {
  FileVaultStorage({
    this.fileName = 'vault.json',
    this.pinFileName = 'vault.pin.json',
    this.quickUnlockFileName = 'vault.quick.json',
  });

  final String fileName;
  final String pinFileName;
  final String quickUnlockFileName;

  Future<Directory> _directory() async {
    final base = await getApplicationSupportDirectory();
    await base.create(recursive: true);
    return base;
  }

  Future<File> _file() async =>
      File(p.join((await _directory()).path, fileName));

  Future<File> _pinFile() async =>
      File(p.join((await _directory()).path, pinFileName));

  Future<File> _quickUnlockFile() async =>
      File(p.join((await _directory()).path, quickUnlockFileName));

  @override
  Future<bool> exists() async => (await _file()).exists();

  @override
  Future<String?> read() async {
    final file = await _file();
    if (await file.exists()) return file.readAsString();
    // A crash between rotating the old file and renaming the new one can
    // leave only the backup. Recover it rather than showing an empty app.
    final backup = File('${file.path}.bak');
    if (await backup.exists()) return backup.readAsString();
    return null;
  }

  @override
  Future<void> write(String contents) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');

    await temp.writeAsString(contents, flush: true);

    if (await file.exists()) {
      if (await backup.exists()) {
        await backup.delete();
      }
      await file.rename(backup.path);
    }

    try {
      await temp.rename(file.path);
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  @override
  Future<void> delete() async {
    final file = await _file();
    for (final target in [
      file,
      File('${file.path}.tmp'),
      File('${file.path}.bak'),
    ]) {
      if (await target.exists()) await target.delete();
    }
  }

  @override
  Future<String> location() async => (await _file()).path;

  @override
  Future<bool> pinExists() async => (await _pinFile()).exists();

  @override
  Future<String?> readPin() async {
    final file = await _pinFile();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> writePin(String contents) async {
    final file = await _pinFile();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(contents, flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  @override
  Future<void> deletePin() async {
    final file = await _pinFile();
    for (final target in [file, File('${file.path}.tmp')]) {
      if (await target.exists()) await target.delete();
    }
  }

  @override
  Future<bool> quickUnlockExists() async => (await _quickUnlockFile()).exists();

  @override
  Future<String?> readQuickUnlock() async {
    final file = await _quickUnlockFile();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> writeQuickUnlock(String contents) async {
    final file = await _quickUnlockFile();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(contents, flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  @override
  Future<void> deleteQuickUnlock() async {
    final file = await _quickUnlockFile();
    for (final target in [file, File('${file.path}.tmp')]) {
      if (await target.exists()) await target.delete();
    }
  }
}
