import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/config/app_version.dart';
import 'package:secure_id/util/version.dart';

void main() {
  test('appVersion matches the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([^\s#]+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml has no version field');

    // `1.0.0+1` -> `1.0.0`; the build number is not part of the release tag.
    final published = match!.group(1)!.split('+').first;
    expect(
      published,
      appVersion,
      reason:
          'lib/config/app_version.dart must match pubspec.yaml so the update '
          'check compares against the real build version.',
    );
    expect(AppVersion.tryParse(appVersion), isNotNull);
  });
}
