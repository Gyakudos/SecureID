import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';

import '../config/app_version.dart';
import '../models/accessibility_settings.dart';
import '../models/app_update.dart';
import '../models/device_login.dart';
import '../models/vault_data.dart';
import '../models/vault_item.dart';
import '../models/vault_settings.dart';
import '../security/device_unlock.dart';
import '../security/pin_unlock.dart';
import '../security/quick_unlock.dart';
import '../security/vault_crypto.dart';
import '../services/account_session.dart';
import '../services/device_registry.dart';
import '../services/remote_vault_store.dart';
import '../services/speech_service.dart';
import '../services/update_service.dart';
import '../storage/accessibility_store.dart';
import '../storage/device_identity.dart';
import '../storage/device_login_store.dart';
import '../storage/sync_state_store.dart';
import '../storage/vault_storage.dart';
import '../util/version.dart';

enum VaultStatus { initializing, needsSetup, locked, unlocked }

/// The state of the manual GitHub update check.
enum UpdateStatus { idle, checking, upToDate, available, error }

enum SyncStatus { disabled, signedOut, idle, syncing, conflict, error }

enum SyncResolution { keepLocal, useRemote }

/// A local and account vault that both changed since the last sync.
class SyncConflict {
  const SyncConflict({
    required this.remote,
    required this.localHash,
    required this.localVaultId,
  });

  final RemoteVault remote;
  final String localHash;
  final String localVaultId;

  /// True when both sides hold the same vault (same salt), so the account
  /// version can be decrypted with the key already in memory.
  bool get sameVault => remote.vaultId == localVaultId;

  DateTime? get remoteUpdatedAt => remote.updatedAt;
}

class VaultController extends ChangeNotifier {
  VaultController({
    required VaultStorage storage,
    PinUnlock? pinUnlock,
    VaultKdfConfig kdf = const VaultKdfConfig(),
    DateTime Function()? now,
    AccountSession? accountSession,
    RemoteVaultStore? remoteVaultStore,
    SyncStateStore? syncStateStore,
    DeviceRegistry? deviceRegistry,
    DeviceIdentityStore? deviceIdentityStore,
    AccessibilityStore? accessibilityStore,
    DeviceLoginStore? deviceLoginStore,
    SpeechService? speechService,
    UpdateService? updateService,
    QuickUnlockConfig quickUnlockConfig = const QuickUnlockConfig(),
    Duration syncDebounce = const Duration(seconds: 2),
  }) : _storage = storage, // ignore: prefer_initializing_formals
       _pin = pinUnlock ?? createDeviceUnlock(),
       // ignore: prefer_initializing_formals
       _kdf = kdf,
       _now = now ?? DateTime.now,
       // ignore: prefer_initializing_formals
       _account = accountSession,
       // ignore: prefer_initializing_formals
       _remoteVaults = remoteVaultStore,
       // ignore: prefer_initializing_formals
       _syncStateStore = syncStateStore,
       // ignore: prefer_initializing_formals
       _deviceRegistry = deviceRegistry,
       // ignore: prefer_initializing_formals
       _deviceIdentityStore = deviceIdentityStore,
       // ignore: prefer_initializing_formals
       _accessibilityStore = accessibilityStore,
       // ignore: prefer_initializing_formals
       _deviceLoginStore = deviceLoginStore,
       // ignore: prefer_initializing_formals
       _speech = speechService,
       // ignore: prefer_initializing_formals
       _updates = updateService,
       // ignore: prefer_initializing_formals
       _quickConfig = quickUnlockConfig,
       // ignore: prefer_initializing_formals
       _syncDebounce = syncDebounce;

  static const int minMasterPasswordLength = 12;

  final VaultStorage _storage;
  final PinUnlock _pin;
  final VaultKdfConfig _kdf;
  final DateTime Function() _now;
  final AccountSession? _account;
  final RemoteVaultStore? _remoteVaults;
  final SyncStateStore? _syncStateStore;
  final DeviceRegistry? _deviceRegistry;
  final DeviceIdentityStore? _deviceIdentityStore;
  final AccessibilityStore? _accessibilityStore;
  final DeviceLoginStore? _deviceLoginStore;
  final SpeechService? _speech;
  final UpdateService? _updates;
  final QuickUnlockConfig _quickConfig;
  final Duration _syncDebounce;

  VaultStatus _status = VaultStatus.initializing;
  VaultData? _data;
  VaultEnvelope? _envelope;
  SecretKey? _key;
  Uint8List? _keyBytes;
  String? _error;
  bool _busy = false;
  bool _pinAvailable = false;
  bool _pinEnabled = false;
  DateTime? _lastActivity;
  DateTime? _lastSavedAt;
  Timer? _autoLockTimer;
  Timer? _syncTimer;
  StreamSubscription<AccountUser?>? _accountSub;
  Future<void> _saveQueue = Future<void>.value();
  bool _disposed = false;
  bool _authInProgress = false;

  AccountUser? _user;
  SyncState? _syncState;
  SyncStatus _syncStatus = SyncStatus.disabled;
  SyncConflict? _conflict;
  String? _syncError;
  bool _syncing = false;

  DeviceIdentity? _deviceIdentity;
  List<LinkedDevice> _linkedDevices = const [];
  bool _devicesLoading = false;
  String? _devicesError;

  AccessibilitySettings _accessibility = const AccessibilitySettings();
  bool _speaking = false;
  int _speechGeneration = 0;

  DeviceLoginSettings _deviceLogin = const DeviceLoginSettings();
  QuickUnlockRecord? _quickRecord;

  UpdateStatus _updateStatus = UpdateStatus.idle;
  AppUpdate? _latestUpdate;
  String? _updateError;
  DateTime? _lastUpdateCheck;
  int _updateGeneration = 0;

  VaultStatus get status => _status;
  VaultData? get data => _data;
  List<VaultItem> get items =>
      List<VaultItem>.unmodifiable(_data?.items ?? const []);
  VaultSettings get settings => _data?.settings ?? VaultSettings();
  String? get error => _error;
  bool get isBusy => _busy;
  bool get isUnlocked => _status == VaultStatus.unlocked;
  DateTime? get lastSavedAt => _lastSavedAt;
  DateTime? get lastActivity => _lastActivity;
  bool get pinAvailable => _pinAvailable;
  bool get pinEnabled => _pinEnabled && _pinAvailable;
  bool get pinPlatformSupported => _pin.isPlatformSupported;

  /// The platform name for device unlock, e.g. "Windows Hello".
  String get pinFeatureName => _pin.featureName;

  /// The unlock button label for this platform.
  String get pinUnlockButtonLabel => _pin.unlockButtonLabel;

  /// Help text shown when device unlock is enabled.
  String get pinAvailableHint => _pin.availableHint;

  /// Help text shown when the platform has nothing enrolled yet.
  String get pinUnavailableHint => _pin.unavailableHint;

  /// The default login method chosen for this device.
  DefaultLoginMethod get defaultLogin => _deviceLogin.method;

  /// The PIN or pattern style chosen for quick unlock.
  PasswordStyle get passwordStyle => _deviceLogin.style;

  /// True when this platform can offer a PIN or pattern quick unlock.
  bool get passwordStyleSupported => Platform.isAndroid;

  /// True when a PIN or pattern has been set up on this device.
  bool get quickUnlockEnabled => _quickRecord != null;

  /// True when quick unlock has used every attempt and the master password is
  /// required.
  bool get quickUnlockLockedOut =>
      (_quickRecord?.failedAttempts ?? 0) >= QuickUnlockCrypto.maxAttempts;

  /// How many quick-unlock attempts remain before the master password is
  /// required.
  int get quickUnlockAttemptsRemaining {
    final left =
        QuickUnlockCrypto.maxAttempts - (_quickRecord?.failedAttempts ?? 0);
    return left < 0 ? 0 : left;
  }

  /// The method the lock screen should actually present. A method that is not
  /// ready on this device falls back to the master password.
  DefaultLoginMethod get effectiveDefaultLogin {
    switch (_deviceLogin.method) {
      case DefaultLoginMethod.password:
        return DefaultLoginMethod.password;
      case DefaultLoginMethod.deviceUnlock:
        return pinEnabled
            ? DefaultLoginMethod.deviceUnlock
            : DefaultLoginMethod.password;
      case DefaultLoginMethod.passwordStyle:
        return quickUnlockEnabled && !quickUnlockLockedOut
            ? DefaultLoginMethod.passwordStyle
            : DefaultLoginMethod.password;
    }
  }

  bool get accountAvailable =>
      _account != null &&
      _account.isAvailable &&
      _remoteVaults != null &&
      _syncStateStore != null;
  AccountUser? get accountUser => _user;
  bool get isSignedIn => _user != null;
  SyncStatus get syncStatus => _syncStatus;
  SyncConflict? get syncConflict => _conflict;
  String? get syncError => _syncError;
  bool get isSyncing => _syncing;
  DateTime? get lastSyncedAt => _syncState?.syncedAt;
  String? get syncedVaultId => _syncState?.vaultId;

  /// True when this build can list and register devices with an account.
  bool get deviceAvailable =>
      _deviceRegistry != null && _deviceIdentityStore != null;

  /// This installation's stable identity, once it has been loaded.
  DeviceIdentity? get deviceIdentity => _deviceIdentity;
  List<LinkedDevice> get linkedDevices =>
      List<LinkedDevice>.unmodifiable(_linkedDevices);
  bool get devicesLoading => _devicesLoading;
  String? get devicesError => _devicesError;

  /// Display and speech preferences for low-vision users. These are stored
  /// outside the encrypted vault so they apply on the setup and unlock screens.
  AccessibilitySettings get accessibility => _accessibility;

  /// True when this build can read text aloud.
  bool get speechAvailable => _speech != null;
  bool get isSpeaking => _speaking;

  /// The version of the running build, shown in Settings.
  String get currentVersion => appVersion;

  /// State of the manual GitHub update check.
  UpdateStatus get updateStatus => _updateStatus;

  /// The newest published release, once a check has succeeded.
  AppUpdate? get latestUpdate => _latestUpdate;

  /// Why the last update check failed, if it did.
  String? get updateError => _updateError;

  DateTime? get lastUpdateCheck => _lastUpdateCheck;

  bool get updateAvailable => _updateStatus == UpdateStatus.available;

  int get loginCount => _data?.loginCount ?? 0;
  int get passkeyCount => _data?.passkeyCount ?? 0;
  int get totpCount => _data?.totpCount ?? 0;

  Future<String> get location => _storage.location();

  Future<void> init() async {
    await _loadAccessibility();
    await _loadDeviceLogin();
    try {
      final exists = await _storage.exists();
      if (exists) {
        _status = VaultStatus.locked;
        _pinAvailable = await _pin.isAvailable();
        _pinEnabled = _pinAvailable && await _storage.pinExists();
      } else {
        _status = VaultStatus.needsSetup;
        _pinAvailable = false;
        _pinEnabled = false;
      }
    } catch (exception) {
      _status = VaultStatus.needsSetup;
      _error = 'Could not open the vault folder: $exception';
    }
    await ensureDeviceIdentity();
    await _restoreAccountSession();
    _safeNotify();
  }

  Future<void> _loadAccessibility() async {
    final store = _accessibilityStore;
    if (store == null) return;
    try {
      final saved = await store.read();
      if (saved != null) _accessibility = saved;
    } catch (_) {
      // A damaged preferences file falls back to the accessible defaults.
    }
  }

  /// Loads the device-local login choice and any PIN/pattern record.
  Future<void> _loadDeviceLogin() async {
    final store = _deviceLoginStore;
    if (store != null) {
      try {
        final saved = await store.read();
        if (saved != null) _deviceLogin = saved;
      } catch (_) {
        // A damaged preferences file falls back to the master password.
      }
    }
    try {
      final text = await _storage.readQuickUnlock();
      if (text == null) {
        _quickRecord = null;
        return;
      }
      final record = QuickUnlockRecord.decode(text);
      final vaultText = await _storage.read();
      final envelope = vaultText == null
          ? null
          : VaultEnvelope.decode(vaultText);
      if (envelope == null || record.vaultId != base64Encode(envelope.salt)) {
        // The record belongs to a vault that is no longer here.
        _quickRecord = null;
        await _storage.deleteQuickUnlock();
        return;
      }
      _quickRecord = record;
    } catch (_) {
      _quickRecord = null;
    }
  }

  /// Applies and persists vision/accessibility preferences.
  Future<void> updateAccessibility(AccessibilitySettings next) async {
    final wasReading = _accessibility.readAloud;
    _accessibility = next;
    if (wasReading && !next.readAloud) {
      await stopSpeaking();
    }
    _safeNotify();
    try {
      await _accessibilityStore?.write(next);
    } catch (_) {
      // Preferences are cosmetic; the in-memory value still applies.
    }
  }

  /// Reads [text] aloud with the platform voice.
  Future<void> speak(String text) async {
    final speech = _speech;
    if (speech == null || text.trim().isEmpty) return;
    final generation = ++_speechGeneration;
    _speaking = true;
    _safeNotify();
    try {
      await speech.stop();
      if (generation != _speechGeneration) return;
      await speech.speak(text);
    } catch (_) {
      // Speech is an enhancement; never let a voice failure block the vault.
    } finally {
      if (generation == _speechGeneration) {
        _speaking = false;
        _safeNotify();
      }
    }
  }

  /// Stops any in-progress speech.
  Future<void> stopSpeaking() async {
    _speechGeneration++;
    _speaking = false;
    try {
      await _speech?.stop();
    } catch (_) {
      // Nothing to stop.
    }
    _safeNotify();
  }

  /// Asks GitHub for the newest published release and compares it with
  /// [currentVersion].
  ///
  /// Safe to call repeatedly: a check already in flight is reused, and a
  /// result that arrives after the controller is disposed is dropped.
  Future<void> checkForUpdates() async {
    final service = _updates;
    if (service == null) {
      _updateStatus = UpdateStatus.error;
      _updateError = 'This build cannot check for updates.';
      _safeNotify();
      return;
    }
    if (_updateStatus == UpdateStatus.checking) return;

    final generation = ++_updateGeneration;
    _updateStatus = UpdateStatus.checking;
    _updateError = null;
    _safeNotify();

    try {
      final latest = await service.fetchLatest();
      if (_disposed || generation != _updateGeneration) return;
      _lastUpdateCheck = _now();
      _latestUpdate = latest;

      final current = AppVersion.tryParse(appVersion);
      final remote = latest == null
          ? null
          : AppVersion.tryParse(latest.version);
      if (latest == null || current == null || remote == null) {
        // No release published, or an unreadable tag: nothing to offer.
        _updateStatus = UpdateStatus.upToDate;
      } else {
        _updateStatus = remote > current
            ? UpdateStatus.available
            : UpdateStatus.upToDate;
      }
    } on UpdateException catch (exception) {
      if (_disposed || generation != _updateGeneration) return;
      _updateStatus = UpdateStatus.error;
      _updateError = exception.message;
    } catch (_) {
      if (_disposed || generation != _updateGeneration) return;
      _updateStatus = UpdateStatus.error;
      _updateError = 'Could not check for updates. Try again later.';
    }

    _safeNotify();
  }

  /// Clears the result of the last update check.
  void dismissUpdateResult() {
    if (_updateStatus == UpdateStatus.checking) return;
    _updateStatus = UpdateStatus.idle;
    _latestUpdate = null;
    _updateError = null;
    _safeNotify();
  }

  Future<void> _restoreAccountSession() async {
    if (!accountAvailable) {
      _syncStatus = SyncStatus.disabled;
      return;
    }
    _accountSub ??= _account!.userChanges.listen(_onAccountUserChanged);
    _user = _account!.currentUser;
    if (_user == null) {
      _syncStatus = SyncStatus.signedOut;
      return;
    }
    _syncStatus = SyncStatus.idle;
    try {
      final stored = await _syncStateStore!.read();
      _syncState = stored != null && stored.belongsTo(_user!.id)
          ? stored
          : null;
    } catch (_) {
      _syncState = null;
    }
    if (_status == VaultStatus.needsSetup) {
      await _downloadRemoteIfLocalMissing();
    }
  }

  /// The Supabase SDK restores a persisted session asynchronously. This keeps
  /// the controller in step when that happens (or when the session expires).
  void _onAccountUserChanged(AccountUser? user) {
    if (_disposed) return;
    final previousId = _user?.id;
    _user = user;
    if (_authInProgress) {
      if (user != null) _syncStatus = SyncStatus.idle;
      _safeNotify();
      return;
    }
    if (user == null) {
      if (previousId == null) return;
      _syncState = null;
      _conflict = null;
      _syncError = null;
      _syncStatus = accountAvailable
          ? SyncStatus.signedOut
          : SyncStatus.disabled;
      _safeNotify();
      return;
    }
    if (user.id == previousId) {
      _safeNotify();
      return;
    }
    _syncState = null;
    _conflict = null;
    _syncError = null;
    _syncStatus = SyncStatus.idle;
    _safeNotify();
    unawaited(_adoptRestoredUser(user));
  }

  Future<void> _adoptRestoredUser(AccountUser user) async {
    try {
      final stored = await _syncStateStore?.read();
      _syncState = stored != null && stored.belongsTo(user.id) ? stored : null;
    } catch (_) {
      _syncState = null;
    }
    if (_status == VaultStatus.needsSetup) {
      await _downloadRemoteIfLocalMissing();
    }
    _safeNotify();
    unawaited(_touchDevice());
  }

  Future<void> _downloadRemoteIfLocalMissing() async {
    final user = _user;
    if (user == null ||
        !accountAvailable ||
        _status != VaultStatus.needsSetup) {
      return;
    }
    try {
      final remote = await _remoteVaults!.fetch(user.id);
      if (remote == null || remote.envelope.isEmpty) return;
      await _applyRemote(remote);
      _syncStatus = SyncStatus.idle;
      unawaited(_touchDevice());
    } catch (_) {
      _syncStatus = SyncStatus.error;
      _syncError =
          'Could not download your account vault. '
          'Check your connection and try again.';
    }
  }

  /// Signs in with an email and password, then reconciles the vault.
  ///
  /// On a device without a local vault, the encrypted account vault is
  /// downloaded and the app asks for the master password to unlock it.
  Future<bool> signIn({required String email, required String password}) async {
    if (!accountAvailable) {
      _fail('Account sync is not configured in this build.');
      return false;
    }
    if (_busy) return false;
    _busy = true;
    _authInProgress = true;
    _error = null;
    _syncError = null;
    _safeNotify();
    try {
      final user = await _account!.signIn(email: email, password: password);
      _user = user;
      _conflict = null;
      _syncStatus = SyncStatus.idle;
      final stored = await _syncStateStore!.read();
      _syncState = stored != null && stored.belongsTo(user.id) ? stored : null;
      if (_status == VaultStatus.needsSetup) {
        await _downloadRemoteIfLocalMissing();
      } else {
        await _runSync();
      }
      return true;
    } on AccountException catch (exception) {
      _fail(exception.message);
      return false;
    } catch (_) {
      _fail('Could not sign in. Check your connection and try again.');
      return false;
    } finally {
      _authInProgress = false;
      _busy = false;
      _safeNotify();
    }
  }

  /// Creates an account. When email confirmation is enabled in Supabase the
  /// caller should ask the user to confirm before signing in.
  Future<SignUpOutcome?> signUp({
    required String email,
    required String password,
  }) async {
    if (!accountAvailable) {
      _fail('Account sync is not configured in this build.');
      return null;
    }
    if (_busy) return null;
    _busy = true;
    _authInProgress = true;
    _error = null;
    _syncError = null;
    _safeNotify();
    try {
      final outcome = await _account!.signUp(email: email, password: password);
      if (outcome == SignUpOutcome.signedIn) {
        final user = _account.currentUser;
        if (user != null) {
          _user = user;
          _syncState = null;
          _conflict = null;
          _syncStatus = SyncStatus.idle;
          if (_status == VaultStatus.needsSetup) {
            await _downloadRemoteIfLocalMissing();
          } else {
            await _runSync();
          }
        }
      }
      return outcome;
    } on AccountException catch (exception) {
      _fail(exception.message);
      return null;
    } catch (_) {
      _fail(
        'Could not create the account. '
        'Check your connection and try again.',
      );
      return null;
    } finally {
      _authInProgress = false;
      _busy = false;
      _safeNotify();
    }
  }

  /// Signs out of the account. The local encrypted vault is kept.
  Future<void> signOut() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    _authInProgress = true;
    try {
      await _account?.signOut();
    } catch (_) {
      // Clearing the local session is what matters.
    } finally {
      _authInProgress = false;
    }
    _user = null;
    _syncState = null;
    _conflict = null;
    _syncError = null;
    _syncing = false;
    _linkedDevices = const [];
    _devicesError = null;
    _syncStatus = accountAvailable ? SyncStatus.signedOut : SyncStatus.disabled;
    try {
      await _syncStateStore?.clear();
    } catch (_) {
      // Stale metadata is harmless; the next sign-in reconciles by hash.
    }
    _safeNotify();
  }

  /// Reconciles the local encrypted vault with the account vault.
  Future<void> syncNow() => _runSync();

  /// Loads (or creates) this installation's stable device identity.
  Future<DeviceIdentity?> ensureDeviceIdentity() async {
    final store = _deviceIdentityStore;
    if (store == null) return null;
    final cached = _deviceIdentity;
    if (cached != null) return cached;
    try {
      final identity = await store.load();
      _deviceIdentity = identity;
      return identity;
    } catch (_) {
      return null;
    }
  }

  /// Registers this device with the signed-in account.
  ///
  /// The device list is informational, so a failure here never blocks syncing.
  Future<void> _touchDevice() async {
    final registry = _deviceRegistry;
    final user = _user;
    if (registry == null || user == null) return;
    final identity = await ensureDeviceIdentity();
    if (identity == null) return;
    try {
      final registered = await registry.register(
        deviceId: identity.id,
        name: identity.name,
        platform: identity.platform,
      );
      _upsertLinkedDevice(registered.copyWith(isThisDevice: true));
      _safeNotify();
    } catch (_) {
      // Offline or not provisioned yet: try again on the next sync.
    }
  }

  void _upsertLinkedDevice(LinkedDevice device) {
    final next = [
      for (final existing in _linkedDevices)
        if (existing.deviceId != device.deviceId) existing,
      device,
    ];
    next.sort((a, b) => _deviceTime(b).compareTo(_deviceTime(a)));
    _linkedDevices = next;
  }

  static DateTime _deviceTime(LinkedDevice device) =>
      device.lastSeen ??
      device.createdAt ??
      DateTime.fromMillisecondsSinceEpoch(0);

  /// Loads the devices linked to the signed-in account.
  Future<void> refreshLinkedDevices() async {
    final registry = _deviceRegistry;
    if (registry == null || _user == null) {
      _linkedDevices = const [];
      _devicesError = null;
      _safeNotify();
      return;
    }
    if (_devicesLoading) return;
    _devicesLoading = true;
    _devicesError = null;
    _safeNotify();
    await _touchDevice();
    final identity = await ensureDeviceIdentity();
    try {
      final devices = await registry.list();
      _linkedDevices = [
        for (final device in devices)
          device.copyWith(
            isThisDevice: identity != null && device.deviceId == identity.id,
          ),
      ];
      _linkedDevices.sort((a, b) => _deviceTime(b).compareTo(_deviceTime(a)));
    } catch (exception) {
      _devicesError = exception is AccountException
          ? exception.message
          : 'Could not load your linked devices. Check your connection.';
    } finally {
      _devicesLoading = false;
      _safeNotify();
    }
  }

  /// Removes another device from the account's device list.
  Future<bool> removeLinkedDevice(String deviceId) async {
    final registry = _deviceRegistry;
    if (registry == null || _user == null) return false;
    final identity = _deviceIdentity;
    if (identity != null && identity.id == deviceId) {
      _devicesError = 'Sign out on that device instead of removing it here.';
      _safeNotify();
      return false;
    }
    try {
      await registry.remove(deviceId);
      _linkedDevices = [
        for (final device in _linkedDevices)
          if (device.deviceId != deviceId) device,
      ];
      _devicesError = null;
      _safeNotify();
      return true;
    } catch (exception) {
      _devicesError = exception is AccountException
          ? exception.message
          : 'Could not remove that device. Try again.';
      _safeNotify();
      return false;
    }
  }

  /// The raw encrypted envelope, for transfer to a linked phone.
  ///
  /// The contents are already encrypted with the vault key, so the LAN
  /// transport never sees plaintext secrets.
  Future<String?> readEncryptedEnvelope() async {
    try {
      await _saveQueue;
      final text = await _storage.read();
      if (text == null || text.trim().isEmpty) return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  /// Replaces this device's vault with an envelope received from another
  /// device. The vault is left locked and the master password is required.
  Future<bool> importEnvelope(String text) async {
    if (_busy) return false;
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _fail('The received link was empty.');
      return false;
    }
    _busy = true;
    _error = null;
    _safeNotify();
    try {
      final envelope = VaultEnvelope.decode(trimmed);
      await _saveQueue;
      await _storage.write(trimmed);

      _autoLockTimer?.cancel();
      _autoLockTimer = null;
      _syncTimer?.cancel();
      _syncTimer = null;
      _data = null;
      _envelope = envelope;
      _key = null;
      final bytes = _keyBytes;
      if (bytes != null) bytes.fillRange(0, bytes.length, 0);
      _keyBytes = null;
      _lastActivity = null;
      _lastSavedAt = null;

      _pinEnabled = false;
      try {
        await _storage.deletePin();
        await _pin.clearDeviceKey();
      } catch (_) {
        // A stale device unlock record is rejected on the next unlock.
      }
      await _clearQuickUnlockRecord();
      await _resetDefaultLoginIfQuick();

      _syncState = null;
      _conflict = null;
      _syncError = null;
      try {
        await _syncStateStore?.clear();
      } catch (_) {
        // Stale metadata is harmless; the next sync reconciles by hash.
      }

      _status = VaultStatus.locked;
      _pinAvailable = await _pin.isAvailable();
      return true;
    } on FormatException {
      _fail('That code is not a SecureID vault link.');
      return false;
    } catch (exception) {
      _fail('Could not import the vault: $exception');
      return false;
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  Future<void> _runSync() async {
    if (!accountAvailable || _syncing) return;
    final user = _user;
    if (user == null) {
      _syncStatus = SyncStatus.signedOut;
      _safeNotify();
      return;
    }
    _syncing = true;
    _syncError = null;
    _conflict = null;
    _syncStatus = SyncStatus.syncing;
    _safeNotify();
    try {
      var retried = false;
      while (true) {
        try {
          await _syncOnce(user);
          break;
        } on RemoteVaultConflict {
          if (retried) rethrow;
          retried = true;
        }
      }
      if (_syncStatus != SyncStatus.conflict) {
        _syncStatus = SyncStatus.idle;
        unawaited(_touchDevice());
      }
    } on RemoteVaultConflict {
      _syncStatus = SyncStatus.error;
      _syncError =
          'The account vault changed again while syncing. '
          'Tap Sync now to review it.';
    } catch (exception) {
      _syncStatus = SyncStatus.error;
      _syncError = _syncFailureMessage(exception);
    } finally {
      _syncing = false;
      _safeNotify();
    }
  }

  Future<void> _syncOnce(AccountUser user) async {
    await _saveQueue;
    final localText = await _storage.read();
    final stored = await _syncStateStore!.read();
    final state = stored != null && stored.belongsTo(user.id) ? stored : null;
    final remote = await _remoteVaults!.fetch(user.id);

    if (localText == null) {
      if (remote != null && remote.envelope.isNotEmpty) {
        await _applyRemote(remote);
      }
      return;
    }

    final local = VaultEnvelope.decode(localText);
    final localHash = _hash(localText);

    if (remote == null) {
      await _uploadLocal(
        user: user,
        local: local,
        text: localText,
        hash: localHash,
        expectedRevision: 0,
      );
      return;
    }

    if (state == null) {
      if (remote.contentHash == localHash) {
        await _recordSynced(user, local, remote, localHash);
      } else {
        _setConflict(local, remote, localHash);
      }
      return;
    }

    final localChanged = state.localHash != localHash;
    final remoteChanged = state.remoteRevision != remote.revision;
    if (!localChanged && !remoteChanged) return;

    if (localChanged && !remoteChanged) {
      await _uploadLocal(
        user: user,
        local: local,
        text: localText,
        hash: localHash,
        expectedRevision: remote.revision,
      );
      return;
    }

    if (!localChanged && remoteChanged) {
      await _applyRemote(remote);
      return;
    }

    if (remote.contentHash == localHash) {
      await _recordSynced(user, local, remote, localHash);
    } else {
      _setConflict(local, remote, localHash);
    }
  }

  void _setConflict(VaultEnvelope local, RemoteVault remote, String localHash) {
    _conflict = SyncConflict(
      remote: remote,
      localHash: localHash,
      localVaultId: local.vaultId,
    );
    _syncStatus = SyncStatus.conflict;
  }

  Future<void> _uploadLocal({
    required AccountUser user,
    required VaultEnvelope local,
    required String text,
    required String hash,
    required int expectedRevision,
  }) async {
    final uploaded = await _remoteVaults!.upload(
      userId: user.id,
      vaultId: local.vaultId,
      envelope: text,
      contentHash: hash,
      expectedRevision: expectedRevision,
    );
    await _recordSynced(user, local, uploaded, hash);
  }

  Future<void> _recordSynced(
    AccountUser user,
    VaultEnvelope local,
    RemoteVault remote,
    String localHash,
  ) async {
    final state = SyncState(
      userId: user.id,
      vaultId: local.vaultId,
      remoteRevision: remote.revision,
      localHash: localHash,
      syncedAt: _now(),
    );
    await _syncStateStore!.write(state);
    _syncState = state;
  }

  /// Replaces the local vault with the account version.
  Future<void> _applyRemote(RemoteVault remote) async {
    final user = _user;
    if (user == null) return;
    final incoming = VaultEnvelope.decode(remote.envelope);
    final current = _envelope;
    final sameVault = current != null && current.vaultId == incoming.vaultId;
    final key = _key;

    await _storage.write(remote.envelope);

    if (!sameVault) {
      _pinEnabled = false;
      try {
        await _storage.deletePin();
        await _pin.clearDeviceKey();
      } catch (_) {
        // A stale device unlock record is rejected on the next unlock.
      }
      await _clearQuickUnlockRecord();
      await _resetDefaultLoginIfQuick();
    }

    if (_status == VaultStatus.unlocked && sameVault && key != null) {
      try {
        final plaintext = await VaultCrypto.decrypt(key, incoming.payload);
        final decoded = jsonDecode(plaintext);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('The vault contents are not valid.');
        }
        _data = VaultData.fromJson(decoded);
        _envelope = incoming;
        _lastSavedAt = _now();
        _lastActivity = _now();
        _scheduleAutoLock();
      } catch (_) {
        lock();
      }
    } else if (_status == VaultStatus.unlocked) {
      lock();
    } else {
      _envelope = null;
      if (_status == VaultStatus.needsSetup) {
        _status = VaultStatus.locked;
        _pinAvailable = await _pin.isAvailable();
      }
    }

    final state = SyncState(
      userId: user.id,
      vaultId: incoming.vaultId,
      remoteRevision: remote.revision,
      localHash: remote.contentHash,
      syncedAt: _now(),
    );
    await _syncStateStore!.write(state);
    _syncState = state;
  }

  /// Resolves a [SyncConflict] by either uploading this device's vault or
  /// replacing it with the account version.
  Future<bool> resolveConflict(SyncResolution resolution) async {
    final conflict = _conflict;
    final user = _user;
    if (conflict == null || user == null || !accountAvailable || _syncing) {
      return false;
    }
    _syncing = true;
    _syncError = null;
    _safeNotify();
    try {
      await _saveQueue;
      if (resolution == SyncResolution.keepLocal) {
        final localText = await _storage.read();
        if (localText == null) {
          throw const FormatException('There is no local vault to upload.');
        }
        final local = VaultEnvelope.decode(localText);
        await _uploadLocal(
          user: user,
          local: local,
          text: localText,
          hash: _hash(localText),
          expectedRevision: conflict.remote.revision,
        );
      } else {
        await _applyRemote(conflict.remote);
      }
      _conflict = null;
      _syncStatus = SyncStatus.idle;
      _safeNotify();
      return true;
    } on RemoteVaultConflict {
      _syncStatus = SyncStatus.error;
      _syncError =
          'The account vault changed again. '
          'Sync again to review the latest version.';
      return false;
    } catch (exception) {
      _syncStatus = SyncStatus.error;
      _syncError = _syncFailureMessage(exception);
      return false;
    } finally {
      _syncing = false;
      _safeNotify();
    }
  }

  void _scheduleAutoSync() {
    if (!accountAvailable || _user == null) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(_syncDebounce, () {
      if (!_disposed && _user != null) {
        unawaited(_runSync());
      }
    });
  }

  static String _hash(String text) =>
      crypto.sha256.convert(utf8.encode(text)).toString();

  static String _syncFailureMessage(Object exception) {
    if (exception is AccountException) return exception.message;
    if (exception is FormatException) {
      return 'The account vault could not be read.';
    }
    return 'Could not sync with your account. '
        'Check your connection and try again.';
  }

  Future<bool> createVault(String password) async {
    if (_busy) return false;
    if (password.length < minMasterPasswordLength) {
      _fail(
        'Use at least $minMasterPasswordLength characters for the master password.',
      );
      return false;
    }
    _busy = true;
    _error = null;
    _safeNotify();
    try {
      final data = VaultData();
      final sealed = await VaultCrypto.create(
        password: password,
        plaintext: jsonEncode(data.toJson()),
        config: _kdf,
      );
      await _storage.write(sealed.envelope.encode());
      _data = data;
      _envelope = sealed.envelope;
      _key = sealed.key;
      _keyBytes = Uint8List.fromList(await sealed.key.extractBytes());
      _status = VaultStatus.unlocked;
      _pinEnabled = false;
      await _clearQuickUnlockRecord();
      await _resetDefaultLoginIfQuick();
      _lastActivity = _now();
      _lastSavedAt = _now();
      _scheduleAutoLock();
      _scheduleAutoSync();
      return true;
    } catch (exception) {
      _error = 'Could not create the vault: $exception';
      return false;
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  Future<bool> unlock(String password) async {
    if (_busy) return false;
    if (password.isEmpty) {
      _fail('Enter your master password.');
      return false;
    }
    _busy = true;
    _error = null;
    _safeNotify();
    try {
      final text = await _storage.read();
      if (text == null) {
        _status = VaultStatus.needsSetup;
        _error = 'No vault was found. Create a new one or restore a backup.';
        return false;
      }
      final envelope = VaultEnvelope.decode(text);
      final key = await VaultCrypto.deriveKey(
        password,
        envelope.salt,
        VaultKdfConfig(
          memory: envelope.memory,
          iterations: envelope.iterations,
          parallelism: envelope.parallelism,
        ),
      );
      final plaintext = await VaultCrypto.decrypt(key, envelope.payload);
      final decoded = jsonDecode(plaintext);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('The vault contents are not valid.');
      }
      final data = VaultData.fromJson(decoded);
      _data = data;
      _envelope = envelope;
      _key = key;
      _keyBytes = Uint8List.fromList(await key.extractBytes());
      _status = VaultStatus.unlocked;
      _lastActivity = _now();
      _lastSavedAt = _now();
      _scheduleAutoLock();

      await _reconcilePinAfterPasswordUnlock();
      _scheduleAutoSync();
      return true;
    } on SecretBoxAuthenticationError {
      _fail('Wrong master password.');
      return false;
    } on FormatException {
      _fail('That file is not a valid SecureID vault.');
      return false;
    } catch (exception) {
      _fail('Could not unlock the vault: $exception');
      return false;
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  /// Device unlock is device-specific, so the unlock record file is the source
  /// of truth rather than the synced vault settings. A record is only kept when
  /// the platform unlock is available on this device.
  Future<void> _reconcilePinAfterPasswordUnlock() async {
    try {
      final pinFileExists = await _storage.pinExists();
      _pinAvailable = await _pin.isAvailable();
      _pinEnabled = pinFileExists && _pinAvailable;
      if (!_pinEnabled && pinFileExists) {
        await _storage.deletePin();
        await _pin.clearDeviceKey();
      }
    } catch (_) {
      _pinEnabled = false;
    }
  }

  /// Opens the vault with an already-unwrapped vault key.
  ///
  /// Shared by the device-unlock and PIN/pattern paths so every route applies
  /// the same validation and post-unlock state.
  Future<bool> _openWithVaultKey(List<int> keyBytes) async {
    final vaultText = await _storage.read();
    if (vaultText == null) {
      throw const FormatException('The vault file is missing.');
    }
    if (keyBytes.length != VaultCrypto.keyLength) {
      throw const FormatException('The vault key is invalid.');
    }
    final envelope = VaultEnvelope.decode(vaultText);
    final key = SecretKey(keyBytes);
    final plaintext = await VaultCrypto.decrypt(key, envelope.payload);
    final decoded = jsonDecode(plaintext);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The vault contents are not valid.');
    }
    final data = VaultData.fromJson(decoded);
    _data = data;
    _envelope = envelope;
    _key = key;
    _keyBytes = Uint8List.fromList(keyBytes);
    _status = VaultStatus.unlocked;
    _lastActivity = _now();
    _lastSavedAt = _now();
    _scheduleAutoLock();
    return true;
  }

  /// Prompts for the platform unlock (Windows Hello or Android biometrics) and
  /// unlocks with the device-wrapped vault key.
  Future<bool> unlockWithPin() async {
    if (_busy || !_pinAvailable) return false;
    _busy = true;
    _error = null;
    _safeNotify();
    try {
      final pinText = await _storage.readPin();
      final vaultText = await _storage.read();
      if (pinText == null || vaultText == null) {
        await _discardPinRecord();
        _fail(
          'The ${_pin.featureName} record is missing. Use your master password.',
        );
        return false;
      }
      final envelope = VaultEnvelope.decode(vaultText);
      final record = PinVaultRecord.decode(pinText);
      if (record.vaultId != base64Encode(envelope.salt)) {
        await _discardPinRecord();
        _fail(
          'This ${_pin.featureName} record belongs to a different vault. '
          'Use your master password.',
        );
        return false;
      }
      final keyBytes = await _pin.unwrapVaultKey(record);
      final opened = await _openWithVaultKey(keyBytes);
      if (opened) {
        _pinEnabled = true;
        _data!.settings.pinUnlockEnabled = true;
      }
      return opened;
    } on PinUnlockCancelled {
      _fail('${_pin.featureName} was cancelled.');
      return false;
    } on PinUnlockException catch (exception) {
      await _discardPinRecord();
      _fail(exception.message);
      return false;
    } on SecretBoxAuthenticationError {
      await _discardPinRecord();
      _fail('${_pin.featureName} unlock failed. Use your master password.');
      return false;
    } on FormatException {
      await _discardPinRecord();
      _fail('${_pin.featureName} unlock failed. Use your master password.');
      return false;
    } catch (_) {
      await _discardPinRecord();
      _fail('${_pin.featureName} unlock failed. Use your master password.');
      return false;
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  /// Removes a device unlock record that can no longer unwrap the current
  /// vault (wrong vault, missing device key or failed decryption).
  Future<void> _discardPinRecord() async {
    _pinEnabled = false;
    try {
      await _storage.deletePin();
      await _pin.clearDeviceKey();
    } catch (_) {
      // Nothing else to do; the master password still works.
    }
  }

  Future<bool> enablePinUnlock() async {
    if (_status != VaultStatus.unlocked ||
        _keyBytes == null ||
        _envelope == null ||
        _data == null) {
      return false;
    }
    if (!_pin.isPlatformSupported) {
      _fail('${_pin.featureName} is not available on this platform.');
      return false;
    }
    _busy = true;
    _error = null;
    _safeNotify();
    try {
      if (!await _pin.isAvailable()) {
        _fail(_pin.unavailableHint);
        return false;
      }
      final record = await _pin.wrapVaultKey(
        vaultKey: _keyBytes!,
        salt: _envelope!.salt,
      );
      await _storage.writePin(record.encode());
      _pinAvailable = true;
      _pinEnabled = true;
      _data!.settings.pinUnlockEnabled = true;
      await save();
      return true;
    } on PinUnlockCancelled {
      _fail('${_pin.featureName} was cancelled.');
      return false;
    } on PinUnlockException catch (exception) {
      _fail(exception.message);
      return false;
    } catch (exception) {
      _fail('Could not enable ${_pin.featureName}: $exception');
      return false;
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  Future<void> disablePinUnlock() async {
    _pinEnabled = false;
    try {
      await _storage.deletePin();
      await _pin.clearDeviceKey();
    } catch (_) {
      // The vault is still safe; the stale record simply won't be used.
    }
    if (_data != null) {
      _data!.settings.pinUnlockEnabled = false;
      await save();
    }
    _safeNotify();
  }

  /// Chooses which unlock method the lock screen presents first.
  Future<bool> setDefaultLogin(DefaultLoginMethod method) async {
    if (method == DefaultLoginMethod.deviceUnlock && !pinEnabled) {
      final enabled = await enablePinUnlock();
      if (!enabled) return false;
    }
    if (method == DefaultLoginMethod.passwordStyle && !quickUnlockEnabled) {
      _fail('Set up a PIN or pattern first.');
      return false;
    }
    _deviceLogin = _deviceLogin.copyWith(method: method);
    await _persistDeviceLogin();
    _safeNotify();
    return true;
  }

  /// Chooses the PIN or pattern style used by quick unlock.
  ///
  /// An existing record is tied to the old style, so it is removed and the
  /// caller is expected to set up the new one.
  Future<void> setPasswordStyle(PasswordStyle style) async {
    if (_deviceLogin.style == style) return;
    _deviceLogin = _deviceLogin.copyWith(style: style);
    if (_quickRecord != null) await _clearQuickUnlockRecord();
    await _persistDeviceLogin();
    _safeNotify();
  }

  /// Creates a PIN or pattern that wraps the current vault key.
  ///
  /// [pin] must be six digits for [PasswordStyle.pin]; [pattern] is the ordered
  /// list of 0-8 dot indexes for [PasswordStyle.pattern].
  Future<bool> enableQuickUnlock({
    required PasswordStyle style,
    String? pin,
    List<int>? pattern,
  }) async {
    if (_status != VaultStatus.unlocked ||
        _keyBytes == null ||
        _envelope == null) {
      return false;
    }
    final String secret;
    if (style == PasswordStyle.pin) {
      final value = pin ?? '';
      if (!QuickUnlockCrypto.isValidPin(value)) {
        _fail('Use a six-digit PIN.');
        return false;
      }
      secret = value;
    } else {
      final dots = pattern ?? const <int>[];
      if (!QuickUnlockCrypto.isValidPattern(dots)) {
        _fail('Draw a pattern that uses at least four dots.');
        return false;
      }
      secret = QuickUnlockCrypto.patternSecret(dots);
    }
    _busy = true;
    _error = null;
    _safeNotify();
    try {
      final record = await QuickUnlockCrypto.create(
        vaultKey: _keyBytes!,
        vaultSalt: _envelope!.salt,
        style: style,
        secret: secret,
        config: _quickConfig,
      );
      await _storage.writeQuickUnlock(record.encode());
      _quickRecord = record;
      _deviceLogin = DeviceLoginSettings(
        method: DefaultLoginMethod.passwordStyle,
        style: style,
      );
      await _persistDeviceLogin();
      return true;
    } catch (exception) {
      _fail('Could not set up quick unlock: $exception');
      return false;
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  /// Removes the PIN/pattern record and falls back to the master password.
  Future<void> disableQuickUnlock() async {
    await _clearQuickUnlockRecord();
    if (_deviceLogin.method == DefaultLoginMethod.passwordStyle) {
      _deviceLogin = _deviceLogin.copyWith(method: DefaultLoginMethod.password);
      await _persistDeviceLogin();
    }
    _safeNotify();
  }

  /// Unlocks with the PIN or pattern set up on this device.
  Future<bool> unlockWithQuick(String secret) async {
    if (_busy) return false;
    final record = _quickRecord;
    if (record == null) {
      _fail('Set up a PIN or pattern in Settings first.');
      return false;
    }
    if (record.failedAttempts >= QuickUnlockCrypto.maxAttempts) {
      _fail('Too many attempts. Unlock with your master password.');
      return false;
    }
    _busy = true;
    _error = null;
    _safeNotify();
    try {
      final vaultText = await _storage.read();
      if (vaultText == null) {
        _fail('No vault was found. Create a new one or restore a backup.');
        return false;
      }
      final envelope = VaultEnvelope.decode(vaultText);
      if (record.vaultId != base64Encode(envelope.salt)) {
        await _clearQuickUnlockRecord();
        _fail(
          'This PIN or pattern belongs to a different vault. '
          'Use your master password.',
        );
        return false;
      }
      final keyBytes = await QuickUnlockCrypto.unlock(record, secret);
      final opened = await _openWithVaultKey(keyBytes);
      if (opened) {
        final reset = record.copyWith(failedAttempts: 0);
        _quickRecord = reset;
        try {
          await _storage.writeQuickUnlock(reset.encode());
        } catch (_) {
          // The attempt counter is best-effort; the vault is already open.
        }
      }
      return opened;
    } on SecretBoxAuthenticationError {
      final next = record.copyWith(failedAttempts: record.failedAttempts + 1);
      _quickRecord = next;
      try {
        await _storage.writeQuickUnlock(next.encode());
      } catch (_) {
        // A failed counter write only weakens the attempt limit.
      }
      final left = QuickUnlockCrypto.maxAttempts - next.failedAttempts;
      if (left <= 0) {
        _fail('Too many attempts. Unlock with your master password.');
      } else {
        _fail(
          'Wrong PIN or pattern. $left '
          '${left == 1 ? 'attempt' : 'attempts'} left.',
        );
      }
      return false;
    } on FormatException {
      await _clearQuickUnlockRecord();
      _fail('The quick-unlock record is damaged. Use your master password.');
      return false;
    } catch (exception) {
      _fail('Could not unlock the vault: $exception');
      return false;
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  Future<void> _clearQuickUnlockRecord() async {
    _quickRecord = null;
    try {
      await _storage.deleteQuickUnlock();
    } catch (_) {
      // A stale record is rejected by the vault-id check on the next unlock.
    }
  }

  Future<void> _persistDeviceLogin() async {
    try {
      await _deviceLoginStore?.write(_deviceLogin);
    } catch (_) {
      // The choice still applies for this session; the next launch keeps the
      // previously saved value.
    }
  }

  /// Returns to the master password when a PIN/pattern record is removed.
  Future<void> _resetDefaultLoginIfQuick() async {
    if (_deviceLogin.method != DefaultLoginMethod.passwordStyle) return;
    _deviceLogin = _deviceLogin.copyWith(method: DefaultLoginMethod.password);
    await _persistDeviceLogin();
  }

  void lock() {
    if (_status != VaultStatus.unlocked) return;
    _speechGeneration++;
    _speaking = false;
    unawaited(_speech?.stop() ?? Future<void>.value());
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    _data = null;
    _envelope = null;
    _key = null;
    final bytes = _keyBytes;
    if (bytes != null) bytes.fillRange(0, bytes.length, 0);
    _keyBytes = null;
    _lastActivity = null;
    _status = VaultStatus.locked;
    _error = null;
    _safeNotify();
  }

  void touch() {
    if (_status != VaultStatus.unlocked) return;
    _lastActivity = _now();
    _scheduleAutoLock();
  }

  void _scheduleAutoLock() {
    _autoLockTimer?.cancel();
    final minutes = _data?.settings.autoLockMinutes ?? 5;
    if (minutes <= 0) {
      _autoLockTimer = null;
      return;
    }
    _autoLockTimer = Timer(Duration(minutes: minutes), () {
      if (_status == VaultStatus.unlocked) lock();
    });
  }

  Future<void> save() async {
    final data = _data;
    final key = _key;
    final envelope = _envelope;
    if (data == null || key == null || envelope == null) return;
    data.updatedAt = _now().toUtc();
    final plaintext = jsonEncode(data.toJson());

    _saveQueue = _saveQueue
        .then((_) async {
          if (_status != VaultStatus.unlocked || !identical(_key, key)) return;
          final payload = await VaultCrypto.encrypt(key, plaintext);
          final next = envelope.copyWithPayload(payload);
          await _storage.write(next.encode());
          if (identical(_key, key)) {
            _envelope = next;
            _lastSavedAt = _now();
            _safeNotify();
          }
          _scheduleAutoSync();
        })
        .catchError((Object exception) {
          _error = 'Could not save the vault: $exception';
          _safeNotify();
        });
    await _saveQueue;
  }

  Future<void> upsertItem(VaultItem item) async {
    final data = _data;
    if (data == null) return;
    item.updatedAt = _now().toUtc();
    final index = data.items.indexWhere((entry) => entry.id == item.id);
    if (index == -1) {
      data.items.add(item);
    } else {
      data.items[index] = item;
    }
    _safeNotify();
    await save();
  }

  Future<void> deleteItem(String id) async {
    final data = _data;
    if (data == null) return;
    data.items.removeWhere((item) => item.id == id);
    _safeNotify();
    await save();
  }

  Future<void> toggleFavorite(String id) async {
    final data = _data;
    if (data == null) return;
    final index = data.items.indexWhere((item) => item.id == id);
    if (index == -1) return;
    data.items[index].favorite = !data.items[index].favorite;
    data.items[index].updatedAt = _now().toUtc();
    _safeNotify();
    await save();
  }

  Future<void> updateSettings(VaultSettings next) async {
    final data = _data;
    if (data == null) return;
    final pinFlag = data.settings.pinUnlockEnabled;
    next.pinUnlockEnabled = pinFlag;
    data.settings = next;
    _scheduleAutoLock();
    _safeNotify();
    await save();
  }

  Future<bool> changeMasterPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (newPassword.length < minMasterPasswordLength) {
      _fail(
        'Use at least $minMasterPasswordLength characters for the new password.',
      );
      return false;
    }
    final data = _data;
    final envelope = _envelope;
    if (data == null || envelope == null) return false;
    _busy = true;
    _error = null;
    _safeNotify();
    try {
      final currentKey = await VaultCrypto.deriveKey(
        currentPassword,
        envelope.salt,
        VaultKdfConfig(
          memory: envelope.memory,
          iterations: envelope.iterations,
          parallelism: envelope.parallelism,
        ),
      );
      await VaultCrypto.decrypt(currentKey, envelope.payload);
      await _saveQueue;

      final sealed = await VaultCrypto.create(
        password: newPassword,
        plaintext: jsonEncode(data.toJson()),
        config: _kdf,
      );
      await _storage.write(sealed.envelope.encode());
      _key = sealed.key;
      _envelope = sealed.envelope;
      final bytes = _keyBytes;
      if (bytes != null) bytes.fillRange(0, bytes.length, 0);
      _keyBytes = Uint8List.fromList(await sealed.key.extractBytes());

      if (_pinEnabled) {
        try {
          final record = await _pin.wrapVaultKey(
            vaultKey: _keyBytes!,
            salt: sealed.envelope.salt,
          );
          await _storage.writePin(record.encode());
        } catch (_) {
          _pinEnabled = false;
          data.settings.pinUnlockEnabled = false;
          await _storage.deletePin();
        }
      }

      // The quick-unlock record wraps the old vault key. Without the PIN or
      // pattern we cannot rewrap it for the new key, so it is removed.
      await _clearQuickUnlockRecord();
      await _resetDefaultLoginIfQuick();

      _lastSavedAt = _now();
      _lastActivity = _now();
      _scheduleAutoLock();
      _scheduleAutoSync();
      return true;
    } on SecretBoxAuthenticationError {
      _fail('The current master password is wrong.');
      return false;
    } on FormatException {
      _fail('Could not read the vault. The file may be damaged.');
      return false;
    } catch (exception) {
      _fail('Could not change the master password: $exception');
      return false;
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  Future<String> exportBackup() async {
    await save();
    final text = await _storage.read();
    if (text == null) {
      throw StateError('There is no vault to export.');
    }
    return text;
  }

  Future<bool> restoreFromBackup(String contents, String password) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    _safeNotify();
    try {
      final envelope = VaultEnvelope.decode(contents);
      final key = await VaultCrypto.deriveKey(
        password,
        envelope.salt,
        VaultKdfConfig(
          memory: envelope.memory,
          iterations: envelope.iterations,
          parallelism: envelope.parallelism,
        ),
      );
      final plaintext = await VaultCrypto.decrypt(key, envelope.payload);
      final decoded = jsonDecode(plaintext);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('The vault contents are not valid.');
      }
      final data = VaultData.fromJson(decoded);

      await _storage.write(contents);
      await _storage.deletePin();
      _pinEnabled = false;
      data.settings.pinUnlockEnabled = false;
      await _clearQuickUnlockRecord();
      await _resetDefaultLoginIfQuick();

      _data = data;
      _envelope = envelope;
      _key = key;
      _keyBytes = Uint8List.fromList(await key.extractBytes());
      _status = VaultStatus.unlocked;
      _lastActivity = _now();
      _lastSavedAt = _now();
      _scheduleAutoLock();
      await save();
      return true;
    } on SecretBoxAuthenticationError {
      _fail('The password for this backup is wrong.');
      return false;
    } on FormatException {
      _fail('That file is not a SecureID backup.');
      return false;
    } catch (exception) {
      _fail('Could not restore the backup: $exception');
      return false;
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  Future<void> wipeVault() async {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    try {
      await _storage.delete();
      await _storage.deletePin();
      await _storage.deleteQuickUnlock();
      await _pin.clearDeviceKey();
    } catch (_) {
      // Deleting the main file is what matters; stale PIN data is harmless.
    }
    _quickRecord = null;
    _deviceLogin = const DeviceLoginSettings();
    await _persistDeviceLogin();
    _syncState = null;
    _conflict = null;
    _syncError = null;
    try {
      await _syncStateStore?.clear();
    } catch (_) {
      // Stale metadata is harmless; the next sign-in reconciles by hash.
    }
    _data = null;
    _envelope = null;
    _key = null;
    final bytes = _keyBytes;
    if (bytes != null) bytes.fillRange(0, bytes.length, 0);
    _keyBytes = null;
    _pinEnabled = false;
    _pinAvailable = false;
    _lastActivity = null;
    _lastSavedAt = null;
    _status = VaultStatus.needsSetup;
    _error = null;
    _safeNotify();
  }

  void handleLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        _status == VaultStatus.unlocked &&
        settings.lockOnBackground) {
      lock();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _safeNotify();
  }

  void _fail(String message) {
    _error = message;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _autoLockTimer?.cancel();
    _syncTimer?.cancel();
    unawaited(_accountSub?.cancel() ?? Future<void>.value());
    _accountSub = null;
    final speech = _speech;
    if (speech != null) unawaited(speech.dispose());
    final bytes = _keyBytes;
    if (bytes != null) bytes.fillRange(0, bytes.length, 0);
    _keyBytes = null;
    _key = null;
    super.dispose();
  }
}
