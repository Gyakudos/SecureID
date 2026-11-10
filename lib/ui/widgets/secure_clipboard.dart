import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Copies a secret and clears it from the clipboard after a delay, but only if
/// the clipboard still contains the value we put there.
class SecureClipboard {
  const SecureClipboard._();

  static Future<void> copy(
    BuildContext context, {
    required String value,
    required String label,
    required int clearAfterSeconds,
  }) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            clearAfterSeconds > 0
                ? '$label copied · clears in ${clearAfterSeconds}s'
                : '$label copied',
          ),
          duration: const Duration(seconds: 2),
        ),
      );

    if (clearAfterSeconds <= 0) return;
    Timer(Duration(seconds: clearAfterSeconds), () async {
      try {
        final current = await Clipboard.getData(Clipboard.kTextPlain);
        if (current?.text == value) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      } catch (_) {
        // Some platforms block clipboard reads in the background. Leaving the
        // value is safer than clearing an unrelated clipboard entry.
      }
    });
  }
}
