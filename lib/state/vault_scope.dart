import 'package:flutter/widgets.dart';

import 'vault_controller.dart';

class VaultScope extends InheritedNotifier<VaultController> {
  const VaultScope({
    super.key,
    required VaultController controller,
    required super.child,
  }) : super(notifier: controller);

  static VaultController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<VaultScope>();
    assert(scope != null, 'No VaultScope found in the widget tree.');
    return scope!.notifier!;
  }

  static VaultController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<VaultScope>();
    assert(scope != null, 'No VaultScope found in the widget tree.');
    return scope!.notifier!;
  }
}
