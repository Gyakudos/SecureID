import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../state/vault_controller.dart';
import '../util/date_format.dart';

const XTypeGroup _vaultTypeGroup = XTypeGroup(
  label: 'SecureID vault',
  extensions: ['vault', 'json'],
);

Future<void> exportVaultBackup(
  BuildContext context,
  VaultController controller,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final contents = await controller.exportBackup();
    final name = 'SecureID-backup-${formatBackupStamp(DateTime.now())}.vault';
    final path = await _pickSavePath(name);
    if (path == null) return;
    await File(path).writeAsString(contents, flush: true);
    messenger.showSnackBar(
      SnackBar(content: Text('Encrypted backup saved to $path')),
    );
  } catch (exception) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not export the backup: $exception')),
    );
  }
}

Future<String?> _pickSavePath(String suggestedName) async {
  if (Platform.isAndroid) {
    try {
      final directory = await getDirectoryPath();
      if (directory == null) return null;
      return p.join(directory, suggestedName);
    } catch (_) {
      return null;
    }
  }
  try {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [_vaultTypeGroup],
    );
    return location?.path;
  } on UnimplementedError {
    try {
      final directory = await getDirectoryPath();
      if (directory == null) return null;
      return p.join(directory, suggestedName);
    } catch (_) {
      return null;
    }
  } catch (_) {
    return null;
  }
}

Future<bool> restoreVaultBackup(
  BuildContext context,
  VaultController controller,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final file = await openFile(acceptedTypeGroups: const [_vaultTypeGroup]);
    if (file == null) return false;
    final contents = await file.readAsString();
    if (!context.mounted) return false;

    final password = await showDialog<String>(
      context: context,
      builder: (context) => const _BackupPasswordDialog(),
    );
    if (password == null || password.isEmpty) return false;

    final restored = await controller.restoreFromBackup(contents, password);
    if (!context.mounted) return restored;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          restored
              ? 'Backup restored. Windows Hello unlock was turned off.'
              : controller.error ?? 'Could not restore the backup.',
        ),
      ),
    );
    return restored;
  } catch (exception) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not read the backup: $exception')),
      );
    }
    return false;
  }
}

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog();

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Backup password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the master password that protected this backup when it was '
            'exported.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Master password',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              ),
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Restore'),
        ),
      ],
    );
  }
}
