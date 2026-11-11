import '../util/version.dart';

/// A downloadable file attached to a GitHub release.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final String url;
  final int size;

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: json['name'] as String? ?? '',
      url: json['browser_download_url'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isUsable => name.isNotEmpty && url.isNotEmpty;
}

/// The newest published GitHub release.
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.tag,
    required this.title,
    required this.releaseUrl,
    required this.notes,
    required this.assets,
    this.publishedAt,
  });

  /// Normalised version, for example `1.1.0`. Falls back to the raw tag when
  /// the tag is not a version number.
  final String version;

  /// The tag as published, for example `v1.1.0`.
  final String tag;

  final String title;
  final String releaseUrl;
  final String notes;
  final List<ReleaseAsset> assets;
  final DateTime? publishedAt;

  factory AppUpdate.fromJson(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String? ?? '').trim();
    final parsed = AppVersion.tryParse(tag);
    final rawAssets = json['assets'];
    final assets = <ReleaseAsset>[];
    if (rawAssets is List) {
      for (final entry in rawAssets) {
        if (entry is Map<String, dynamic>) {
          final asset = ReleaseAsset.fromJson(entry);
          if (asset.isUsable) assets.add(asset);
        }
      }
    }
    return AppUpdate(
      version: parsed?.toString() ?? tag,
      tag: tag,
      title: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : tag,
      releaseUrl: json['html_url'] as String? ?? '',
      notes: (json['body'] as String? ?? '').trim(),
      assets: List.unmodifiable(assets),
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
    );
  }

  /// The Windows installer attached to this release, if there is one.
  ReleaseAsset? get windowsInstaller => _find((name) => name.endsWith('.exe'));

  /// The Android package attached to this release, if there is one.
  ReleaseAsset? get androidPackage => _find((name) => name.endsWith('.apk'));

  ReleaseAsset? _find(bool Function(String name) matches) {
    for (final asset in assets) {
      if (matches(asset.name.toLowerCase())) return asset;
    }
    return null;
  }

  /// True when [other] is a newer version than this one.
  bool isNewerThan(AppVersion other) {
    final mine = AppVersion.tryParse(version);
    return mine != null && mine > other;
  }
}
