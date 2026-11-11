import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secure_id/services/update_service.dart';

void main() {
  const releaseJson = {
    'tag_name': 'v1.2.0',
    'name': 'SecureID 1.2.0',
    'body': 'Fixes and a faster unlock.',
    'html_url': 'https://github.com/Gyakudos/SecureID/releases/tag/v1.2.0',
    'published_at': '2026-11-10T03:11:44Z',
    'assets': [
      {
        'name': 'SecureID-Setup-1.2.0.exe',
        'browser_download_url': 'https://github.com/Gyakudos/SecureID/releases/download/v1.2.0/SecureID-Setup-1.2.0.exe',
        'size': 9776264,
      },
      {
        'name': 'SecureID-1.2.0.apk',
        'browser_download_url': 'https://github.com/Gyakudos/SecureID/releases/download/v1.2.0/SecureID-1.2.0.apk',
        'size': 74082878,
      },
    ],
  };

  GitHubUpdateService serviceFor(
    Future<http.Response> Function(http.Request request) handler,
  ) {
    return GitHubUpdateService(client: MockClient(handler));
  }

  test('parses the latest release and its assets', () async {
    final service = serviceFor(
      (_) async => http.Response(jsonEncode(releaseJson), 200),
    );

    final update = await service.fetchLatest();

    expect(update, isNotNull);
    expect(update!.tag, 'v1.2.0');
    expect(update.version, '1.2.0');
    expect(update.title, 'SecureID 1.2.0');
    expect(update.notes, 'Fixes and a faster unlock.');
    expect(update.releaseUrl, contains('/releases/tag/v1.2.0'));
    expect(update.publishedAt, DateTime.utc(2026, 11, 10, 3, 11, 44));
    expect(update.windowsInstaller?.name, 'SecureID-Setup-1.2.0.exe');
    expect(update.androidPackage?.name, 'SecureID-1.2.0.apk');
  });

  test('requests the documented endpoint with a user agent', () async {
    late Uri seen;
    late String? agent;
    final service = serviceFor((request) async {
      seen = request.url;
      agent = request.headers['User-Agent'];
      return http.Response(jsonEncode(releaseJson), 200);
    });

    await service.fetchLatest();

    expect(seen.host, 'api.github.com');
    expect(seen.path, '/repos/Gyakudos/SecureID/releases/latest');
    expect(agent, startsWith('SecureID/'));
  });

  test('returns null when the repository has no release yet', () async {
    final service = serviceFor((_) async => http.Response('Not Found', 404));
    expect(await service.fetchLatest(), isNull);
  });

  test('reports rate limiting clearly', () async {
    final service = serviceFor((_) async => http.Response('rate limited', 403));
    await expectLater(
      service.fetchLatest(),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.message,
          'message',
          contains('rate limiting'),
        ),
      ),
    );
  });

  test('reports unexpected status codes', () async {
    final service = serviceFor((_) async => http.Response('boom', 500));
    await expectLater(
      service.fetchLatest(),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.message,
          'message',
          contains('500'),
        ),
      ),
    );
  });

  test('reports unreadable payloads', () async {
    final service = serviceFor((_) async => http.Response('not json', 200));
    await expectLater(service.fetchLatest(), throwsA(isA<UpdateException>()));
  });

  test('reports network failures', () async {
    final service = serviceFor(
      (_) async => throw http.ClientException('no route to host'),
    );
    await expectLater(
      service.fetchLatest(),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.message,
          'message',
          contains('Could not reach GitHub'),
        ),
      ),
    );
  });

  test('tolerates a release with no assets', () async {
    final service = serviceFor(
      (_) async => http.Response(
        jsonEncode({
          'tag_name': 'v2.0.0',
          'name': 'SecureID 2.0.0',
          'body': '',
          'html_url':
              'https://github.com/Gyakudos/SecureID/releases/tag/v2.0.0',
          'assets': <Object>[],
        }),
        200,
      ),
    );

    final update = await service.fetchLatest();
    expect(update!.version, '2.0.0');
    expect(update.assets, isEmpty);
    expect(update.windowsInstaller, isNull);
    expect(update.androidPackage, isNull);
  });

  test('ignores assets that are missing a download URL', () async {
    final service = serviceFor(
      (_) async => http.Response(
        jsonEncode({
          'tag_name': 'v2.0.0',
          'html_url': 'https://example.test',
          'assets': [
            {'name': 'broken.exe', 'size': 1},
            {'name': 'good.apk', 'browser_download_url': 'https://x/y.apk'},
          ],
        }),
        200,
      ),
    );

    final update = await service.fetchLatest();
    expect(update!.assets.length, 1);
    expect(update.androidPackage?.name, 'good.apk');
  });
}
