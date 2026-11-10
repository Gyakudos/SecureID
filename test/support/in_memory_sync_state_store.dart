import 'package:secure_id/storage/sync_state_store.dart';

class InMemorySyncStateStore implements SyncStateStore {
  SyncState? state;

  @override
  Future<SyncState?> read() async => state;

  @override
  Future<void> write(SyncState state) async {
    this.state = state;
  }

  @override
  Future<void> clear() async {
    state = null;
  }
}
