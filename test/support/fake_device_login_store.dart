import 'package:secure_id/models/device_login.dart';
import 'package:secure_id/storage/device_login_store.dart';

/// In-memory device login preferences for tests.
class FakeDeviceLoginStore implements DeviceLoginStore {
  DeviceLoginSettings? settings;

  @override
  Future<DeviceLoginSettings?> read() async => settings;

  @override
  Future<void> write(DeviceLoginSettings value) async {
    settings = value;
  }
}
