import 'package:flutter/material.dart';

import '../theme.dart';

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
  String? requiredText,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final canConfirm =
            requiredText == null || controller.text.trim() == requiredText;
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (requiredText != null) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Type $requiredText to confirm',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: kDanger,
                      foregroundColor: Colors.white,
                    )
                  : null,
              onPressed: canConfirm ? () => Navigator.pop(context, true) : null,
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();
  return result ?? false;
}
