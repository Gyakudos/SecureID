import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/trusted_device.dart';
import '../../security/trusted_pairing.dart';
import '../../services/trusted_pairing_transport.dart';
import '../../state/vault_controller.dart';
import '../../state/vault_scope.dart';
import '../../util/date_format.dart';
import '../scanner/raw_qr_scanner_screen.dart';
import '../theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/gradient_background.dart';
import 'link_phone_screen.dart';

/// Pairs a phone and a PC once, then moves the encrypted vault with one tap.
///
/// The PC is the receiver and shows the QR code. The phone scans it and pushes
/// the already-encrypted vault. Both devices remember each other; later
/// transfers use the stored trust key and never ask for the master password on
/// the sending side. The receiving side still needs the vault's master password
/// to decrypt it.
class TrustedDeviceScreen extends StatefulWidget {
  const TrustedDeviceScreen({super.key, this.forceReceiver = false});

  /// Shows the receiving side even on a phone. Used by the setup and unlock
  /// screens, where the only sensible action is to receive a vault.
  final bool forceReceiver;

  @override
  State<TrustedDeviceScreen> createState() => _TrustedDeviceScreenState();
}

class _TrustedDeviceScreenState extends State<TrustedDeviceScreen> {
  final TrustedPairingReceiver _receiver = TrustedPairingReceiver();
  final TrustedPairingSender _sender = TrustedPairingSender();

  TrustPairingOffer? _offer;
  bool _startingReceiver = false;
  String? _receiveError;
  String? _receivedFrom;
  Timer? _countdown;
  Duration _remaining = Duration.zero;

  bool _pairing = false;
  String? _pairError;
  bool _sending = false;
  String? _sendingTo;
  String? _sendError;
  bool _discovering = false;
  List<DiscoveredTrustedDevice> _discovered = const [];
  bool _loaded = false;

  bool get _isPhone => !widget.forceReceiver && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = VaultScope.read(context);
      await controller.loadTrustedDevices();
      if (!mounted) return;
      setState(() => _loaded = true);
      if (!_isPhone) await _startReceiver();
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    unawaited(_receiver.stop());
    super.dispose();
  }

  Future<void> _startReceiver() async {
    final controller = VaultScope.read(context);
    final identity = await controller.ensureDeviceIdentity();
    if (!mounted) return;
    if (identity == null) {
      setState(() {
        _receiveError =
            'This build cannot create a device identity, so it cannot pair.';
      });
      return;
    }

    setState(() {
      _startingReceiver = true;
      _receiveError = null;
      _receivedFrom = null;
      _offer = null;
    });

    try {
      final offer = await _receiver.start(
        deviceId: identity.id,
        deviceName: identity.name,
        platform: identity.platform,
        findTrusted: controller.findTrustedDevice,
        remember: controller.rememberTrustedDevice,
        onConfirm: _confirmReceive,
        onEnvelope: _importReceived,
      );
      if (!mounted) {
        await _receiver.stop();
        return;
      }
      setState(() {
        _offer = offer;
        _startingReceiver = false;
        _remaining = offer.expiresAt.difference(DateTime.now());
      });
      _startCountdown();
    } on TrustedTransferException catch (exception) {
      if (!mounted) return;
      setState(() {
        _startingReceiver = false;
        _receiveError = exception.message;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _startingReceiver = false;
        _receiveError = 'Could not start receiving: $exception';
      });
    }
  }

  void _startCountdown() {
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      final offer = _offer;
      if (offer == null) return;
      final left = offer.expiresAt.difference(DateTime.now());
      if (!mounted) return;
      if (left.isNegative || left == Duration.zero) {
        _countdown?.cancel();
        _countdown = null;
        setState(() {
          _remaining = Duration.zero;
          _offer = null;
        });
        unawaited(_receiver.stop());
      } else {
        setState(() => _remaining = left);
      }
    });
  }

  Future<bool> _confirmReceive(TrustedDevice sender, bool pairing) async {
    if (!mounted) return false;
    final controller = VaultScope.read(context);
    final hasVault = controller.status != VaultStatus.needsSetup;
    final title = pairing
        ? 'Pair with ${sender.name}?'
        : 'Receive from ${sender.name}?';
    final base = pairing
        ? 'This remembers ${sender.name} as a trusted device. Only the '
              'already-encrypted vault is transferred; you still need its '
              'master password to open it.'
        : 'Accept the encrypted vault from ${sender.name}?';
    return confirmAction(
      context,
      title: title,
      message: hasVault
          ? '$base\n\nThis replaces the vault on this device. Export a backup '
                'first if you might need the current one.'
          : base,
      confirmLabel: pairing ? 'Pair and receive' : 'Receive vault',
      destructive: hasVault,
    );
  }

  Future<bool> _importReceived(String envelope, TrustedDevice sender) async {
    if (!mounted) return false;
    final controller = VaultScope.read(context);
    final imported = await controller.importEnvelope(envelope);
    if (!mounted) return imported;
    if (imported) {
      setState(() {
        _receivedFrom = sender.name;
        _receiveError = null;
      });
      // The trust record is saved just after this callback returns.
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 400),
          () => controller.loadTrustedDevices(force: true),
        ),
      );
    } else {
      setState(() {
        _receiveError =
            controller.error ?? 'Could not import the received vault.';
      });
    }
    return imported;
  }

  Future<void> _scanAndPair() async {
    final controller = VaultScope.read(context);
    if (controller.status == VaultStatus.needsSetup) {
      setState(() {
        _pairError = 'Create or receive a vault on this device before pairing.';
      });
      return;
    }

    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const RawQrScannerScreen(
          title: 'Scan the computer QR code',
          hint: 'Point the camera at the trusted-device code on the computer.',
        ),
      ),
    );
    if (!mounted || scanned == null) return;

    final link = TrustPairingLink.tryParse(scanned);
    if (link == null) {
      setState(() {
        _pairError =
            'That is not a SecureID trusted-device code. On the computer open '
            'Settings → Trusted devices and try again.';
      });
      return;
    }
    if (DateTime.now().isAfter(link.expiresAt)) {
      setState(() {
        _pairError =
            'That pairing code expired. Show a new code on the computer.';
      });
      return;
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pair with ${link.deviceName}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Check that this code matches the one on the computer screen.',
            ),
            const SizedBox(height: 16),
            Text(
              link.displayCode,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                letterSpacing: 8,
                fontWeight: FontWeight.w700,
                color: kMint,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pair and send'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    final identity = await controller.ensureDeviceIdentity();
    final envelope = await controller.readEncryptedEnvelope();
    if (!mounted) return;
    if (identity == null) {
      setState(() => _pairError = 'This build cannot identify this device.');
      return;
    }
    if (envelope == null || envelope.trim().isEmpty) {
      setState(() => _pairError = 'There is no vault on this device to send.');
      return;
    }

    setState(() {
      _pairing = true;
      _pairError = null;
    });
    try {
      final device = await _sender.pairAndPush(
        link: link,
        senderId: identity.id,
        senderName: identity.name,
        senderPlatform: identity.platform,
        envelope: envelope,
      );
      await controller.rememberTrustedDevice(device);
      if (!mounted) return;
      setState(() => _pairing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Paired with ${device.name}.')));
    } on TrustedTransferException catch (exception) {
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _pairError = exception.message;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _pairError = 'Could not pair: $exception';
      });
    }
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
    setState(() {
      _discovering = true;
      _sendError = null;
    });
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
          'device without a new pairing code.',
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

  @override
  Widget build(BuildContext context) {
    final controller = VaultScope.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Trusted devices')),
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
                      'Pair once, then transfer with one tap',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Both devices must be on the same Wi-Fi or local '
                      'network. Trust only authorises the transfer; the '
                      'master password is still required to decrypt the '
                      'vault.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    if (!controller.trustedDeviceAvailable)
                      _MessageCard(
                        icon: Icons.lock_outline_rounded,
                        color: kAccent,
                        message:
                            'Trusted devices are not available in this build.',
                      )
                    else if (_isPhone)
                      ..._buildPhone(context, controller)
                    else
                      ..._buildComputer(context, controller),
                    const SizedBox(height: 24),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                LinkPhoneScreen(initialTab: _isPhone ? 0 : 1),
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

  List<Widget> _buildComputer(
    BuildContext context,
    VaultController controller,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return [
      _SectionHeader(
        title: 'Receive a vault',
        subtitle:
            'Show this code to a phone, or wait for a paired phone to send.',
      ),
      const SizedBox(height: 10),
      if (_receivedFrom != null)
        _MessageCard(
          icon: Icons.check_circle_rounded,
          color: kMint,
          message:
              'Vault received from $_receivedFrom. Unlock it with that '
              'vault\'s master password.',
        )
      else if (_startingReceiver)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_offer != null)
        _PairingCard(
          offer: _offer!,
          remaining: _remaining,
          onNewCode: _startReceiver,
        )
      else
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_receiveError != null) ...[
              _MessageCard(
                icon: Icons.wifi_off_rounded,
                color: kDanger,
                message: _receiveError!,
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _startReceiver,
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('Show pairing code'),
            ),
          ],
        ),
      const SizedBox(height: 22),
      _SectionHeader(
        title: 'Paired phones',
        subtitle: 'Phones that can send their vault here with one tap.',
      ),
      const SizedBox(height: 8),
      if (_receiveError != null && _offer != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _MessageCard(
            icon: Icons.error_outline_rounded,
            color: kDanger,
            message: _receiveError!,
          ),
        ),
      _buildDeviceList(context, controller, receiverSide: true),
      const SizedBox(height: 18),
      _HintCard(
        icon: Icons.shield_outlined,
        title: 'What is stored',
        body:
            'Only the trust key is saved, protected by ${controller.trustedSealLabel}. '
            'Vault contents and the master password never leave the encrypted '
            'envelope. Forget a phone to revoke its access immediately.',
      ),
      if (scheme.brightness == Brightness.dark) const SizedBox.shrink(),
    ];
  }

  List<Widget> _buildPhone(BuildContext context, VaultController controller) {
    return [
      _SectionHeader(
        title: 'Paired computers',
        subtitle:
            'Open Receive on the computer, then tap Send here. The computer '
            'asks for confirmation unless you turn that off.',
      ),
      const SizedBox(height: 8),
      if (_sendError != null) ...[
        _MessageCard(
          icon: Icons.error_outline_rounded,
          color: kDanger,
          message: _sendError!,
        ),
        const SizedBox(height: 12),
      ],
      _buildDeviceList(context, controller, receiverSide: false),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _pairing ? null : _scanAndPair,
              icon: _pairing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_scanner_rounded),
              label: Text(_pairing ? 'Pairing…' : 'Scan a new computer'),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _discovering || _sending ? null : _discover,
            icon: _discovering
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
        ],
      ),
      if (_pairError != null) ...[
        const SizedBox(height: 12),
        _MessageCard(
          icon: Icons.error_outline_rounded,
          color: kDanger,
          message: _pairError!,
        ),
      ],
      if (_discovered.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(
          '${_discovered.length} paired computer'
          '${_discovered.length == 1 ? '' : 's'} online',
          style: TextStyle(
            color: kMint,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
      const SizedBox(height: 18),
      _HintCard(
        icon: Icons.shield_outlined,
        title: 'What is stored',
        body:
            'Only the trust key is saved, protected by ${controller.trustedSealLabel}. '
            'The master password is never sent, and the computer still needs '
            'it to unlock the received vault.',
      ),
    ];
  }

  Widget _buildDeviceList(
    BuildContext context,
    VaultController controller, {
    required bool receiverSide,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final devices = controller.trustedDevices;
    if (!_loaded || controller.trustedDevicesLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (controller.trustedDevicesError != null) {
      return _MessageCard(
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
          receiverSide
              ? 'No phones are paired yet. Show the code above, then scan it '
                    'from the phone.'
              : 'No computers are paired yet. Scan the computer\'s pairing '
                    'code to start.',
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
              canSend: !receiverSide && !_sending,
              showAutoAccept: receiverSide,
              onSend: () => _sendTo(device),
              onForget: () => _forget(device),
              onAutoAccept: (value) =>
                  controller.setTrustedDeviceAutoAccept(device.deviceId, value),
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
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
    required this.showAutoAccept,
    required this.onSend,
    required this.onForget,
    required this.onAutoAccept,
  });

  final TrustedDevice device;
  final bool online;
  final bool sending;
  final bool canSend;
  final bool showAutoAccept;
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
      if (device.autoAccept && showAutoAccept) 'Accepts automatically',
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
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
            if (showAutoAccept)
              Tooltip(
                message: 'Accept transfers without asking',
                child: Switch(
                  value: device.autoAccept,
                  onChanged: onAutoAccept,
                ),
              ),
            if (!showAutoAccept)
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
            IconButton(
              tooltip: 'Forget ${device.name}',
              onPressed: onForget,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _PairingCard extends StatelessWidget {
  const _PairingCard({
    required this.offer,
    required this.remaining,
    required this.onNewCode,
  });

  final TrustPairingOffer offer;
  final Duration remaining;
  final VoidCallback onNewCode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: QrImageView(
                  data: offer.link.encode(),
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Pairing code',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                offer.code,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  letterSpacing: 8,
                  fontWeight: FontWeight.w700,
                  color: kMint,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${offer.address} · expires in $minutes:$seconds',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _StatusPill(
                icon: Icons.wifi_tethering_rounded,
                color: kAccent,
                label: 'Waiting for a phone…',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onNewCode,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Show a new code'),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label, style: TextStyle(color: color, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: kMint, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12.5,
                    height: 1.45,
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

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
