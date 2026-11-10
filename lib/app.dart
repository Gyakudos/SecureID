import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state/vault_controller.dart';
import 'state/vault_scope.dart';
import 'ui/screens/setup_screen.dart';
import 'ui/screens/unlock_screen.dart';
import 'ui/screens/vault_home_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets/brand_mark.dart';
import 'ui/widgets/gradient_background.dart';

class SecureIdApp extends StatefulWidget {
  const SecureIdApp({super.key, required this.controller});

  final VaultController controller;

  @override
  State<SecureIdApp> createState() => _SecureIdAppState();
}

class _SecureIdAppState extends State<SecureIdApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Any keyboard activity counts as use of the app and postpones auto-lock.
  bool _handleKey(KeyEvent event) {
    widget.controller.touch();
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.controller.handleLifecycle(state);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return VaultScope(
      controller: controller,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final accessibility = controller.accessibility;
          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => controller.touch(),
            child: MaterialApp(
              title: 'SecureID',
              debugShowCheckedModeBanner: false,
              theme: buildSecureIdTheme(
                highContrast: accessibility.highContrast,
              ),
              builder: (context, child) {
                final media = MediaQuery.of(context);
                return MediaQuery(
                  data: media.copyWith(
                    textScaler: accessibility.textScale == 1.0
                        ? media.textScaler
                        : _MultipliedTextScaler(
                            media.textScaler,
                            accessibility.textScale,
                          ),
                  ),
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: const _RootGate(),
            ),
          );
        },
      ),
    );
  }
}

/// Multiplies the user's system text scale by the in-app accessibility scale.
class _MultipliedTextScaler implements TextScaler {
  const _MultipliedTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  double get textScaleFactor {
    // ignore: deprecated_member_use
    return base.textScaleFactor * factor;
  }

  @override
  TextScaler clamp({
    double minScaleFactor = 0,
    double maxScaleFactor = double.infinity,
  }) {
    return _MultipliedTextScaler(
      base.clamp(
        minScaleFactor: minScaleFactor / factor,
        maxScaleFactor: maxScaleFactor / factor,
      ),
      factor,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _MultipliedTextScaler &&
      other.base == base &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final controller = VaultScope.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: switch (controller.status) {
        VaultStatus.initializing => const _LoadingScreen(
          key: ValueKey('loading'),
        ),
        VaultStatus.needsSetup => const SetupScreen(key: ValueKey('setup')),
        VaultStatus.locked => const UnlockScreen(key: ValueKey('locked')),
        VaultStatus.unlocked => const VaultHomeScreen(key: ValueKey('vault')),
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: GradientBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandMark(size: 56),
              SizedBox(height: 20),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
