import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/supabase_config.dart';
import 'services/account_session.dart';
import 'services/device_registry.dart';
import 'services/remote_vault_store.dart';
import 'services/speech_service.dart';
import 'services/update_service.dart';
import 'state/vault_controller.dart';
import 'storage/accessibility_store.dart';
import 'storage/device_identity.dart';
import 'storage/device_login_store.dart';
import 'storage/file_vault_storage.dart';
import 'storage/sync_state_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AccountSession? accountSession;
  RemoteVaultStore? remoteVaultStore;
  SyncStateStore? syncStateStore;
  DeviceRegistry? deviceRegistry;

  if (SupabaseConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.anonKey,
      );
      final client = Supabase.instance.client;
      accountSession = SupabaseAccountSession(client);
      remoteVaultStore = SupabaseRemoteVaultStore(client);
      syncStateStore = FileSyncStateStore();
      deviceRegistry = SupabaseDeviceRegistry(client);
    } catch (error) {
      // A bad URL or an offline first run must never stop the offline vault
      // from opening. Account features simply stay disabled.
      debugPrint('SecureID account sync is disabled: $error');
    }
  }

  final controller = VaultController(
    storage: FileVaultStorage(),
    accountSession: accountSession,
    remoteVaultStore: remoteVaultStore,
    syncStateStore: syncStateStore,
    deviceRegistry: deviceRegistry,
    deviceIdentityStore: DeviceIdentityStore(),
    accessibilityStore: FileAccessibilityStore(),
    deviceLoginStore: FileDeviceLoginStore(),
    speechService: FlutterTtsSpeechService(),
    updateService: GitHubUpdateService(),
  );
  await controller.init();
  runApp(SecureIdApp(controller: controller));
}
