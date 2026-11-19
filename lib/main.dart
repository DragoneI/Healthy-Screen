import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'presentation/app_shell.dart';
import 'presentation/ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppC.card,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const HealthyScreenApp());
}

class HealthyScreenApp extends StatelessWidget {
  const HealthyScreenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Healthy Screen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppC.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppC.indigo,
          brightness: Brightness.light,
          surface: AppC.card,
        ),
      ),
      home: const AppShell(),
    );
  }
}