import 'package:flutter/material.dart';

/// A phone-style 0-9 keypad that reports a complete PIN.
///
/// The pad clears itself as soon as a complete PIN is entered, so a wrong PIN
/// can be retried immediately.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    this.length = 6,
    this.enabled = true,
    required this.onCompleted,
  });

  /// How many digits make a complete PIN.
  final int length;

  final bool enabled;

  /// Called with the completed PIN.
  final ValueChanged<String> onCompleted;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _digits = '';

  void _press(String digit) {
    if (!widget.enabled || _digits.length >= widget.length) return;
    final next = _digits + digit;
    setState(() => _digits = next);
    if (next.length == widget.length) {
      setState(() => _digits = '');
      widget.onCompleted(next);
    }
  }

  void _backspace() {
    if (!widget.enabled || _digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.length; i++)
                Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _digits.length
                        ? scheme.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: i < _digits.length
                          ? scheme.primary
                          : scheme.outline,
                      width: 1.6,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['', '0', '<'],
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final key in row)
                    SizedBox(
                      width: 78,
                      height: 62,
                      child: key.isEmpty
                          ? const SizedBox.shrink()
                          : _PadKey(
                              label: key == '<' ? null : key,
                              icon: key == '<'
                                  ? Icons.backspace_outlined
                                  : null,
                              enabled: widget.enabled,
                              onPressed: key == '<'
                                  ? _backspace
                                  : () => _press(key),
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

class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String? label;
  final IconData? icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: Center(
            child: icon != null
                ? Icon(icon, size: 22, color: scheme.onSurfaceVariant)
                : Text(
                    label ?? '',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: enabled ? scheme.onSurface : scheme.outline,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
