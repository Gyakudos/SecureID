import 'package:flutter/material.dart';

import '../../services/account_session.dart';
import '../../services/device_registry.dart';
import '../../state/vault_controller.dart';
import '../../state/vault_scope.dart';
import '../../util/date_format.dart';
import '../theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/gradient_background.dart';
import 'link_phone_screen.dart';

/// Sign-in and zero-knowledge vault sync.
///
/// The master password is never sent anywhere. Supabase only stores the
/// already-encrypted vault envelope.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.popWhenVaultAppears = false});

  /// Set when opened from the setup screen: signing in can download an existing
  /// vault, so the screen should get out of the way once a vault is available.
  final bool popWhenVaultAppears;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _createMode = false;
  bool _busy = false;
  bool _obscure = true;
  String? _localError;
  String? _message;
  bool _devicesRequested = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = VaultScope.read(context);
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _localError = 'Enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _localError = 'Use at least 6 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _localError = null;
      _message = null;
    });

    if (_createMode) {
      final outcome = await controller.signUp(email: email, password: password);
      if (!mounted) return;
      if (outcome == null) {
        setState(() {
          _busy = false;
          _localError = controller.error ?? 'Could not create the account.';
        });
        return;
      }
      if (outcome == SignUpOutcome.confirmationRequired) {
        setState(() {
          _busy = false;
          _createMode = false;
          _message =
              'Account created. Check your email to confirm it, '
              'then sign in here.';
        });
        return;
      }
      _password.clear();
      setState(() => _busy = false);
      _afterAuthentication(controller);
      return;
    }

    final signedIn = await controller.signIn(email: email, password: password);
    if (!mounted) return;
    if (!signedIn) {
      setState(() {
        _busy = false;
        _localError = controller.error ?? 'Could not sign in.';
      });
      return;
    }
    _password.clear();
    setState(() => _busy = false);
    _afterAuthentication(controller);
  }

  void _afterAuthentication(VaultController controller) {
    if (!mounted) return;
    if (widget.popWhenVaultAppears &&
        controller.status != VaultStatus.needsSetup) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    _snack(
      'Signed in as ${controller.accountUser?.displayName ?? 'your account'}.',
    );
  }

  Future<void> _syncNow() async {
    final controller = VaultScope.read(context);
    await controller.syncNow();
    if (!mounted) return;
    if (controller.syncStatus == SyncStatus.conflict) {
      _snack('The vault changed on another device. Review it below.');
    } else if (controller.syncError != null) {
      _snack(controller.syncError!);
    } else {
      _snack('Vault synced.');
    }
  }

  Future<void> _removeDevice(LinkedDevice device) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove ${device.name}?',
      message:
          'It disappears from this list. The device can add itself back '
          'the next time it syncs with this account.',
      confirmLabel: 'Remove device',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final controller = VaultScope.read(context);
    final removed = await controller.removeLinkedDevice(device.deviceId);
    if (!mounted) return;
    _snack(
      removed
          ? 'Device removed.'
          : (controller.devicesError ?? 'Could not remove the device.'),
    );
  }

  Future<void> _signOut() async {
    final controller = VaultScope.read(context);
    final confirmed = await confirmAction(
      context,
      title: 'Sign out of sync?',
      message:
          'This device keeps its encrypted vault. '
          'You can sign in again at any time.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed) return;
    await controller.signOut();
    if (!mounted) return;
    _snack('Signed out. The local vault is still available.');
  }

  Future<void> _resolve(SyncResolution resolution) async {
    final useRemote = resolution == SyncResolution.useRemote;
    final confirmed = await confirmAction(
      context,
      title: useRemote
          ? 'Use the account version?'
          : 'Keep this device\'s vault?',
      message: useRemote
          ? 'The vault on this device will be replaced by the version stored '
                'in your account. If the two vaults use different master '
                'passwords, you will need the password for the account version.'
          : 'The account version will be overwritten with the vault on this '
                'device. The other device can sync it again later.',
      confirmLabel: useRemote ? 'Use account version' : 'Keep this device',
      destructive: useRemote,
    );
    if (!confirmed) return;
    if (!mounted) return;

    final controller = VaultScope.read(context);
    final resolved = await controller.resolveConflict(resolution);
    if (!mounted) return;
    if (!resolved) {
      _snack(controller.syncError ?? 'Could not resolve the conflict.');
      return;
    }
    if (controller.status != VaultStatus.unlocked) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    _snack(
      useRemote
          ? 'Account vault restored.'
          : 'This device\'s vault was uploaded.',
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = VaultScope.of(context);
    final scheme = Theme.of(context).colorScheme;

    if (controller.isSignedIn &&
        controller.deviceAvailable &&
        !_devicesRequested) {
      _devicesRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.refreshLinkedDevices();
      });
    }

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 20, 6),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Account & sync',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        Icon(
                          Icons.verified_user_outlined,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      child: !controller.accountAvailable
                          ? const _NotConfiguredCard()
                          : controller.isSignedIn
                          ? _signedIn(context, controller)
                          : _signedOut(context, controller),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _signedOut(BuildContext context, VaultController controller) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _busy || controller.isBusy;
    final error = _localError ?? controller.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.cloud_sync_outlined,
                      color: kAccent,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _createMode ? 'Create an account' : 'Sign in to sync',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Your master password never leaves this device.',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                enabled: !busy,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => busy ? null : _submit(),
                decoration: InputDecoration(
                  labelText: 'Account password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  ),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 14),
                _MessageBanner(message: error, isError: true),
              ],
              if (_message != null) ...[
                const SizedBox(height: 14),
                _MessageBanner(message: _message!, isError: false),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: busy ? null : _submit,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _createMode
                            ? Icons.person_add_alt_1_rounded
                            : Icons.login_rounded,
                      ),
                label: Text(
                  busy
                      ? (_createMode ? 'Creating account…' : 'Signing in…')
                      : (_createMode ? 'Create account' : 'Sign in'),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        _createMode = !_createMode;
                        _localError = null;
                        _message = null;
                      }),
                child: Text(
                  _createMode
                      ? 'I already have an account'
                      : 'Create a new account',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _PrivacyNote(),
      ],
    );
  }

  Widget _signedIn(BuildContext context, VaultController controller) {
    final scheme = Theme.of(context).colorScheme;
    final user = controller.accountUser!;
    final conflict = controller.syncConflict;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: kMint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.person_rounded, color: kMint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Signed in · zero-knowledge sync',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SyncStatusCard(controller: controller),
        if (conflict != null) ...[
          const SizedBox(height: 14),
          _ConflictCard(
            controller: controller,
            onKeepLocal: () => _resolve(SyncResolution.keepLocal),
            onUseRemote: () => _resolve(SyncResolution.useRemote),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: controller.isSyncing || _busy ? null : _syncNow,
                icon: controller.isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                label: Text(controller.isSyncing ? 'Syncing…' : 'Sync now'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: controller.isSyncing || _busy ? null : _signOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _LinkedDevicesCard(
          controller: controller,
          onLinkPhone: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const LinkPhoneScreen())),
          onRemove: _removeDevice,
        ),
        const SizedBox(height: 16),
        const _PrivacyNote(),
      ],
    );
  }
}

class _LinkedDevicesCard extends StatelessWidget {
  const _LinkedDevicesCard({
    required this.controller,
    required this.onLinkPhone,
    required this.onRemove,
  });

  final VaultController controller;
  final VoidCallback onLinkPhone;
  final void Function(LinkedDevice device) onRemove;

  IconData _platformIcon(String platform) => switch (platform) {
    'windows' => Icons.desktop_windows_rounded,
    'android' => Icons.phone_android_rounded,
    'ios' => Icons.phone_iphone_rounded,
    'macos' => Icons.laptop_mac_rounded,
    'linux' => Icons.computer_rounded,
    _ => Icons.devices_other_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final devices = controller.linkedDevices;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.devices_rounded, color: kAccent, size: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Linked devices',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (controller.devicesLoading)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  tooltip: 'Refresh device list',
                  onPressed: controller.refreshLinkedDevices,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
            ],
          ),
          if (controller.devicesError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 6, 8),
              child: Text(
                controller.devicesError!,
                style: TextStyle(color: kDanger, fontSize: 12.5, height: 1.4),
              ),
            )
          else if (devices.isEmpty && !controller.devicesLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 6, 10),
              child: Text(
                'No devices have synced yet. This device will appear after the '
                'next sync.',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          for (final device in devices)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _platformIcon(device.platform),
                color: device.isThisDevice ? kMint : scheme.onSurfaceVariant,
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (device.isThisDevice) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: kMint.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'This device',
                        style: TextStyle(color: kMint, fontSize: 10.5),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                device.lastSeen == null
                    ? device.platformLabel
                    : '${device.platformLabel} · last seen '
                          '${formatDateTime(device.lastSeen!)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: device.isThisDevice
                  ? null
                  : IconButton(
                      tooltip: 'Remove device',
                      onPressed: () => onRemove(device),
                      icon: Icon(
                        Icons.link_off_rounded,
                        size: 19,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
            ),
          const Divider(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.qr_code_2_rounded, color: kMint),
            title: const Text('Link another phone'),
            subtitle: const Text(
              'Send this encrypted vault over your local network. Works '
              'offline, even without an account.',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onLinkPhone,
          ),
        ],
      ),
    );
  }
}

class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({required this.controller});

  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label, detail) = switch (controller.syncStatus) {
      SyncStatus.disabled => (
        Icons.cloud_off_rounded,
        scheme.onSurfaceVariant,
        'Sync is off',
        'Account sync is not configured in this build.',
      ),
      SyncStatus.signedOut => (
        Icons.cloud_off_rounded,
        scheme.onSurfaceVariant,
        'Not signed in',
        'Sign in to sync your encrypted vault.',
      ),
      SyncStatus.syncing => (
        Icons.cloud_sync_rounded,
        kAccent,
        'Syncing…',
        'Comparing this device with your account.',
      ),
      SyncStatus.conflict => (
        Icons.sync_problem_rounded,
        kDanger,
        'Needs attention',
        'This device and your account have different changes.',
      ),
      SyncStatus.error => (
        Icons.cloud_off_rounded,
        kDanger,
        'Sync failed',
        controller.syncError ?? 'Check your connection and try again.',
      ),
      SyncStatus.idle => (
        Icons.cloud_done_rounded,
        kMint,
        'Up to date',
        controller.lastSyncedAt == null
            ? 'Your vault is ready to sync.'
            : 'Last synced ${formatDateTime(controller.lastSyncedAt!)}.',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.controller,
    required this.onKeepLocal,
    required this.onUseRemote,
  });

  final VaultController controller;
  final VoidCallback onKeepLocal;
  final VoidCallback onUseRemote;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final conflict = controller.syncConflict!;
    final updated = conflict.remoteUpdatedAt;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kDanger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kDanger.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: kDanger, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This vault changed on another device',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            updated == null
                ? 'Both this device and your account have changes. '
                      'Choose which version to keep.'
                : 'The account version was updated ${formatDateTime(updated)}. '
                      'Both it and this device have changes. '
                      'Choose which version to keep.',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          if (!conflict.sameVault) ...[
            const SizedBox(height: 8),
            Text(
              'The account version uses a different master password. '
              'You will need that password to unlock it.',
              style: TextStyle(color: kDanger, fontSize: 12, height: 1.4),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: controller.isSyncing ? null : onKeepLocal,
            icon: const Icon(Icons.phone_android_rounded, size: 18),
            label: const Text('Keep this device\'s vault'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: controller.isSyncing ? null : onUseRemote,
            icon: const Icon(Icons.cloud_download_outlined, size: 18),
            label: const Text('Use account version'),
          ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_rounded, size: 18, color: kMint),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Zero-knowledge sync: your account only stores the vault after it '
              'has been encrypted with your master password. The master '
              'password is never sent to the server, so nobody at SecureID or '
              'the hosting provider can read your items.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : kMint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.mark_email_read_outlined,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotConfiguredCard extends StatelessWidget {
  const _NotConfiguredCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 30, color: kMuted),
          const SizedBox(height: 14),
          Text(
            'Account sync is not configured',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'This build runs entirely offline. To enable accounts and '
            'multi-device sync, build SecureID with a Supabase project URL '
            'and its public anon/publishable key.',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: const SelectableText(
              'flutter build windows --release '
              '--dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co '
              '--dart-define=SUPABASE_ANON_KEY=YOUR-PUBLIC-KEY',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'See supabase/README.md for the database schema and setup steps.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
