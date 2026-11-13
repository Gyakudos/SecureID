import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/trusted_device.dart';
import '../../services/trusted_pairing_transport.dart';
import '../../state/vault_controller.dart';
import '../../state/vault_scope.dart';
import '../../util/date_format.dart';
import '../theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/gradient_background.dart';
import '../widgets/trusted_pairing_widgets.dart';
import 'link_phone_screen.dart';
import 'pair_device_screen.dart';

/// Lists and manages every device that has been paired with this one.
///
/// Pairing lives on a separate screen so adding a new phone never removes the
/// devices that are already trusted. The same list can push this encrypted
/// vault to any paired device, on both computers and phones.
class TrustedDeviceScreen extends StatefulWidget {
  const TrustedDeviceScreen({super.key});

  @override
  State<TrustedDeviceScreen> createState() => _TrustedDeviceScreenState();
}

class _TrustedDeviceScreenState extends State<TrustedDeviceScreen> {
  final TrustedPairingSender _sender = TrustedPairingSender();

  bool _loaded = false;
  bool _discovering = false;
  bool _sending = false;
  String? _sendingTo;
  String? _sendError;
  List<DiscoveredTrustedDevice> _discovered = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = VaultScope.read(context);
      await controller.loadTrustedDevices();
      if (!mounted) return;
      setState(() => _loaded = true);
      unawaited(_discover());
    });
  }

  Future<void> _openPairing({bool receiveOnly = false}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PairDeviceScreen(receiveOnly: receiveOnly),
      ),
    );
    if (!mounted) return;
    await VaultScope.read(context).loadTrustedDevices(force: true);
    if (mounted) setState(() {});
  }

  Future<void> _sendTo(TrustedDevice device) async {
    final controller = VaultScope.read(context);
    final identity = await controller.ensureDeviceIdentity();
    final envelope = await controller.readEncryptedEnvelope();
    if (!mounted) return;
    if (identity == null) {
      setState(() => _sendError = 'This build cannot identify this device.');
      return;
    }
    if (envelope == null || envelope.trim().isEmpty) {
      setState(() => _sendError = 'There is no vault on this device to send.');
      return;
    }

    setState(() {
      _sending = true;
      _sendingTo = device.deviceId;
      _sendError = null;
    });

    DiscoveredTrustedDevice? online;
    for (final found in _discovered) {
      if (found.deviceId == device.deviceId) {
        online = found;
        break;
      }
    }

    try {
      TrustedDevice updated;
      try {
        updated = await _sender.sendToTrusted(
          device: device,
          senderId: identity.id,
          senderName: identity.name,
          senderPlatform: identity.platform,
          envelope: envelope,
          endpoint: online?.endpoint,
        );
      } on TrustedTransferException {
        if (online != null) rethrow;
        // The remembered address may be stale. Look for the receiver's
        // broadcast before giving up.
        final found = await _sender.discover(
          timeout: const Duration(seconds: 3),
          deviceIds: {device.deviceId},
        );
        if (found.isEmpty) rethrow;
        updated = await _sender.sendToTrusted(
          device: device,
          senderId: identity.id,
          senderName: identity.name,
          senderPlatform: identity.platform,
          envelope: envelope,
          endpoint: found.first.endpoint,
        );
      }

      await controller.rememberTrustedDevice(updated);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendingTo = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Vault sent to ${updated.name}.')));
    } on TrustedTransferException catch (exception) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendingTo = null;
        _sendError = exception.message;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendingTo = null;
        _sendError = 'Could not send: $exception';
      });
    }
  }

  Future<void> _discover() async {
    final controller = VaultScope.read(context);
    final ids = {
      for (final device in controller.trustedDevices) device.deviceId,
    };
    if (ids.isEmpty) return;
    if (mounted) {
      setState(() {
        _discovering = true;
        _sendError = null;
      });
    }
    final found = await _sender.discover(deviceIds: ids);
    if (!mounted) return;
    setState(() {
      _discovering = false;
      _discovered = found;
    });
  }

  Future<void> _forget(TrustedDevice device) async {
    final confirmed = await confirmAction(
      context,
      title: 'Forget ${device.name}?',
      message:
          'This device will no longer be able to send its vault to this '
          'device without a new pairing code. Other trusted devices are not '
          'affected.',
      confirmLabel: 'Forget device',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final controller = VaultScope.read(context);
    await controller.forgetTrustedDevice(device.deviceId);
    if (!mounted) return;
    setState(() {
      _discovered = [
        for (final found in _discovered)
          if (found.deviceId != device.deviceId) found,
      ];
    });
  }

  Future<void> _setAutoAccept(TrustedDevice device, bool value) async {
    final controller = VaultScope.read(context);
    await controller.setTrustedDeviceAutoAccept(device.deviceId, value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = VaultScope.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trusted Devices'),
        actions: [
          IconButton(
            tooltip: 'Refresh online devices',
            onPressed: _discovering ? null : _discover,
            icon: _discovering
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: GradientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Manage linked devices',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pair once, then send the encrypted vault to any linked '
                      'device with one tap. Both devices must be on the same '
                      'Wi-Fi or local network. Trust only authorises the '
                      'transfer; the master password is still required to '
                      'decrypt the vault.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 18),
                    if (!controller.trustedDeviceAvailable)
                      const TrustedMessageCard(
                        icon: Icons.lock_outline_rounded,
                        color: kAccent,
                        message:
                            'Trusted devices are not available in this build.',
                      )
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _openPairing(),
                              icon: const Icon(Icons.add_link_rounded),
                              label: const Text('Pair a new Device'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _openPairing(receiveOnly: true),
                              icon: const Icon(Icons.download_rounded),
                              label: const Text('Receive updates'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      TrustedSectionHeader(
                        title: 'Paired devices',
                        subtitle: _discovered.isEmpty
                            ? 'Send a vault, or open Receive updates on another '
                                  'device so it can send one here.'
                            : '${_discovered.length} device'
                                  '${_discovered.length == 1 ? '' : 's'} online '
                                  'now.',
                      ),
                      const SizedBox(height: 8),
                      if (_sendError != null) ...[
                        TrustedMessageCard(
                          icon: Icons.error_outline_rounded,
                          color: kDanger,
                          message: _sendError!,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _buildDeviceList(context, controller),
                      const SizedBox(height: 18),
                      TrustedHintCard(
                        icon: Icons.shield_outlined,
                        title: 'What is stored',
                        body:
                            'Only the trust key is saved, protected by '
                            '${controller.trustedSealLabel}. Vault contents and '
                            'the master password never leave the encrypted '
                            'envelope. Forget a device to revoke its access '
                            'immediately.',
                      ),
                    ],
                    const SizedBox(height: 24),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LinkPhoneScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.link_rounded),
                        label: const Text('Use a one-time link instead'),
                      ),
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

  Widget _buildDeviceList(BuildContext context, VaultController controller) {
    final scheme = Theme.of(context).colorScheme;
    final devices = controller.trustedDevices;
    if (!_loaded || controller.trustedDevicesLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (controller.trustedDevicesError != null) {
      return TrustedMessageCard(
        icon: Icons.error_outline_rounded,
        color: kDanger,
        message: controller.trustedDevicesError!,
      );
    }
    if (devices.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          'No devices are paired yet. Tap Pair a new Device to add one. '
          'Existing devices are never removed when you add another.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
      );
    }

    return Column(
      children: [
        for (final device in devices)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _DeviceTile(
              device: device,
              online: _discovered.any(
                (found) => found.deviceId == device.deviceId,
              ),
              sending: _sendingTo == device.deviceId,
              canSend: !_sending,
              onSend: () => _sendTo(device),
              onForget: () => _forget(device),
              onAutoAccept: (value) => _setAutoAccept(device, value),
            ),
          ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.online,
    required this.sending,
    required this.canSend,
    required this.onSend,
    required this.onForget,
    required this.onAutoAccept,
  });

  final TrustedDevice device;
  final bool online;
  final bool sending;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onForget;
  final ValueChanged<bool> onAutoAccept;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lastUsed = device.lastUsedAt;
    final subtitle = [
      if (lastUsed != null) 'Last used ${formatRelative(lastUsed)}',
      if (online) 'Online now',
      if (device.autoAccept) 'Accepts automatically',
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
        leading: Icon(
          device.platform == 'android'
              ? Icons.phone_android_rounded
              : Icons.desktop_windows_rounded,
          color: online ? kMint : kAccent,
        ),
        title: Text(device.name),
        subtitle: Text(
          subtitle.isEmpty
              ? device.platformLabel
              : '${device.platformLabel} · $subtitle',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Send vault to ${device.name}',
              onPressed: canSend ? onSend : null,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
            ),
            PopupMenuButton<_DeviceAction>(
              tooltip: 'Device options',
              onSelected: (action) {
                switch (action) {
                  case _DeviceAction.autoAccept:
                    onAutoAccept(!device.autoAccept);
                    break;
                  case _DeviceAction.forget:
                    onForget();
                    break;
                }
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  value: _DeviceAction.autoAccept,
                  checked: device.autoAccept,
                  child: const Text('Accept transfers automatically'),
                ),
                const PopupMenuItem(
                  value: _DeviceAction.forget,
                  child: Text('Forget device'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _DeviceAction { autoAccept, forget }
