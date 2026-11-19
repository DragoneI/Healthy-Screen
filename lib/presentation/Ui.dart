import 'package:flutter/material.dart';

class AppC {
  // Surfaces claires & douces (inspirées Envol & Digital Wellbeing)
  static const bg = Color(0xFFF6F7FC);
  static const bgTop = Color(0xFFEAF0FF);
  static const card = Color(0xFFFFFFFF);
  static const cardTint = Color(0xFFF0F3FA);
  static const stroke = Color(0xFFE5E9F2);

  // Accents
  static const indigo = Color(0xFF6366F1);
  static const indigoDark = Color(0xFF5A4FCF);
  static const sky = Color(0xFF2596F3);
  static const teal = Color(0xFF26A69A);
  static const sun = Color(0xFFF59E0B);
  static const dusk = Color(0xFFFB7185);
  static const night = Color(0xFF7C6CF0);

  // Textes
  static const ink = Color(0xFF1A1D2E);
  static const muted = Color(0xFF7A8299);
}

Color withA(Color c, double o) => c.withAlpha((o * 255).round());

TextStyle tx(
  double s, {
  FontWeight w = FontWeight.w500,
  Color c = AppC.ink,
  double? ls,
  double h = 1.25,
}) =>
    TextStyle(
      fontSize: s,
      fontWeight: w,
      color: c,
      letterSpacing: ls,
      height: h,
    );

String hhmm(int h, int m) =>
    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

String fmtMinutes(int m) =>
    m < 60 ? '$m min' : '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = AppC.card,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: withA(const Color(0xFF2D3766), 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(24),
          child: Padding(padding: padding, child: child),
        ),
      );
}

void showToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg, style: tx(14, c: Colors.white)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppC.ink,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
}