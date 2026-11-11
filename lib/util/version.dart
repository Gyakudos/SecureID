/// A comparable `major.minor.patch` version.
///
/// Release tags on GitHub look like `v1.2.3`, `1.2.3` or `1.2.3+4`, and some
/// carry a pre-release suffix such as `1.2.3-beta.1`. [tryParse] normalises all
/// of those to three integers so they can be compared without a dependency.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// Parses [raw], returning null when it is not a usable version.
  ///
  /// A pre-release suffix is dropped, so `1.2.3-beta` compares equal to
  /// `1.2.3`. That is deliberate: the update check uses GitHub's "latest"
  /// endpoint, which never returns a pre-release.
  static AppVersion? tryParse(String? raw) {
    if (raw == null) return null;
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }
    text = text.split('+').first;
    text = text.split('-').first;
    if (text.isEmpty) return null;

    final parts = text.split('.');
    if (parts.length > 3) return null;

    final numbers = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0) return null;
      numbers.add(value);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return AppVersion(numbers[0], numbers[1], numbers[2]);
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
