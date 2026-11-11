import 'package:flutter/material.dart';
import 'presentation/home_page.dart';

void main() {
  runApp(const HealthyScreenApp());
}

class HealthyScreenApp extends StatelessWidget {
  const HealthyScreenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Healthy Screen',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}