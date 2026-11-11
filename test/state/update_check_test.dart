import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/config/app_version.dart';
import 'package:secure_id/security/vault_crypto.dart';
import 'package:secure_id/services/update_service.dart';
import 'package:secure_id/state/vault_controller.dart';
import 'package:secure_id/util/version.dart';

import '../support/fake_pin_unlock.dart';
import '../support/fake_update_service.dart';
import '../support/in_memory_vault_storage.dart';

void main() {
  late InMemoryVaultStorage storage;
  late FakeUpdateService updates;
  late VaultController controller;

  VaultController build({bool withService = true}) {
    return VaultController(
      storage: storage,
      pinUnlock: FakePinUnlock(),
      kdf: VaultKdfConfig.test,
      updateService: withService ? updates : null,
    );
  }

  setUp(() {
    storage = InMemoryVaultStorage();
    updates = FakeUpdateService();
    controller = build();
  });

  tearDown(() => controller.dispose());

  test('starts idle and exposes the running version', () {
    expect(controller.updateStatus, UpdateStatus.idle);
    expect(controller.currentVersion, appVersion);
    expect(controller.latestUpdate, isNull);
    expect(controller.updateAvailable, isFalse);
  });

  test('a newer release is offered as an update', () async {
    final current = AppVersion.tryParse(appVersion)!;
    final next = '${current.major}.${current.minor}.${current.patch + 1}';
    updates.release = buildUpdate(next);

    await controller.checkForUpdates();

    expect(controller.updateStatus, UpdateStatus.available);
    expect(controller.updateAvailable, isTrue);
    expect(controller.latestUpdate?.version, next);
    expect(controller.updateError, isNull);
    expect(controller.lastUpdateCheck, isNotNull);
  });

  test('the same version counts as up to date', () async {
    updates.release = buildUpdate(appVersion);

    await controller.checkForUpdates();

    expect(controller.updateStatus, UpdateStatus.upToDate);
    expect(controller.updateAvailable, isFalse);
  });

  test('an older release is not offered', () async {
    updates.release = buildUpdate('0.0.1');

    await controller.checkForUpdates();

    expect(controller.updateStatus, UpdateStatus.upToDate);
  });

  test('no published release counts as up to date', () async {
    updates.release = null;

    await controller.checkForUpdates();

    expect(controller.updateStatus, UpdateStatus.upToDate);
    expect(controller.latestUpdate, isNull);
  });

  test('a failed check keeps a readable message', () async {
    updates.error = const UpdateException('Could not reach GitHub.');

    await controller.checkForUpdates();

    expect(controller.updateStatus, UpdateStatus.error);
    expect(controller.updateError, 'Could not reach GitHub.');
    expect(controller.updateAvailable, isFalse);
  });

  test('an unexpected failure does not escape', () async {
    updates.fail = true;

    await controller.checkForUpdates();

    expect(controller.updateStatus, UpdateStatus.error);
    expect(controller.updateError, isNotNull);
  });

  test('a build without an update service reports that clearly', () async {
    final offline = build(withService: false);
    addTearDown(offline.dispose);

    await offline.checkForUpdates();

    expect(offline.updateStatus, UpdateStatus.error);
    expect(offline.updateError, contains('cannot check'));
  });

  test('a second check while one is running is ignored', () async {
    updates.release = buildUpdate('9.9.9');

    final first = controller.checkForUpdates();
    final second = controller.checkForUpdates();
    await Future.wait([first, second]);

    expect(updates.calls, 1);
    expect(controller.updateStatus, UpdateStatus.available);
  });

  test('dismissing the result returns to idle', () async {
    updates.release = buildUpdate('9.9.9');
    await controller.checkForUpdates();
    expect(controller.updateStatus, UpdateStatus.available);

    controller.dismissUpdateResult();

    expect(controller.updateStatus, UpdateStatus.idle);
    expect(controller.latestUpdate, isNull);
  });

  test('notifies listeners while checking and when done', () async {
    updates.release = buildUpdate('9.9.9');
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.checkForUpdates();

    expect(notifications, greaterThanOrEqualTo(2));
  });
}
