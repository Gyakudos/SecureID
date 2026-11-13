import 'package:flutter/material.dart';

import '../../models/device_login.dart';
import '../../models/vault_settings.dart';
import '../../state/vault_controller.dart';
import '../../state/vault_scope.dart';
import '../../util/date_format.dart';
import '../backup_actions.dart';
import '../theme.dart';
import '../widgets/accessibility_panel.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/gradient_background.dart';
import '../widgets/quick_unlock_setup.dart';
import '../widgets/secure_clipboard.dart';
import '../widgets/strength_meter.dart';
import '../widgets/update_dialog.dart';
import 'account_screen.dart';
import 'link_phone_screen.dart';
import 'pair_device_screen.dart';
import 'trusted_device_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<String>? _location;
  bool _pinBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _location ??= VaultScope.read(context).location;
  }

  Future<void> _update(
    VaultSettings Function(VaultSettings settings) mutate,
  ) async {
    final controller = VaultScope.read(context);
    final next = controller.settings.copy();
    mutate(next);
    await controller.updateSettings(next);
  }

  Future<void> _togglePin(bool value) async {
    final controller = VaultScope.read(context);
    setState(() => _pinBusy = true);
    if (value) {
      final enabled = await controller.enablePinUnlock();
      if (!enabled && mounted) {
        _snack(
          controller.error ?? 'Could not enable ${controller.pinFeatureName}.',
        );
      }
    } else {
      await controller.disablePinUnlock();
    }
    if (mounted) setState(() => _pinBusy = false);
  }

  Future<void> _changePassword() async {
    final controller = VaultScope.read(context);
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePasswordDialog(controller: controller),
    );
    if (changed == true && mounted) {
      _snack('Master password changed.');
    }
  }

  Future<void> _setDefaultLogin(DefaultLoginMethod method) async {
    final controller = VaultScope.read(context);
    if (method == DefaultLoginMethod.passwordStyle &&
        !controller.quickUnlockEnabled) {
      await _setupQuickUnlock(controller.passwordStyle);
      return;
    }
    final ok = await controller.setDefaultLogin(method);
    if (!ok && mounted) {
      _snack(controller.error ?? 'Could not change the default login.');
    }
  }

  Future<void> _setupQuickUnlock(PasswordStyle style) async {
    final controller = VaultScope.read(context);
    if (style == PasswordStyle.pin) {
      final pin = await showPinSetupDialog(context);
      if (pin == null || !mounted) return;
      final ok = await controller.enableQuickUnlock(style: style, pin: pin);
      if (!mounted) return;
      _snack(
        ok
            ? 'PIN set up. It is now the default login.'
            : controller.error ?? 'Could not set up the PIN.',
      );
      return;
    }
    final dots = await showPatternSetupDialog(context);
    if (dots == null || !mounted) return;
    final ok = await controller.enableQuickUnlock(style: style, pattern: dots);
    if (!mounted) return;
    _snack(
      ok
          ? 'Pattern set up. It is now the default login.'
          : controller.error ?? 'Could not set up the pattern.',
    );
  }

  Future<void> _changePasswordStyle(PasswordStyle style) async {
    final controller = VaultScope.read(context);
    if (style == controller.passwordStyle) return;
    // With an existing record, ask for the new secret first. Cancelling keeps
    // the old style and record intact.
    if (controller.quickUnlockEnabled) {
      await _setupQuickUnlock(style);
      return;
    }
    await controller.setPasswordStyle(style);
  }

  Future<void> _removeQuickUnlock() async {
    final controller = VaultScope.read(context);
    final confirmed = await confirmAction(
      context,
      title: 'Remove quick unlock?',
      message:
          'The lock screen will ask for your master password instead. Your '
          'vault contents are not changed.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await controller.disableQuickUnlock();
    if (mounted) _snack('Quick unlock removed.');
  }

  void _openAccount() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AccountScreen()));
  }

  String _syncSubtitle(VaultController controller) {
    return switch (controller.syncStatus) {
      SyncStatus.syncing => 'Syncing…',
      SyncStatus.conflict => 'Sync needs attention',
      SyncStatus.error => controller.syncError ?? 'Sync failed',
      SyncStatus.disabled => 'Account sync is not configured',
      SyncStatus.signedOut => 'Not signed in',
      SyncStatus.idle =>
        controller.lastSyncedAt == null
            ? 'Ready to sync'
            : 'Synced ${formatDateTime(controller.lastSyncedAt!)}',
    };
  }

  Future<void> _wipe() async {
    final controller = VaultScope.read(context);
    final confirmed = await confirmAction(
      context,
      title: 'Delete this vault?',
      message:
          'Every login, passkey and authenticator code on this device will be '
          'permanently deleted. Export a backup first if you want to keep them.',
      confirmLabel: 'Delete vault',
      destructive: true,
      requiredText: 'DELETE',
    );
    if (!confirmed) return;
    await controller.wipeVault();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
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
    final settings = controller.settings;

    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
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
                          'Settings',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        Text(
                          'v${controller.currentVersion}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Section(
                            title: 'Account & sync',
                            icon: Icons.cloud_outlined,
                            children: [
                              if (!controller.accountAvailable)
                                const ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.cloud_off_rounded),
                                  title: Text('Offline only'),
                                  subtitle: Text(
                                    'Account sync is not configured in this '
                                    'build. The vault stays on this device.',
                                  ),
                                )
                              else if (!controller.isSignedIn)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.cloud_off_rounded),
                                  title: const Text('Not signed in'),
                                  subtitle: const Text(
                                    'Sign in to sync your encrypted vault '
                                    'across devices',
                                  ),
                                  trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                  ),
                                  onTap: _openAccount,
                                )
                              else
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    controller.syncStatus ==
                                                SyncStatus.conflict ||
                                            controller.syncStatus ==
                                                SyncStatus.error
                                        ? Icons.sync_problem_rounded
                                        : Icons.cloud_done_rounded,
                                    color:
                                        controller.syncStatus ==
                                                SyncStatus.conflict ||
                                            controller.syncStatus ==
                                                SyncStatus.error
                                        ? kDanger
                                        : kMint,
                                  ),
                                  title: Text(
                                    controller.accountUser?.displayName ??
                                        'Signed in',
                                  ),
                                  subtitle: Text(
                                    _syncSubtitle(controller),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                  ),
                                  onTap: _openAccount,
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _Section(
                            title: 'Linked devices',
                            icon: Icons.phonelink_ring_rounded,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.shield_outlined),
                                title: const Text('Trusted Devices'),
                                subtitle: const Text(
                                  'See every paired device, send the encrypted '
                                  'vault, or revoke access.',
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const TrustedDeviceScreen(),
                                  ),
                                ),
                              ),
                              const Divider(height: 1),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.add_link_rounded),
                                title: const Text('Pair a new Device'),
                                subtitle: const Text(
                                  'Add a phone or computer without removing '
                                  'the devices already trusted.',
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const PairDeviceScreen(),
                                  ),
                                ),
                              ),
                              const Divider(height: 1),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.qr_code_2_rounded),
                                title: const Text('One-time link'),
                                subtitle: const Text(
                                  'Send or receive a vault with a single-use '
                                  'QR code instead.',
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const LinkPhoneScreen(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _Section(
                            title: 'Vision & reading',
                            icon: Icons.accessibility_new_rounded,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.text_fields_rounded),
                                title: const Text('Text size'),
                                subtitle: Text(
                                  controller.accessibility.textScaleLabel,
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () => showAccessibilitySheet(context),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                secondary: const Icon(
                                  Icons.record_voice_over_rounded,
                                ),
                                title: const Text('Read accounts aloud'),
                                subtitle: Text(
                                  controller.speechAvailable
                                      ? 'Speak account summaries and details'
                                      : 'Text-to-speech is not available on '
                                            'this device',
                                ),
                                value: controller.accessibility.readAloud,
                                onChanged: controller.speechAvailable
                                    ? (value) => controller.updateAccessibility(
                                        controller.accessibility.copyWith(
                                          readAloud: value,
                                        ),
                                      )
                                    : null,
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                secondary: const Icon(Icons.contrast_rounded),
                                title: const Text('High contrast'),
                                subtitle: const Text(
                                  'Black background with brighter text',
                                ),
                                value: controller.accessibility.highContrast,
                                onChanged: (value) =>
                                    controller.updateAccessibility(
                                      controller.accessibility.copyWith(
                                        highContrast: value,
                                      ),
                                    ),
                              ),
                              const Divider(height: 1),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.accessibility_new_rounded,
                                ),
                                title: const Text('Open vision settings'),
                                subtitle: const Text(
                                  'Text size, spoken accounts and contrast',
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () => showAccessibilitySheet(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _Section(
                            title: 'Security',
                            icon: Icons.shield_outlined,
                            children: [
                              _DropdownTile<int>(
                                icon: Icons.timer_outlined,
                                title: 'Auto-lock',
                                subtitle: 'Lock the vault after a period without activity',
                                value: settings.autoLockMinutes,
                                items: const {
                                  1: 'After 1 minute',
                                  5: 'After 5 minutes',
                                  15: 'After 15 minutes',
                                  30: 'After 30 minutes',
                                  60: 'After 1 hour',
                                  0: 'Never',
                                },
                                onChanged: (value) => _update((settings) {
                                  settings.autoLockMinutes = value;
                                  return settings;
                                }),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                secondary: const Icon(
                                  Icons.phone_iphone_rounded,
                                ),
                                title: const Text('Lock when backgrounded'),
                                subtitle: const Text(
                                  'Lock as soon as the app leaves the foreground',
                                ),
                                value: settings.lockOnBackground,
                                onChanged: (value) => _update((settings) {
                                  settings.lockOnBackground = value;
                                  return settings;
                                }),
                              ),
                              const Divider(height: 1),
                              _DropdownTile<int>(
                                icon: Icons.content_copy_rounded,
                                title: 'Clear clipboard',
                                subtitle:
                                    'Remove copied secrets from the clipboard',
                                value: settings.clipboardClearSeconds,
                                items: const {
                                  10: 'After 10 seconds',
                                  30: 'After 30 seconds',
                                  60: 'After 1 minute',
                                  120: 'After 2 minutes',
                                  0: 'Never',
                                },
                                onChanged: (value) => _update((settings) {
                                  settings.clipboardClearSeconds = value;
                                  return settings;
                                }),
                              ),
                            ],
                          ),
                          if (controller.pinPlatformSupported) ...[
                            const SizedBox(height: 14),
                            _Section(
                              title: controller.pinFeatureName,
                              icon: Icons.fingerprint_rounded,
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  secondary: const Icon(
                                    Icons.fingerprint_rounded,
                                  ),
                                  title: Text(controller.pinUnlockButtonLabel),
                                  subtitle: Text(
                                    controller.pinEnabled ||
                                            controller.pinAvailable
                                        ? controller.pinAvailableHint
                                        : controller.pinUnavailableHint,
                                  ),
                                  value: controller.pinEnabled,
                                  onChanged: _pinBusy ? null : _togglePin,
                                ),
                                if (_pinBusy)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: LinearProgressIndicator(
                                      minHeight: 2,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),
                          _Section(
                            title: 'Default Login',
                            icon: Icons.login_rounded,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  bottom: 6,
                                ),
                                child: Text(
                                  'Choose what the lock screen asks for first. '
                                  'Your master password always works.',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              _LoginMethodTile(
                                icon: Icons.password_rounded,
                                title: 'Password',
                                subtitle: 'Type your master password',
                                selected:
                                    controller.defaultLogin ==
                                    DefaultLoginMethod.password,
                                onTap: () => _setDefaultLogin(
                                  DefaultLoginMethod.password,
                                ),
                              ),
                              if (controller.pinPlatformSupported)
                                _LoginMethodTile(
                                  icon: Icons.fingerprint_rounded,
                                  title: controller.pinFeatureName,
                                  subtitle: controller.pinEnabled
                                      ? 'Use your enrolled biometric or PIN'
                                      : 'Enable ${controller.pinFeatureName} '
                                            'above first',
                                  selected:
                                      controller.defaultLogin ==
                                      DefaultLoginMethod.deviceUnlock,
                                  onTap: () => _setDefaultLogin(
                                    DefaultLoginMethod.deviceUnlock,
                                  ),
                                ),
                              if (controller.passwordStyleSupported) ...[
                                _LoginMethodTile(
                                  icon: Icons.dialpad_rounded,
                                  title: 'Password Style',
                                  subtitle: controller.quickUnlockEnabled
                                      ? (controller.passwordStyle ==
                                                PasswordStyle.pin
                                            ? 'Unlock with your six-digit PIN'
                                            : 'Unlock with your drawn pattern')
                                      : 'Set up a PIN or a drawn pattern',
                                  selected:
                                      controller.defaultLogin ==
                                      DefaultLoginMethod.passwordStyle,
                                  onTap: () => _setDefaultLogin(
                                    DefaultLoginMethod.passwordStyle,
                                  ),
                                ),
                                const Divider(height: 1),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'Password style',
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      SegmentedButton<PasswordStyle>(
                                        segments: const [
                                          ButtonSegment(
                                            value: PasswordStyle.pin,
                                            icon: Icon(
                                              Icons.dialpad_rounded,
                                              size: 18,
                                            ),
                                            label: Text('6-digit PIN'),
                                          ),
                                          ButtonSegment(
                                            value: PasswordStyle.pattern,
                                            icon: Icon(
                                              Icons.gesture_rounded,
                                              size: 18,
                                            ),
                                            label: Text('Pattern'),
                                          ),
                                        ],
                                        selected: {controller.passwordStyle},
                                        onSelectionChanged: (selection) =>
                                            _changePasswordStyle(
                                              selection.first,
                                            ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: FilledButton.tonalIcon(
                                              onPressed: () =>
                                                  _setupQuickUnlock(
                                                    controller.passwordStyle,
                                                  ),
                                              icon: Icon(
                                                controller.quickUnlockEnabled
                                                    ? Icons.autorenew_rounded
                                                    : Icons.add_rounded,
                                              ),
                                              label: Text(
                                                controller.quickUnlockEnabled
                                                    ? 'Change ${controller.passwordStyle == PasswordStyle.pin ? 'PIN' : 'pattern'}'
                                                    : 'Set up ${controller.passwordStyle == PasswordStyle.pin ? 'PIN' : 'pattern'}',
                                              ),
                                            ),
                                          ),
                                          if (controller
                                              .quickUnlockEnabled) ...[
                                            const SizedBox(width: 8),
                                            IconButton(
                                              tooltip: 'Remove quick unlock',
                                              onPressed: _removeQuickUnlock,
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (controller.quickUnlockEnabled) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          controller.quickUnlockLockedOut
                                              ? 'Too many attempts. Unlock '
                                                    'with your master password.'
                                              : '${controller.quickUnlockAttemptsRemaining} '
                                                    'attempt${controller.quickUnlockAttemptsRemaining == 1 ? '' : 's'} '
                                                    'left before the master '
                                                    'password is required.',
                                          style: TextStyle(
                                            color:
                                                controller.quickUnlockLockedOut
                                                ? scheme.error
                                                : scheme.onSurfaceVariant,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 14),
                          _Section(
                            title: 'Password generator defaults',
                            icon: Icons.auto_awesome_rounded,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.straighten_rounded,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 14),
                                    const Expanded(child: Text('Length')),
                                    Text(
                                      '${settings.generatorLength}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Slider(
                                value: settings.generatorLength
                                    .clamp(8, 64)
                                    .toDouble(),
                                min: 8,
                                max: 64,
                                divisions: 56,
                                label: '${settings.generatorLength}',
                                onChanged: (value) => setState(() {
                                  settings.generatorLength = value.round();
                                }),
                                onChangeEnd: (value) => _update((settings) {
                                  settings.generatorLength = value.round();
                                  return settings;
                                }),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _generatorChip(
                                    'A-Z',
                                    settings.generatorUpper,
                                    (value) => _update((settings) {
                                      settings.generatorUpper = value;
                                      return settings;
                                    }),
                                  ),
                                  _generatorChip(
                                    'a-z',
                                    settings.generatorLower,
                                    (value) => _update((settings) {
                                      settings.generatorLower = value;
                                      return settings;
                                    }),
                                  ),
                                  _generatorChip(
                                    '0-9',
                                    settings.generatorDigits,
                                    (value) => _update((settings) {
                                      settings.generatorDigits = value;
                                      return settings;
                                    }),
                                  ),
                                  _generatorChip(
                                    '!@#',
                                    settings.generatorSymbols,
                                    (value) => _update((settings) {
                                      settings.generatorSymbols = value;
                                      return settings;
                                    }),
                                  ),
                                  _generatorChip(
                                    'No 0/O/1/l',
                                    settings.generatorExcludeAmbiguous,
                                    (value) => _update((settings) {
                                      settings.generatorExcludeAmbiguous =
                                          value;
                                      return settings;
                                    }),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _Section(
                            title: 'Master password',
                            icon: Icons.key_rounded,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.password_rounded),
                                title: const Text('Change master password'),
                                subtitle: const Text(
                                  'Re-encrypts the vault with a new key',
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: _changePassword,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _Section(
                            title: 'Backup',
                            icon: Icons.cloud_upload_outlined,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.save_alt_rounded),
                                title: const Text('Export encrypted backup'),
                                subtitle: const Text(
                                  'Save a copy of the sealed vault file',
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () =>
                                    exportVaultBackup(context, controller),
                              ),
                              const Divider(height: 1),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.settings_backup_restore,
                                ),
                                title: const Text('Restore from backup'),
                                subtitle: const Text(
                                  'Replace this vault with a backup you exported',
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () async {
                                  final restored = await restoreVaultBackup(
                                    context,
                                    controller,
                                  );
                                  if (restored && context.mounted) {
                                    _snack('Backup restored.');
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _Section(
                            title: 'Vault',
                            icon: Icons.folder_outlined,
                            children: [
                              FutureBuilder<String>(
                                future: _location,
                                builder: (context, snapshot) {
                                  final path = snapshot.data ?? 'Loading…';
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.description_outlined,
                                    ),
                                    title: const Text('Vault file'),
                                    subtitle: SelectableText(
                                      path,
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Copy path',
                                      onPressed: snapshot.hasData
                                          ? () => SecureClipboard.copy(
                                              context,
                                              value: path,
                                              label: 'Vault path',
                                              clearAfterSeconds: 0,
                                            )
                                          : null,
                                      icon: const Icon(Icons.copy_rounded),
                                    ),
                                  );
                                },
                              ),
                              const Divider(height: 1),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.delete_forever_rounded,
                                  color: scheme.error,
                                ),
                                title: Text(
                                  'Delete vault',
                                  style: TextStyle(color: scheme.error),
                                ),
                                subtitle: const Text(
                                  'Erase every item on this device',
                                ),
                                onTap: _wipe,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _Section(
                            title: 'About SecureID',
                            icon: Icons.info_outline_rounded,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading:
                                    controller.updateStatus ==
                                        UpdateStatus.checking
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        controller.updateAvailable
                                            ? Icons.system_update_rounded
                                            : Icons.sync_rounded,
                                        color: controller.updateAvailable
                                            ? kMint
                                            : null,
                                      ),
                                title: const Text('Check for updates'),
                                subtitle: Text(_updateSubtitle(controller)),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap:
                                    controller.updateStatus ==
                                        UpdateStatus.checking
                                    ? null
                                    : () => showUpdateCheck(context),
                              ),
                              const Divider(height: 1),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.tag_rounded),
                                title: const Text('Version'),
                                subtitle: Text(controller.currentVersion),
                              ),
                              const Divider(height: 1),
                              const ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.lock_rounded),
                                title: Text('Argon2id + AES-256-GCM'),
                                subtitle: Text(
                                  '19 MiB memory, 2 iterations, per-vault salt. '
                                  'Secrets never leave the encrypted vault.',
                                ),
                              ),
                              const Divider(height: 1),
                              const ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.storage_rounded),
                                title: Text('Local-first'),
                                subtitle: Text(
                                  'The vault works fully offline. Optional '
                                  'account sync stores only the encrypted '
                                  'envelope.',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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

  String _updateSubtitle(VaultController controller) {
    switch (controller.updateStatus) {
      case UpdateStatus.checking:
        return 'Contacting GitHub…';
      case UpdateStatus.available:
        final version = controller.latestUpdate?.version;
        return version == null
            ? 'A newer release is available'
            : 'SecureID $version is available';
      case UpdateStatus.upToDate:
        return 'You are on the latest version';
      case UpdateStatus.error:
        return controller.updateError ?? 'The last check did not finish';
      case UpdateStatus.idle:
        return 'Search GitHub for a newer release';
    }
  }

  Widget _generatorChip(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
      checkmarkColor: kMint,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer.withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DropdownTile<T> extends StatelessWidget {
  const _DropdownTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final safeValue = items.containsKey(value) ? value : items.keys.first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 22, color: scheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: safeValue,
              borderRadius: BorderRadius.circular(14),
              dropdownColor: scheme.surfaceContainerHigh,
              style: TextStyle(color: scheme.onSurface, fontSize: 13),
              items: [
                for (final entry in items.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) {
                if (value != null) onChanged(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginMethodTile extends StatelessWidget {
  const _LoginMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        icon,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        color: selected ? scheme.primary : scheme.outline,
      ),
      onTap: onTap,
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.controller});

  final VaultController controller;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final next = _next.text;
    if (next.length < VaultController.minMasterPasswordLength) {
      setState(() {
        _error =
            'Use at least ${VaultController.minMasterPasswordLength} characters.';
      });
      return;
    }
    if (next != _confirm.text) {
      setState(() => _error = 'The two new passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final changed = await widget.controller.changeMasterPassword(
      currentPassword: _current.text,
      newPassword: next,
    );
    if (!mounted) return;
    if (!changed) {
      setState(() {
        _busy = false;
        _error = widget.controller.error ?? 'Could not change the password.';
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Change master password'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _current,
                autofocus: true,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Current master password',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show' : 'Hide',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _next,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'New master password',
                ),
              ),
              const SizedBox(height: 10),
              StrengthMeter(password: _next.text, showBits: false),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _busy ? null : _submit(),
                decoration: const InputDecoration(
                  labelText: 'Confirm new master password',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Change password'),
        ),
      ],
    );
  }
}
