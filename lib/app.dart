import 'package:flutter/material.dart';

import 'src/app_controller.dart';
import 'src/features/home/home_screen.dart';
import 'src/features/onboarding/onboarding_screen.dart';
import 'src/features/permissions/permission_service.dart';
import 'src/features/settings/settings_screen.dart';
import 'src/ui/logo.dart';
import 'src/update/update_controller.dart';
import 'src/update/update_widgets.dart';

class GateKeeperApp extends StatefulWidget {
  const GateKeeperApp({
    super.key,
    required this.controller,
    required this.updates,
    this.permissions = const PermissionService(),
  });

  final AppController controller;
  final UpdateController updates;
  final PermissionService permissions;

  @override
  State<GateKeeperApp> createState() => _GateKeeperAppState();
}

class _GateKeeperAppState extends State<GateKeeperApp> with WidgetsBindingObserver {
  static const _seed = GateKeeperMark.brandGreen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.load();
    widget.controller.platform.setUiVisible(true);
    widget.updates.init().then((_) => widget.updates.maybeAutoCheck());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = widget.controller;
    switch (state) {
      case AppLifecycleState.resumed:
        c.platform.setUiVisible(true);
        c.refresh();
        widget.updates.maybeAutoCheck();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        c.platform.setUiVisible(false);
      default:
        break;
    }
  }

  ThemeData _theme(Brightness b) => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: b),
        useMaterial3: true,
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GateKeeper',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          if (!c.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          if (!c.settings.onboardingComplete) {
            return OnboardingScreen(controller: c, permissions: widget.permissions);
          }
          return MainShell(controller: c, updates: widget.updates, permissions: widget.permissions);
        },
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.controller, required this.updates, required this.permissions});

  final AppController controller;
  final UpdateController updates;
  final PermissionService permissions;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    widget.updates.addListener(_onUpdates);
  }

  @override
  void dispose() {
    widget.updates.removeListener(_onUpdates);
    super.dispose();
  }

  void _onUpdates() {
    if (_prompting || widget.updates.promptVersion == null || !mounted) return;
    _prompting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) await showUpdatePrompt(context, widget.updates);
      _prompting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(controller: widget.controller, onOpenSettings: () => setState(() => _tab = 1)),
      SettingsScreen(controller: widget.controller, updates: widget.updates, permissions: widget.permissions),
    ];
    const titles = ['GateKeeper', 'Settings'];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (_tab == 0) ...[
              const GateKeeperMark(size: 26),
              const SizedBox(width: 10),
            ],
            Text(titles[_tab], style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'Status'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
