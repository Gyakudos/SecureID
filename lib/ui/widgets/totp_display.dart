import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/totp.dart';
import '../../security/totp.dart';
import '../theme.dart';

/// A live TOTP code with a countdown ring. Rebuilds once a second.
class TotpCodeView extends StatefulWidget {
  const TotpCodeView({
    super.key,
    required this.data,
    this.compact = false,
    this.onCopy,
  });

  final TotpData data;
  final bool compact;
  final VoidCallback? onCopy;

  @override
  State<TotpCodeView> createState() => _TotpCodeViewState();
}

class _TotpCodeViewState extends State<TotpCodeView> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    TotpCode? code;
    String? error;
    try {
      code = generateTotp(widget.data);
    } on TotpException catch (exception) {
      error = exception.message;
    } catch (_) {
      error = 'Invalid secret';
    }

    if (code == null) {
      return Text(
        error ?? 'Invalid secret',
        style: TextStyle(color: scheme.error, fontSize: 12),
      );
    }

    final expiring = code.fraction < 0.2;
    final codeColor = expiring ? kDanger : scheme.onSurface;
    final ringColor = expiring ? kDanger : kMint;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          code.code,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: widget.compact ? 17 : 21,
            fontWeight: FontWeight.w700,
            letterSpacing: widget.compact ? 2.5 : 3.5,
            color: codeColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: widget.compact ? 26 : 30,
          height: widget.compact ? 26 : 30,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: widget.compact ? 26 : 30,
                height: widget.compact ? 26 : 30,
                child: CircularProgressIndicator(
                  value: code.fraction,
                  strokeWidth: 3,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                ),
              ),
              Text(
                '${code.secondsRemaining}',
                style: TextStyle(
                  fontSize: widget.compact ? 9 : 10,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (widget.onCopy != null) ...[
          const SizedBox(width: 2),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Copy code',
            onPressed: widget.onCopy,
            icon: Icon(
              Icons.copy_rounded,
              size: widget.compact ? 16 : 18,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
