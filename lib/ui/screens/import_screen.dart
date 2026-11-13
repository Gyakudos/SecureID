import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../models/vault_item.dart';
import '../../services/browser_import.dart';
import '../../services/password_import.dart';
import '../../state/vault_scope.dart';
import '../theme.dart';
import '../widgets/gradient_background.dart';

const XTypeGroup _csvTypeGroup = XTypeGroup(
  label: 'Password CSV',
  extensions: <String>['csv', 'txt'],
);

/// Imports logins from a CSV export or directly from an installed browser.
///
/// Everything happens on this device. The file or browser database is read in
/// memory, mapped to vault logins, encrypted with the vault key and written to
/// the same vault file as every other entry.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final BrowserImportService _browserImport = const BrowserImportService();

  PasswordImportResult? _fileResult;
  String? _fileName;
  bool _readingFile = false;

  bool _scanning = false;
  bool _scanned = false;
  List<BrowserImportProfile> _profiles = const <BrowserImportProfile>[];
  BrowserImportSummary? _browserSummary;
  String? _browserError;
  String? _readingProfile;

  bool _skipDuplicates = true;
  bool _importing = false;

  Future<void> _pickCsv() async {
    setState(() {
      _readingFile = true;
      _fileName = null;
      _fileResult = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[_csvTypeGroup],
      );
      if (file == null) {
        if (mounted) setState(() => _readingFile = false);
        return;
      }
      final bytes = await file.readAsBytes();
      final contents = _decodeText(bytes);
      final result = PasswordCsvImport.parse(contents);
      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _fileResult = result;
        _readingFile = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() => _readingFile = false);
      _snack('Could not read that file: $exception');
    }
  }

  Future<void> _scanBrowsers() async {
    setState(() {
      _scanning = true;
      _scanned = true;
      _browserSummary = null;
      _browserError = null;
      _profiles = const <BrowserImportProfile>[];
    });
    try {
      final profiles = await _browserImport.discoverProfiles();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _scanning = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _browserError = 'Could not look for browsers: $exception';
      });
    }
  }

  Future<void> _readProfile(BrowserImportProfile profile) async {
    setState(() {
      _readingProfile = profile.loginDataPath;
      _browserSummary = null;
      _browserError = null;
    });
    try {
      final summary = await _browserImport.importProfile(profile);
      if (!mounted) return;
      setState(() {
        _browserSummary = summary;
        _readingProfile = null;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _readingProfile = null;
        _browserError = 'Could not read ${profile.label}: $exception';
      });
    }
  }

  Future<void> _commit(List<VaultItem> items, String source) async {
    if (items.isEmpty) return;
    final controller = VaultScope.read(context);
    final duplicates = controller.countImportDuplicates(items);
    setState(() => _importing = true);
    try {
      final added = await controller.importItems(
        items,
        skipDuplicates: _skipDuplicates,
      );
      if (!mounted) return;
      final skipped = items.length - added;
      setState(() {
        _importing = false;
        _fileResult = null;
        _fileName = null;
        _browserSummary = null;
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(added == 0 ? 'Nothing new to import' : 'Import complete'),
          content: Text(
            added == 0
                ? 'All ${items.length} logins from $source already exist in '
                      'this vault.'
                : 'Imported $added of ${items.length} logins from $source.'
                      '${skipped > 0 ? '\n\nSkipped $skipped duplicate'
                                '${skipped == 1 ? '' : 's'}.' : ''}'
                      '${duplicates > 0 && !_skipDuplicates ? '\n\n'
                                '$duplicates matched an existing login and '
                                'were imported again.' : ''}',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (exception) {
      if (!mounted) return;
      setState(() => _importing = false);
      _snack('Could not import the logins: $exception');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _decodeText(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: false);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var index = 0; index + 1 < bytes.length; index += 2) {
      units.add(
        littleEndian
            ? bytes[index] | (bytes[index + 1] << 8)
            : (bytes[index] << 8) | bytes[index + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fileResult = _fileResult;
    final browserSummary = _browserSummary;

    return Scaffold(
      appBar: AppBar(title: const Text('Import passwords')),
      body: GradientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Bring your logins with you',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Import a CSV exported by another password manager or '
                      'browser, or read a browser profile directly on Windows. '
                      'Everything stays on this device.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    _SectionCard(
                      icon: Icons.upload_file_rounded,
                      title: 'From a CSV file',
                      subtitle:
                          'Chrome, Edge, Safari, Firefox, Bitwarden, LastPass, '
                          '1Password, Proton Pass, Dashlane, KeePass, NordPass, '
                          'Keeper, Enpass, RoboForm and generic CSV exports are '
                          'detected automatically.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (_fileName != null) ...<Widget>[
                            _FilePill(name: _fileName!),
                            const SizedBox(height: 12),
                          ],
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.icon(
                              onPressed: _readingFile || _importing
                                  ? null
                                  : _pickCsv,
                              icon: _readingFile
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.folder_open_rounded),
                              label: Text(
                                _readingFile ? 'Reading…' : 'Choose CSV file',
                              ),
                            ),
                          ),
                          if (fileResult != null) ...<Widget>[
                            const SizedBox(height: 16),
                            _ImportPreview(
                              title: '${fileResult.format.label} export',
                              count: fileResult.count,
                              skipped: fileResult.skippedRows,
                              warnings: fileResult.warnings,
                              skipDuplicates: _skipDuplicates,
                              importing: _importing,
                              onSkipChanged: (value) =>
                                  setState(() => _skipDuplicates = value),
                              onImport: () => _commit(
                                fileResult.items,
                                fileResult.format.label,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_browserImport.isSupported)
                      _SectionCard(
                        icon: Icons.travel_explore_rounded,
                        title: 'From a browser on this PC',
                        subtitle:
                            'Reads the saved passwords in Chrome, Edge, Brave, '
                            'Vivaldi, Chromium and Opera. If the browser uses '
                            'app-bound encryption, use its CSV export instead.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: _scanning || _importing
                                    ? null
                                    : _scanBrowsers,
                                icon: _scanning
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.manage_search_rounded),
                                label: Text(
                                  _scanning
                                      ? 'Looking for browsers…'
                                      : 'Find installed browsers',
                                ),
                              ),
                            ),
                            if (_scanned &&
                                !_scanning &&
                                _profiles.isEmpty) ...<Widget>[
                              const SizedBox(height: 12),
                              Text(
                                'No Chromium-based browser profiles were '
                                'found. If the browser is installed, open it '
                                'once and save a password, then try again.',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            if (_profiles.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 8),
                              for (final profile in _profiles)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.account_circle_outlined,
                                  ),
                                  title: Text(profile.browser),
                                  subtitle: Text(profile.profileName),
                                  trailing:
                                      _readingProfile == profile.loginDataPath
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : TextButton(
                                          onPressed: _importing
                                              ? null
                                              : () => _readProfile(profile),
                                          child: const Text('Read'),
                                        ),
                                ),
                            ],
                            if (_browserError != null) ...<Widget>[
                              const SizedBox(height: 12),
                              Text(
                                _browserError!,
                                style: TextStyle(color: scheme.error),
                              ),
                            ],
                            if (browserSummary != null) ...<Widget>[
                              const SizedBox(height: 12),
                              _ImportPreview(
                                title: browserSummary.profile.label,
                                count: browserSummary.count,
                                skipped: browserSummary.skipped,
                                warnings: browserSummary.warnings,
                                skipDuplicates: _skipDuplicates,
                                importing: _importing,
                                onSkipChanged: (value) =>
                                    setState(() => _skipDuplicates = value),
                                onImport: () => _commit(
                                  browserSummary.items,
                                  browserSummary.profile.browser,
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    else
                      _SectionCard(
                        icon: Icons.travel_explore_rounded,
                        title: 'From a browser',
                        subtitle:
                            'Direct browser reading is available on Windows. '
                            'On this device, export a CSV from the browser and '
                            'use the file importer above.',
                        child: const SizedBox.shrink(),
                      ),
                    const SizedBox(height: 14),
                    _ExportGuide(),
                    const SizedBox(height: 14),
                    _HintCard(
                      icon: Icons.lock_outline_rounded,
                      text:
                          'Imported passwords are protected by your master '
                          'password as soon as they are added. Delete the CSV '
                          'file afterwards; it contains your passwords in '
                          'plain text.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _FilePill extends StatelessWidget {
  const _FilePill({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.description_outlined, size: 18),
          const SizedBox(width: 8),
          Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _ImportPreview extends StatelessWidget {
  const _ImportPreview({
    required this.title,
    required this.count,
    required this.skipped,
    required this.warnings,
    required this.skipDuplicates,
    required this.importing,
    required this.onSkipChanged,
    required this.onImport,
  });

  final String title;
  final int count;
  final int skipped;
  final List<String> warnings;
  final bool skipDuplicates;
  final bool importing;
  final ValueChanged<bool> onSkipChanged;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.check_circle_outline_rounded, color: kMint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$count login${count == 1 ? '' : 's'} found in $title',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          if (skipped > 0) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              '$skipped row${skipped == 1 ? '' : 's'} skipped (empty or '
              'duplicate).',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
            ),
          ],
          for (final warning in warnings) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              warning,
              style: TextStyle(color: scheme.tertiary, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: skipDuplicates,
            onChanged: importing ? null : onSkipChanged,
            title: const Text('Skip logins that already exist'),
            subtitle: const Text(
              'Matches on title, username and website address.',
            ),
          ),
          const SizedBox(height: 4),
          FilledButton.icon(
            onPressed: importing || count == 0 ? null : onImport,
            icon: importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_done_rounded),
            label: Text(
              importing
                  ? 'Importing…'
                  : 'Import $count login${count == 1 ? '' : 's'}',
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportGuide extends StatelessWidget {
  const _ExportGuide();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ExpansionTile(
        leading: Icon(Icons.help_outline_rounded, color: scheme.primary),
        title: const Text('How to export from a browser'),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _GuideStep(
            name: 'Google Chrome',
            steps:
                'Open chrome://password-manager/settings, choose '
                '"Download file", and pick the CSV file above.',
          ),
          _GuideStep(
            name: 'Microsoft Edge',
            steps:
                'Open edge://settings/passwords, open the "…" menu next to '
                '"Saved passwords", choose "Export passwords", and pick the '
                'CSV file above.',
          ),
          _GuideStep(
            name: 'Safari',
            steps:
                'On a Mac, open Safari → File → Export → Passwords. On '
                'Windows, use the iCloud Passwords app if available. SecureID '
                'reads Safari\'s Title, URL, Username, Password, Notes and '
                'OTPAuth columns.',
          ),
          _GuideStep(
            name: 'Firefox',
            steps:
                'Open about:logins, open the menu, choose "Export logins…", '
                'and pick the CSV file above.',
          ),
          _GuideStep(
            name: 'Proton Pass',
            steps:
                'Open the Proton Pass browser extension or Windows app, go '
                'to Settings → Export, choose CSV and turn off encryption, '
                'then pick the file above. Vaults become tags and TOTP '
                'secrets are kept.',
          ),
          _GuideStep(
            name: 'Other managers',
            steps:
                'Export a CSV from Bitwarden, LastPass, 1Password, Dashlane, '
                'KeePass, NordPass, Keeper, Enpass or RoboForm. SecureID '
                'detects the column layout and imports folders, notes and '
                'authenticator secrets when they are present.',
          ),
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.name, required this.steps});

  final String name;
  final String steps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(steps, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
