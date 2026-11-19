import 'package:flutter/material.dart';

import 'home_page.dart';
import 'space_page.dart';
import 'ui.dart';
import 'wallpapers_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _i = 0;

  Widget _page() => switch (_i) {
        0 => const HomePage(),
        1 => const SpacePage(),
        _ => const WallpapersPage(),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppC.bg,
      body: _page(),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppC.card,
          indicatorColor: withA(AppC.accent, 0.2),
          labelTextStyle: WidgetStatePropertyAll(tx(12, w: FontWeight.w600)),
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                color: states.contains(WidgetState.selected) ? AppC.accent : AppC.muted,
              )),
        ),
        child: NavigationBar(
          selectedIndex: _i,
          onDestinationSelected: (i) => setState(() => _i = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Accueil'),
            NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights_rounded),
                label: 'Mon espace'),
            NavigationDestination(
                icon: Icon(Icons.wallpaper_outlined),
                selectedIcon: Icon(Icons.wallpaper_rounded),
                label: 'Fonds'),
          ],
        ),
      ),
    );
  }
}