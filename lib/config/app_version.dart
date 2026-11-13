/// The version of the running build.
///
/// Keep this in sync with `version:` in `pubspec.yaml`. A test in
/// `test/config/app_version_test.dart` fails if the two drift apart, so the
/// update checker never compares against a stale number.
const String appVersion = '1.2.53';

/// The GitHub repository that publishes SecureID releases.
const String updateRepositoryOwner = 'Gyakudos';
const String updateRepositoryName = 'SecureID';
