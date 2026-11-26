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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppC.card,
          boxShadow: [
            BoxShadow(
              color: withA(const Color(0xFF2D3766), 0.06),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            height: 68,
            backgroundColor: AppC.card,
            indicatorColor: Colors.transparent,
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return tx(
                11,
                w: selected ? FontWeight.w700 : FontWeight.w500,
                c: selected ? AppC.indigo: AppC.muted,
              );
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return IconThemeData(
                size: 23,
                color: selected ? AppC.indigo : AppC.muted,
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: _i,
            onDestinationSelected: (i) => setState(() => _i = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Accueil',
              ),
              NavigationDestination(
                icon: Icon(Icons.pie_chart_outline_rounded),
                selectedIcon: Icon(Icons.pie_chart_rounded),
                label: 'Mon espace',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_mosaic_outlined),
                selectedIcon: Icon(Icons.auto_awesome_mosaic_rounded),
                label: 'Fonds',
              ),
            ],
          ),
        ),
      ),
    );
  }
}