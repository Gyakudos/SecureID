import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/accessibility_settings.dart';

/// Persists display and speech preferences outside the encrypted vault.
///
/// Keeping this file separate means the preferences are available before the
/// vault is unlocked, so a low-vision user can enlarge the unlock screen.
abstract class AccessibilityStore {
  Future<AccessibilitySettings?> read();
  Future<void> write(AccessibilitySettings settings);
}

/// Stores accessibility preferences in `accessibility.json`.
class FileAccessibilityStore implements AccessibilityStore {
  FileAccessibilityStore({this.fileName = 'accessibility.json'});

  final String fileName;

  Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    await base.create(recursive: true);
    return File(p.join(base.path, fileName));
  }

  @override
  Future<AccessibilitySettings?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return AccessibilitySettings.fromJson(decoded);
    } catch (_) {
      // A damaged preferences file should never block the app.
      return null;
    }
  }

  @override
  Future<void> write(AccessibilitySettings settings) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}
