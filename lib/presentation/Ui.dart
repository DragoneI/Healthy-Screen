import 'package:flutter/material.dart';

class AppC {
  static const bg = Color(0xFF0B1020);
  static const card = Color(0xFF151B2E);
  static const stroke = Color(0xFF232B45);
  static const accent = Color(0xFF2DD4BF);
  static const sun = Color(0xFFFBBF24);
  static const dusk = Color(0xFFFB923C);
  static const night = Color(0xFF818CF8);
  static const muted = Color(0xFF8B93AD);
}

Color withA(Color c, double o) => c.withAlpha((o * 255).round());

TextStyle tx(double s,
        {FontWeight w = FontWeight.w500, Color c = Colors.white, double? ls}) =>
    TextStyle(fontSize: s, fontWeight: w, color: c, letterSpacing: ls, height: 1.25);

String hhmm(int h, int m) =>
    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

String fmtMinutes(int m) =>
    m < 60 ? '$m min' : '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: Material(
          color: AppC.card,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: AppC.stroke),
          ),
          child: Padding(padding: padding, child: child),
        ),
      );
}

void showToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg, style: tx(14)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppC.card,
      duration: const Duration(seconds: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
}