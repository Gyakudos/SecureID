import 'package:secure_id/models/accessibility_settings.dart';
import 'package:secure_id/storage/accessibility_store.dart';

/// In-memory accessibility preferences for tests.
class InMemoryAccessibilityStore implements AccessibilityStore {
  InMemoryAccessibilityStore([this.settings]);

  AccessibilitySettings? settings;
  int writes = 0;

  @override
  Future<AccessibilitySettings?> read() async => settings;

  @override
  Future<void> write(AccessibilitySettings value) async {
    settings = value;
    writes++;
  }
}
