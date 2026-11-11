import 'package:flutter/material.dart';

import 'pattern_pad.dart';
import 'pin_pad.dart';

/// Asks the user to choose and confirm a six-digit PIN.
///
/// Returns the PIN, or null if the user cancels.
Future<String?> showPinSetupDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _PinSetupDialog(),
  );
}

/// Asks the user to draw and confirm a 3x3 pattern.
///
/// Returns the ordered dot indexes, or null if the user cancels.
Future<List<int>?> showPatternSetupDialog(BuildContext context) {
  return showDialog<List<int>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _PatternSetupDialog(),
  );
}

class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog();

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  String? _first;
  String? _error;

  void _onPin(String pin) {
    if (_first == null) {
      setState(() {
        _first = pin;
        _error = null;
      });
      return;
    }
    if (pin == _first) {
      Navigator.of(context).pop(pin);
      return;
    }
    setState(() {
      _first = null;
      _error = 'Those PINs did not match. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final confirming = _first != null;
    return AlertDialog(
      title: Text(confirming ? 'Confirm your PIN' : 'Create a PIN'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              confirming
                  ? 'Enter the same six digits again.'
                  : 'Choose six digits. The phone pad is used so the PIN is '
                        'easy to enter on Android.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            PinPad(onCompleted: _onPin),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _PatternSetupDialog extends StatefulWidget {
  const _PatternSetupDialog();

  @override
  State<_PatternSetupDialog> createState() => _PatternSetupDialogState();
}

class _PatternSetupDialogState extends State<_PatternSetupDialog> {
  List<int>? _first;
  String? _error;

  void _onPattern(List<int> dots) {
    if (_first == null) {
      setState(() {
        _first = dots;
        _error = null;
      });
      return;
    }
    if (_sameDots(dots, _first!)) {
      Navigator.of(context).pop(dots);
      return;
    }
    setState(() {
      _first = null;
      _error = 'Those patterns did not match. Try again.';
    });
  }

  static bool _sameDots(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final confirming = _first != null;
    final width = MediaQuery.sizeOf(context).width;
    final size = width < 380 ? 240.0 : 280.0;
    return AlertDialog(
      title: Text(confirming ? 'Confirm your pattern' : 'Draw a pattern'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              confirming
                  ? 'Draw the same pattern again.'
                  : 'Connect at least four dots in one continuous stroke.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            PatternPad(size: size, onCompleted: _onPattern),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
