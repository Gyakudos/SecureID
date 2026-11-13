import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../models/vault_item.dart';
import '../security/windows_dpapi.dart';
import '../util/ids.dart';
import 'browser_password_crypto.dart';
import 'password_import.dart';

/// One browser profile that contains a Chromium `Login Data` database.
class BrowserImportProfile {
  const BrowserImportProfile({
    required this.browser,
    required this.profileName,
    required this.loginDataPath,
    required this.localStatePath,
  });

  final String browser;
  final String profileName;
  final String loginDataPath;
  final String localStatePath;

  String get label => '$browser · $profileName';
}

/// The logins read from one browser profile.
class BrowserImportSummary {
  const BrowserImportSummary({
    required this.profile,
    required this.items,
    this.appBound = 0,
    this.failed = 0,
    this.skipped = 0,
    this.warnings = const <String>[],
  });

  final BrowserImportProfile profile;
  final List<VaultItem> items;

  /// Passwords protected by app-bound encryption and therefore unreadable.
  final int appBound;

  /// Values that were present but could not be decrypted.
  final int failed;

  /// Rows with no usable username, URL or password.
  final int skipped;

  final List<String> warnings;

  int get count => items.length;

  bool get needsCsvFallback => appBound > 0 || (items.isEmpty && failed > 0);
}

/// Reads saved passwords directly from Chromium-based browsers on Windows.
///
/// Only Windows is supported: Chrome, Edge, Brave, Vivaldi, Chromium and Opera
/// all keep their passwords in a SQLite `Login Data` file. The values are
/// decrypted locally with the same Windows user that owns the browser profile.
/// Safari has no Windows build, so its CSV export is handled by
/// [PasswordCsvImport] instead.
class BrowserImportService {
  const BrowserImportService();

  bool get isSupported => Platform.isWindows;

  /// Every browser profile found on this PC.
  Future<List<BrowserImportProfile>> discoverProfiles() async {
    if (!isSupported) return const <BrowserImportProfile>[];

    final local = Platform.environment['LOCALAPPDATA'];
    final roaming = Platform.environment['APPDATA'];
    final roots = <String, String>{};
    if (local != null) {
      roots['Google Chrome'] = p.join(local, 'Google', 'Chrome', 'User Data');
      roots['Microsoft Edge'] = p.join(local, 'Microsoft', 'Edge', 'User Data');
      roots['Brave'] = p.join(
        local,
        'BraveSoftware',
        'Brave-Browser',
        'User Data',
      );
      roots['Vivaldi'] = p.join(local, 'Vivaldi', 'User Data');
      roots['Chromium'] = p.join(local, 'Chromium', 'User Data');
    }
    if (roaming != null) {
      roots['Opera'] = p.join(roaming, 'Opera Software', 'Opera Stable');
      roots['Opera GX'] = p.join(roaming, 'Opera Software', 'Opera GX Stable');
    }

    final profiles = <BrowserImportProfile>[];
    for (final entry in roots.entries) {
      final root = Directory(entry.value);
      if (!await root.exists()) continue;

      final localState = p.join(root.path, 'Local State');
      final directLoginData = p.join(root.path, 'Login Data');
      if (await File(directLoginData).exists()) {
        // Opera keeps the profile directly in the "Opera Stable" folder.
        profiles.add(
          BrowserImportProfile(
            browser: entry.key,
            profileName: 'Default',
            loginDataPath: directLoginData,
            localStatePath: localState,
          ),
        );
        continue;
      }

      final children = await root.list(followLinks: false).toList();
      for (final child in children) {
        if (child is! Directory) continue;
        final name = p.basename(child.path);
        if (name == 'System Profile' ||
            name == 'Guest Profile' ||
            name.startsWith('ShaderCache') ||
            name.startsWith('GrShaderCache') ||
            name.startsWith('GraphiteDawnCache') ||
            name.startsWith('BrowserMetrics')) {
          continue;
        }
        final loginData = p.join(child.path, 'Login Data');
        if (!await File(loginData).exists()) continue;
        profiles.add(
          BrowserImportProfile(
            browser: entry.key,
            profileName: name,
            loginDataPath: loginData,
            localStatePath: localState,
          ),
        );
      }
    }

    profiles.sort((a, b) {
      final byBrowser = a.browser.compareTo(b.browser);
      if (byBrowser != 0) return byBrowser;
      return a.profileName.compareTo(b.profileName);
    });
    return profiles;
  }

  /// Reads and decrypts every saved login in [profile].
  Future<BrowserImportSummary> importProfile(
    BrowserImportProfile profile,
  ) async {
    if (!isSupported) {
      return BrowserImportSummary(
        profile: profile,
        items: const <VaultItem>[],
        warnings: const <String>[
          'Direct browser import is only available on Windows. Export a CSV '
              'from the browser and import that file instead.',
        ],
      );
    }

    final key = await _encryptionKey(profile.localStatePath);
    final temp = await Directory.systemTemp.createTemp('secureid_browser_');
    final items = <VaultItem>[];
    final seen = <String>{};
    var appBound = 0;
    var failed = 0;
    var skipped = 0;

    try {
      final copied = p.join(temp.path, 'Login Data');
      await File(profile.loginDataPath).copy(copied);
      for (final suffix in const <String>['-wal', '-shm']) {
        final sidecar = File('${profile.loginDataPath}$suffix');
        if (await sidecar.exists()) {
          await sidecar.copy('$copied$suffix');
        }
      }

      final database = sqlite3.open(copied, mode: OpenMode.readOnly);
      try {
        final rows = database.select(
          'SELECT origin_url, username_value, password_value '
          'FROM logins WHERE blacklisted_by_user = 0',
        );
        for (final row in rows) {
          final originUrl = (row['origin_url'] as String? ?? '').trim();
          final username = (row['username_value'] as String? ?? '').trim();
          final blob = row['password_value'];
          final bytes = switch (blob) {
            Uint8List value => value,
            List<int> value => Uint8List.fromList(value),
            String value => Uint8List.fromList(utf8.encode(value)),
            _ => null,
          };

          if (bytes == null || bytes.isEmpty) {
            skipped++;
            continue;
          }

          final result = await decryptChromiumPassword(
            bytes,
            key: key,
            legacyUnprotect: WindowsDpapi.instance.unprotect,
          );
          if (result.state == ChromiumPasswordState.appBound) {
            appBound++;
            continue;
          }
          if (result.state != ChromiumPasswordState.decrypted ||
              result.password == null) {
            failed++;
            continue;
          }

          final password = result.password!;
          final title = _titleFromUrl(originUrl);
          final item = VaultItem(
            id: newId(),
            kind: VaultItemKind.login,
            title: title.isEmpty ? 'Imported login' : title,
            username: username,
            password: password,
            url: originUrl,
            tags: <String>[profile.browser],
          );
          final keyText =
              '${item.title.toLowerCase()}|${username.toLowerCase()}|'
              '${_urlKey(originUrl)}';
          if (!seen.add(keyText)) {
            skipped++;
            continue;
          }
          items.add(item);
        }
      } finally {
        database.close();
      }
    } on SqliteException catch (exception) {
      return BrowserImportSummary(
        profile: profile,
        items: const <VaultItem>[],
        warnings: <String>[
          'The ${profile.browser} password database could not be read: '
              '${exception.message}. Close the browser and try again, or '
              'export a CSV from the browser.',
        ],
      );
    } catch (exception) {
      return BrowserImportSummary(
        profile: profile,
        items: const <VaultItem>[],
        warnings: <String>[
          'Could not read the ${profile.browser} password database: '
              '$exception',
        ],
      );
    } finally {
      try {
        await temp.delete(recursive: true);
      } catch (_) {
        // A leftover temporary copy is harmless; the vault is encrypted.
      }
    }

    final warnings = <String>[];
    if (appBound > 0) {
      warnings.add(
        '$appBound password${appBound == 1 ? '' : 's'} in ${profile.label} '
        'use app-bound encryption, which Windows does not let another app '
        'read. Export a CSV from ${profile.browser} and import that file to '
        'bring them across.',
      );
    }
    if (failed > 0) {
      warnings.add(
        '$failed password${failed == 1 ? '' : 's'} could not be decrypted. '
        'Close ${profile.browser} and try again, or use its CSV export.',
      );
    }

    return BrowserImportSummary(
      profile: profile,
      items: items,
      appBound: appBound,
      failed: failed,
      skipped: skipped,
      warnings: warnings,
    );
  }

  /// Reads the AES key Chromium keeps in `Local State`.
  ///
  /// Returns null when the key is missing or app-bound; individual values then
  /// fall back to the legacy per-password DPAPI format.
  Future<List<int>?> _encryptionKey(String localStatePath) async {
    final file = File(localStatePath);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final osCrypt = decoded['os_crypt'];
      if (osCrypt is! Map) return null;
      final encoded = osCrypt['encrypted_key'];
      if (encoded is! String || encoded.isEmpty) return null;
      final raw = base64Decode(encoded);
      if (raw.length <= 5) return null;
      final prefix = ascii.decode(raw.sublist(0, 5), allowInvalid: true);
      if (prefix != 'DPAPI') return null;
      final unprotected = WindowsDpapi.instance.unprotect(
        Uint8List.fromList(raw.sublist(5)),
      );
      return unprotected.length == 32 ? unprotected : null;
    } catch (_) {
      return null;
    }
  }

  static String _titleFromUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    final host = uri?.host ?? '';
    if (host.isEmpty) return trimmed;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  static String _urlKey(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    final host = (uri?.host ?? '').toLowerCase();
    if (host.isEmpty) return trimmed.toLowerCase();
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}
