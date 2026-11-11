import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/app_update.dart';
import '../../state/vault_controller.dart';
import '../../state/vault_scope.dart';
import '../../util/date_format.dart';
import '../theme.dart';

/// Opens the update dialog and starts a check against GitHub.
///
/// The dialog reflects the controller, so it shows progress while the request
/// is in flight and the result as soon as it lands.
Future<void> showUpdateCheck(BuildContext context) async {
  final controller = VaultScope.read(context);
  if (controller.updateStatus != UpdateStatus.checking) {
    unawaited(controller.checkForUpdates());
  }
  await showDialog<void>(
    context: context,
    builder: (_) => const UpdateDialog(),
  );
}

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = VaultScope.of(context);
    final status = controller.updateStatus;
    final scheme = Theme.of(context).colorScheme;
    final update = controller.latestUpdate;

    return AlertDialog(
      icon: Icon(_icon(status), color: _color(status, scheme)),
      title: Text(_title(controller)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
        child: SingleChildScrollView(
          child: switch (status) {
            UpdateStatus.checking => const _Checking(),
            UpdateStatus.available when update != null => _Available(
              update: update,
              currentVersion: controller.currentVersion,
            ),
            UpdateStatus.upToDate => _UpToDate(
              currentVersion: controller.currentVersion,
              checkedAt: controller.lastUpdateCheck,
            ),
            UpdateStatus.error => _Failed(
              message: controller.updateError ?? 'The check did not finish.',
            ),
            _ => _UpToDate(
              currentVersion: controller.currentVersion,
              checkedAt: controller.lastUpdateCheck,
            ),
          },
        ),
      ),
      actions: _actions(context, controller, update),
    );
  }

  List<Widget> _actions(
    BuildContext context,
    VaultController controller,
    AppUpdate? update,
  ) {
    final status = controller.updateStatus;
    switch (status) {
      case UpdateStatus.checking:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ];
      case UpdateStatus.available:
        final target = _downloadTarget(update);
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          if (target != null)
            FilledButton.icon(
              onPressed: () => _open(context, target.$1),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(target.$2),
            ),
        ];
      case UpdateStatus.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: controller.checkForUpdates,
            child: const Text('Try again'),
          ),
        ];
      case UpdateStatus.upToDate:
      case UpdateStatus.idle:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: controller.checkForUpdates,
            child: const Text('Check again'),
          ),
        ];
    }
  }

  /// The best download for this platform, with a button label.
  (String, String)? _downloadTarget(AppUpdate? update) {
    if (update == null) return null;
    if (Platform.isWindows) {
      final installer = update.windowsInstaller;
      if (installer != null) return (installer.url, 'Download installer');
    }
    if (Platform.isAndroid) {
      final apk = update.androidPackage;
      if (apk != null) return (apk.url, 'Download APK');
    }
    if (update.releaseUrl.isEmpty) return null;
    return (update.releaseUrl, 'Open release page');
  }

  Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final uri = Uri.tryParse(url);
    var opened = false;
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (opened) {
      navigator.pop();
      return;
    }
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Could not open the download page in a browser.'),
        ),
      );
  }

  IconData _icon(UpdateStatus status) => switch (status) {
    UpdateStatus.checking => Icons.cloud_sync_rounded,
    UpdateStatus.available => Icons.system_update_rounded,
    UpdateStatus.upToDate => Icons.check_circle_outline_rounded,
    UpdateStatus.error => Icons.cloud_off_rounded,
    UpdateStatus.idle => Icons.system_update_rounded,
  };

  Color _color(UpdateStatus status, ColorScheme scheme) => switch (status) {
    UpdateStatus.available => kMint,
    UpdateStatus.upToDate => scheme.primary,
    UpdateStatus.error => scheme.error,
    _ => scheme.primary,
  };

  String _title(VaultController controller) =>
      switch (controller.updateStatus) {
        UpdateStatus.checking => 'Checking for updates',
        UpdateStatus.available =>
          'SecureID ${controller.latestUpdate?.version ?? ''} is available',
        UpdateStatus.upToDate => 'You are up to date',
        UpdateStatus.error => 'Update check failed',
        UpdateStatus.idle => 'Check for updates',
      };
}

class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 4),
        const LinearProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          'Looking for the newest SecureID release on GitHub.',
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
        ),
      ],
    );
  }
}

class _UpToDate extends StatelessWidget {
  const _UpToDate({required this.currentVersion, required this.checkedAt});

  final String currentVersion;
  final DateTime? checkedAt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'You are running SecureID $currentVersion, the newest version '
          'published on GitHub.',
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
        ),
        if (checkedAt != null) ...[
          const SizedBox(height: 10),
          Text(
            'Checked ${formatDateTime(checkedAt!)}.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _Available extends StatelessWidget {
  const _Available({required this.update, required this.currentVersion});

  final AppUpdate update;
  final String currentVersion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'You are on $currentVersion. The newest release is ${update.version}.',
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
        ),
        if (update.publishedAt != null) ...[
          const SizedBox(height: 6),
          Text(
            'Published ${formatDateTime(update.publishedAt!)}',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
        if (update.notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'What is new',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              update.notes,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'Your vault and settings are not touched by an update.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, style: const TextStyle(height: 1.45)),
        const SizedBox(height: 12),
        Text(
          'SecureID works offline, so you can keep using the vault without '
          'updating.',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
