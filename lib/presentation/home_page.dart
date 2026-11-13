import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/native_bridge.dart';
import '../domain/schedule_config.dart';

// ───────────────────────── Design tokens ─────────────────────────
class _C {
  static const bg = Color(0xFF0B1020);
  static const card = Color(0xFF151B2E);
  static const stroke = Color(0xFF232B45);
  static const accent = Color(0xFF2DD4BF);
  static const sun = Color(0xFFFBBF24);
  static const dusk = Color(0xFFFB923C);
  static const night = Color(0xFF818CF8);
  static const muted = Color(0xFF8B93AD);
}

Color _a(Color c, double o) => c.withAlpha((o * 255).round());

TextStyle _t(double s,
        {FontWeight w = FontWeight.w500, Color c = Colors.white, double? ls}) =>
    TextStyle(fontSize: s, fontWeight: w, color: c, letterSpacing: ls, height: 1.25);

int _min(TimeOfDay t) => t.hour * 60 + t.minute;

String _hhmm(int h, int m) =>
    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

class _Phase {
  const _Phase(this.label, this.subtitle, this.icon, this.color);
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
}

// ───────────────────────── Page ─────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _bridge = NativeBridge();
  SharedPreferences? _prefs;
  Timer? _ticker;
  DateTime _now = DateTime.now();

  TimeOfDay _sunrise = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _sunset = const TimeOfDay(hour: 19, minute: 0);
  TimeOfDay _night = const TimeOfDay(hour: 22, minute: 0);
  double _brightness = 50;

  /// 0 = actif · -1 = en pause jusqu'à reprise manuelle · >0 = pause jusqu'à ce timestamp (ms)
  int _pauseUntil = 0;

  bool _write = false;
  bool _exact = false;
  bool _notif = false;

  bool get _paused =>
      _pauseUntil == -1 || _pauseUntil > _now.millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  // Au retour des réglages Android ou d'une action de notification, on relit tout.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  // ───────────── Données ─────────────
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final write = await _bridge.canWriteSettings();
    final exact = await _bridge.canScheduleExact();
    final notif = await Permission.notification.isGranted;
    if (!mounted) return;
    setState(() {
      _prefs = p;
      _now = DateTime.now();
      _sunrise = TimeOfDay(
          hour: p.getInt('sunrise_hour') ?? 7, minute: p.getInt('sunrise_minute') ?? 0);
      _sunset = TimeOfDay(
          hour: p.getInt('sunset_hour') ?? 19, minute: p.getInt('sunset_minute') ?? 0);
      _night = TimeOfDay(
          hour: p.getInt('night_hour') ?? 22, minute: p.getInt('night_minute') ?? 0);
      _brightness = (p.getInt('night_brightness') ?? 50).toDouble();
      _pauseUntil = p.getInt('pause_until') ?? 0;
      _write = write;
      _exact = exact;
      _notif = notif;
    });
  }

  Future<void> _persist() async {
    final p = _prefs;
    if (p == null) return;
    await p.setInt('sunrise_hour', _sunrise.hour);
    await p.setInt('sunrise_minute', _sunrise.minute);
    await p.setInt('sunset_hour', _sunset.hour);
    await p.setInt('sunset_minute', _sunset.minute);
    await p.setInt('night_hour', _night.hour);
    await p.setInt('night_minute', _night.minute);
    await p.setInt('night_brightness', _brightness.toInt());

    // Les alarmes restent toujours armées : la pause est gérée côté Kotlin.
    await _bridge.saveSchedule(ScheduleConfig(
      sunriseHour: _sunrise.hour,
      sunriseMinute: _sunrise.minute,
      sunsetHour: _sunset.hour,
      sunsetMinute: _sunset.minute,
      nightHour: _night.hour,
      nightMinute: _night.minute,
      nightBrightness: _brightness.toInt(),
    ));
  }

  Future<void> _setPause(int value) async {
    setState(() => _pauseUntil = value);
    await _prefs?.setInt('pause_until', value);
    HapticFeedback.mediumImpact();
    if (value == 0) await _persist(); // ré-arme tout à la reprise
    _toast(value == 0 ? 'Automatisation reprise' : 'Automatisation en pause');
  }

  DateTime _nextOccurrence(TimeOfDay t) {
    final n = DateTime.now();
    var d = DateTime(n.year, n.month, n.day, t.hour, t.minute);
    if (!d.isAfter(n)) d = d.add(const Duration(days: 1));
    return d;
  }

  // ───────────── Interactions ─────────────
  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: _t(14)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _C.card,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ));
  }

  Future<void> _pickTime(String which) async {
    final current = switch (which) {
      'sunrise' => _sunrise,
      'sunset' => _sunset,
      _ => _night,
    };
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: _C.accent, surface: _C.card),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    final sr = which == 'sunrise' ? picked : _sunrise;
    final ss = which == 'sunset' ? picked : _sunset;
    final nt = which == 'night' ? picked : _night;
    if (!(_min(sr) < _min(ss) && _min(ss) < _min(nt))) {
      _toast('Ordre attendu : lever → coucher → nuit');
      return;
    }
    setState(() {
      _sunrise = sr;
      _sunset = ss;
      _night = nt;
    });
    HapticFeedback.selectionClick();
    await _persist();
  }

  Future<void> _showPauseSheet() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: _C.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: _C.stroke, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Mettre en pause', style: _t(20, w: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Le fond d\'écran et la luminosité ne changeront plus pendant ce temps.',
                style: _t(13, c: _C.muted),
              ),
              const SizedBox(height: 12),
              _SheetOption(
                  icon: Icons.timer_outlined,
                  label: '1 heure',
                  onTap: () => Navigator.pop(ctx, 1)),
              _SheetOption(
                  icon: Icons.wb_twilight_rounded,
                  label: 'Jusqu\'à demain matin',
                  onTap: () => Navigator.pop(ctx, 2)),
              _SheetOption(
                  icon: Icons.all_inclusive_rounded,
                  label: 'Jusqu\'à ce que je reprenne',
                  onTap: () => Navigator.pop(ctx, 3)),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    final until = switch (choice) {
      1 => DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
      2 => _nextOccurrence(_sunrise).millisecondsSinceEpoch,
      _ => -1,
    };
    await _setPause(until);
  }

  Future<void> _askNotifications() async {
    final status = await Permission.notification.request();
    if (status.isPermanentlyDenied) await openAppSettings();
    _load();
  }

  // ───────────── Calculs d'affichage ─────────────
  _Phase get _phase {
    final n = _now.hour * 60 + _now.minute;
    if (n >= _min(_night) || n < _min(_sunrise)) {
      return const _Phase('Nuit profonde', 'Écran apaisé pour préparer le sommeil',
          Icons.bedtime_rounded, _C.night);
    }
    if (n >= _min(_sunset)) {
      return const _Phase('Soirée douce', 'Transition en douceur vers la nuit',
          Icons.wb_twilight_rounded, _C.dusk);
    }
    return const _Phase('Journée lumineuse', 'Écran à pleine énergie',
        Icons.wb_sunny_rounded, _C.sun);
  }

  (String, DateTime) get _next {
    final list = <(String, DateTime)>[
      ('Lever du soleil', _nextOccurrence(_sunrise)),
      ('Coucher du soleil', _nextOccurrence(_sunset)),
      ('Nuit profonde', _nextOccurrence(_night)),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return list.first;
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }

  String get _pauseLabel {
    if (_pauseUntil == -1) return 'En pause jusqu\'à ce que vous repreniez';
    final d = DateTime.fromMillisecondsSinceEpoch(_pauseUntil);
    final tomorrow = d.day != _now.day;
    return 'En pause jusqu\'à ${tomorrow ? 'demain ' : ''}${_hhmm(d.hour, d.minute)}';
  }

  String get _greeting {
    final h = _now.hour;
    if (h < 12) return 'Bonjour';
    if (h < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  // ───────────── UI ─────────────
  @override
  Widget build(BuildContext context) {
    final missing = [!_write, !_exact, !_notif].where((e) => e).length;
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(_greeting, style: _t(14, c: _C.muted)),
            const SizedBox(height: 2),
            Text('Healthy Screen', style: _t(28, w: FontWeight.w800, ls: -0.5)),
            const SizedBox(height: 20),
            _buildHero(),
            const SizedBox(height: 16),
            if (missing > 0) ...[
              _buildPermissions(missing),
              const SizedBox(height: 16),
            ],
            _buildTimeline(),
            const SizedBox(height: 16),
            _buildSlots(),
            const SizedBox(height: 16),
            _buildBrightness(),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    final phase = _phase;
    final color = _paused ? Colors.grey : phase.color;
    final next = _next;
    final remaining = next.$2.difference(_now);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_a(color, 0.28), _a(color, 0.06)],
        ),
        border: Border.all(color: _a(color, 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: _a(color, 0.2)),
                child: Icon(_paused ? Icons.pause_rounded : phase.icon,
                    color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_paused ? 'Automatisation en pause' : phase.label,
                        style: _t(18, w: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(_paused ? _pauseLabel : phase.subtitle,
                        style: _t(13, c: _C.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 16, color: _C.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${next.$1} dans ${_fmtDuration(remaining)}',
                  style: _t(13, c: _C.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: _paused
                ? FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _C.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => _setPause(0),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Reprendre maintenant'),
                  )
                : OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: _a(Colors.white, 0.25)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _showPauseSheet,
                    icon: const Icon(Icons.pause_rounded),
                    label: const Text('Mettre en pause'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissions(int missing) {
    return _Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          iconColor: _C.muted,
          collapsedIconColor: _C.muted,
          title: Text('Configuration requise ($missing)',
              style: _t(15, w: FontWeight.w700)),
          subtitle: Text('Indispensable pour que tout fonctionne en arrière-plan',
              style: _t(12, c: _C.muted)),
          children: [
            if (!_write)
              _PermRow(
                  title: 'Modifier la luminosité',
                  onTap: () async {
                    await _bridge.openWriteSettings();
                  }),
            if (!_exact)
              _PermRow(
                  title: 'Alarmes exactes',
                  onTap: () async {
                    await _bridge.openExactAlarmSettings();
                  }),
            if (!_notif) _PermRow(title: 'Notifications', onTap: _askNotifications),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    double f(TimeOfDay t) => _min(t) / 1440;
    final nowF = (_now.hour * 60 + _now.minute) / 1440;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Votre journée', style: _t(15, w: FontWeight.w700)),
          const SizedBox(height: 16),
          SizedBox(
            height: 36,
            width: double.infinity,
            child: CustomPaint(
                painter: _DayBarPainter(f(_sunrise), f(_sunset), f(_night), nowF)),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['0h', '6h', '12h', '18h', '24h']
                .map((e) => Text(e, style: _t(11, c: _C.muted)))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSlots() {
    return _Card(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          _SlotTile(
              icon: Icons.wb_sunny_rounded,
              color: _C.sun,
              title: 'Lever du soleil',
              subtitle: 'Fond lumineux, luminosité auto',
              time: _hhmm(_sunrise.hour, _sunrise.minute),
              onTap: () => _pickTime('sunrise')),
          const Divider(height: 1, color: _C.stroke, indent: 72),
          _SlotTile(
              icon: Icons.wb_twilight_rounded,
              color: _C.dusk,
              title: 'Coucher du soleil',
              subtitle: 'Tons chauds, transition douce',
              time: _hhmm(_sunset.hour, _sunset.minute),
              onTap: () => _pickTime('sunset')),
          const Divider(height: 1, color: _C.stroke, indent: 72),
          _SlotTile(
              icon: Icons.bedtime_rounded,
              color: _C.night,
              title: 'Nuit profonde',
              subtitle: 'Fond sombre, basse luminosité',
              time: _hhmm(_night.hour, _night.minute),
              onTap: () => _pickTime('night')),
        ],
      ),
    );
  }

  Widget _buildBrightness() {
    final pct = (_brightness / 255 * 100).round();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text('Luminosité de nuit',
                      style: _t(15, w: FontWeight.w700))),
              Text('$pct %', style: _t(15, w: FontWeight.w800, c: _C.accent)),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              activeTrackColor: _C.accent,
              inactiveTrackColor: _C.stroke,
              thumbColor: _C.accent,
              overlayColor: _a(_C.accent, 0.15),
            ),
            child: Slider(
              value: _brightness,
              min: 10,
              max: 255,
              onChanged: (v) => setState(() => _brightness = v),
              onChangeEnd: (_) {
                HapticFeedback.selectionClick();
                _persist();
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Widgets ─────────────────────────
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: _C.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _C.stroke),
        ),
        child: child,
      );
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title, subtitle, time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: _a(color, 0.15), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _t(15, w: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: _t(12, c: _C.muted)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _C.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _C.stroke),
                ),
                child: Text(time, style: _t(15, w: FontWeight.w800, c: _C.accent)),
              ),
            ],
          ),
        ),
      );
}

class _PermRow extends StatelessWidget {
  const _PermRow({required this.title, required this.onTap});
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, size: 18, color: _C.dusk),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: _t(14))),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: _C.accent),
              onPressed: onTap,
              child: const Text('Activer'),
            ),
          ],
        ),
      );
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: _C.accent),
        title: Text(label, style: _t(15, w: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right_rounded, color: _C.muted),
        onTap: onTap,
      );
}

/// Frise 24 h : nuit → lever → jour → coucher → nuit, avec repère "maintenant".
class _DayBarPainter extends CustomPainter {
  _DayBarPainter(this.sr, this.ss, this.nt, this.now);
  final double sr, ss, nt, now;

  @override
  void paint(Canvas canvas, Size size) {
    const y = 18.0;
    final bar = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y - 8, size.width, 16), const Radius.circular(8));
    final shader = LinearGradient(
      colors: const [
        Color(0xFF1E1B4B),
        Color(0xFFF59E0B),
        Color(0xFF38BDF8),
        Color(0xFFFB923C),
        Color(0xFF1E1B4B),
        Color(0xFF1E1B4B),
      ],
      stops: [0, sr, (sr + ss) / 2, ss, nt, 1],
    ).createShader(Rect.fromLTWH(0, 0, size.width, 1));
    canvas.drawRRect(bar, Paint()..shader = shader);

    final tick = Paint()..color = const Color(0x66FFFFFF);
    for (final f in [sr, ss, nt]) {
      canvas.drawCircle(Offset(f * size.width, y), 3, tick);
    }

    final x = (now * size.width).clamp(9.0, size.width - 9.0);
    canvas.drawCircle(Offset(x, y), 10, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(x, y), 5, Paint()..color = _C.accent);
  }

  @override
  bool shouldRepaint(covariant _DayBarPainter old) =>
      old.sr != sr || old.ss != ss || old.nt != nt || old.now != now;
}