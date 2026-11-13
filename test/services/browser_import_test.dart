@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:secure_id/security/windows_dpapi.dart';
import 'package:secure_id/services/browser_import.dart';
import 'package:sqlite3/sqlite3.dart';

Future<Uint8List> chromiumBlob(
  String password,
  List<int> key,
) async {
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(password),
    secretKey: SecretKey(key),
    nonce: List<int>.generate(12, (index) => 20 + index),
  );
  return Uint8List.fromList(<int>[
    ...ascii.encode('v10'),
    ...box.nonce,
    ...box.cipherText,
    ...box.mac.bytes,
  ]);
}

void main() {
  late Directory temp;
  late BrowserImportProfile profile;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('secureid_browser_test_');
    final key = List<int>.generate(32, (index) => index + 1);
    final protected = WindowsDpapi.instance.protect(
      Uint8List.fromList(key),
    );
    final localState = File(p.join(temp.path, 'Local State'));
    await localState.writeAsString(
      jsonEncode(<String, Object>{
        'os_crypt': <String, Object>{
          'encrypted_key': base64Encode(<int>[
            ...ascii.encode('DPAPI'),
            ...protected,
          ]),
        },
      }),
    );

    final loginDataPath = p.join(temp.path, 'Login Data');
    final database = sqlite3.open(loginDataPath);
    database.execute(
      'CREATE TABLE logins ('
      'origin_url TEXT, username_value TEXT, password_value BLOB, '
      'blacklisted_by_user INTEGER)',
    );
    final blob = await chromiumBlob('browser secret', key);
    database.execute(
      'INSERT INTO logins VALUES (?, ?, ?, 0)',
      <Object?>['https://example.com/login', 'alice', blob],
    );
    database.execute(
      'INSERT INTO logins VALUES (?, ?, ?, 0)',
      <Object?>[
        'https://example.com/blocked',
        'blocked',
        Uint8List.fromList(<int>[...ascii.encode('v20'), 1, 2, 3]),
      ],
    );
    database.execute(
      'INSERT INTO logins VALUES (?, ?, ?, 1)',
      <Object?>[
        'https://example.com/blacklisted',
        'blacklisted',
        await chromiumBlob('never imported', key),
      ],
    );
    database.close();

    profile = BrowserImportProfile(
      browser: 'Google Chrome',
      profileName: 'Default',
      loginDataPath: loginDataPath,
      localStatePath: localState.path,
    );
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {
      // Best-effort cleanup.
    }
  });

  test('reads and decrypts a Chromium Login Data database', () async {
    final summary = await const BrowserImportService().importProfile(profile);

    expect(summary.count, 1);
    expect(summary.items.single.username, 'alice');
    expect(summary.items.single.password, 'browser secret');
    expect(summary.items.single.url, 'https://example.com/login');
    expect(summary.items.single.title, 'example.com');
    expect(summary.items.single.tags, contains('Google Chrome'));
    expect(summary.appBound, 1);
    expect(summary.skipped, 0);
    expect(summary.warnings, isNotEmpty);
  });
}
