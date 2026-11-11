import 'package:secure_id/models/app_update.dart';
import 'package:secure_id/services/update_service.dart';

/// A GitHub stand-in that returns a fixed release or throws a fixed error.
class FakeUpdateService implements UpdateService {
  FakeUpdateService({this.release, this.error});

  AppUpdate? release;
  UpdateException? error;
  int calls = 0;
  bool fail = false;

  @override
  Future<AppUpdate?> fetchLatest() async {
    calls++;
    if (error != null) throw error!;
    if (fail) throw StateError('unexpected failure');
    return release;
  }
}

AppUpdate buildUpdate(String version) {
  return AppUpdate(
    version: version,
    tag: 'v$version',
    title: 'SecureID $version',
    releaseUrl: 'https://github.com/Gyakudos/SecureID/releases/tag/v$version',
    notes: 'Release notes for $version',
    assets: const [],
  );
}
