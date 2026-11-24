import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/native_bridge.dart';
import '../domain/schedule_config.dart';
import 'ui.dart';

class _Phase {
  const _Phase(this.label, this.subtitle, this.icon, this.color, this.progress);
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final double progress;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _bridge = NativeBridge();
  SharedPreferences? _prefs;
  Timer? _ticker;
  Timer? _restoreTimer;
  DateTime _now = DateTime.now();

  TimeOfDay _sunrise = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _sunset = const TimeOfDay(hour: 19, minute: 0);
  TimeOfDay _night = const TimeOfDay(hour: 22, minute: 0);
  double _brightness = 50;

  /// 0 = actif · -1 = pause manuelle · >0 = pause jusqu'à ce timestamp (ms)
  int _pauseUntil = 0;

  bool _write = false;
  bool _exact = false;
  bool _notif = false;
  bool _batteryOk = true;

  bool get _paused =>
      _pauseUntil == -1 || _pauseUntil > _now.millisecondsSinceEpoch;

  int _min(TimeOfDay t) => t.hour * 60 + t.minute;

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
    _restoreTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final write = await _bridge.canWriteSettings();
    final exact = await _bridge.canScheduleExact();
    final notif = await Permission.notification.isGranted;
    final batteryOk = await _bridge.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _prefs = p;
      _now = DateTime.now();
      _sunrise = TimeOfDay(
        hour: p.getInt('sunrise_hour') ?? 7,
        minute: p.getInt('sunrise_minute') ?? 0,
      );
      _sunset = TimeOfDay(
        hour: p.getInt('sunset_hour') ?? 19,
        minute: p.getInt('sunset_minute') ?? 0,
      );
      _night = TimeOfDay(
        hour: p.getInt('night_hour') ?? 22,
        minute: p.getInt('night_minute') ?? 0,
      );
      _brightness = (p.getInt('night_brightness') ?? 50).toDouble();
      _pauseUntil = p.getInt('pause_until') ?? 0;
      _write = write;
      _exact = exact;
      _notif = notif;
      _batteryOk = batteryOk;
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

    await _bridge.saveSchedule(
      ScheduleConfig(
        sunriseHour: _sunrise.hour,
        sunriseMinute: _sunrise.minute,
        sunsetHour: _sunset.hour,
        sunsetMinute: _sunset.minute,
        nightHour: _night.hour,
        nightMinute: _night.minute,
        nightBrightness: _brightness.toInt(),
      ),
    );
  }

  Future<void> _setPause(int value) async {
    setState(() => _pauseUntil = value);
    HapticFeedback.mediumImpact();
    await _bridge.setPaused(value);
    final hasOriginal =
        value == 0 || (await _bridge.getWallpapers())['original'] != null;
    if (!mounted) return;
    showToast(
      context,
      value == 0
          ? 'Automatisation reprise · fond d\'écran réappliqué'
          : hasOriginal
              ? 'En pause · votre fond habituel est remis'
              : 'En pause · fond par défaut remis. Choisissez « Mon fond habituel » dans l\'onglet Fonds',
    );
  }

  Future<void> _applyNight(TimeOfDay t) async {
    if (!(_min(_sunset) < _min(t))) {
      showToast(context, 'La nuit doit commencer après le coucher du soleil');
      return;
    }
    setState(() => _night = t);
    HapticFeedback.selectionClick();
    await _persist();
  }

  DateTime _nextOccurrence(TimeOfDay t) {
    final n = DateTime.now();
    var d = DateTime(n.year, n.month, n.day, t.hour, t.minute);
    if (!d.isAfter(n)) d = d.add(const Duration(days: 1));
    return d;
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
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppC.indigo,
            surface: AppC.card,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;

    final sr = which == 'sunrise' ? picked : _sunrise;
    final ss = which == 'sunset' ? picked : _sunset;
    final nt = which == 'night' ? picked : _night;
    if (!(_min(sr) < _min(ss) && _min(ss) < _min(nt))) {
      showToast(context, 'Ordre attendu : lever → coucher → nuit');
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
      backgroundColor: AppC.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
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
                    color: AppC.stroke,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Mettre en pause', style: tx(20, w: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Le fond d\'écran et la luminosité ne changeront plus pendant ce temps.',
                style: tx(13, c: AppC.muted),
              ),
              const SizedBox(height: 12),
              _SheetOption(
                icon: Icons.timer_outlined,
                label: '1 heure',
                onTap: () => Navigator.pop(ctx, 1),
              ),
              _SheetOption(
                icon: Icons.wb_twilight_rounded,
                label: 'Jusqu\'à demain matin',
                onTap: () => Navigator.pop(ctx, 2),
              ),
              _SheetOption(
                icon: Icons.all_inclusive_rounded,
                label: 'Jusqu\'à ce que je reprenne',
                onTap: () => Navigator.pop(ctx, 3),
              ),
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

  Future<void> _previewPhase(String phase, String label) async {
    HapticFeedback.selectionClick();
    await _bridge.applyPhaseNow(phase);
    if (mounted) showToast(context, 'Phase « $label » appliquée');
  }

  // ───────────── Calculs ─────────────
  _Phase get _phase {
    final n = _now.hour * 60 + _now.minute;
    final sr = _min(_sunrise);
    final ss = _min(_sunset);
    final nt = _min(_night);

    if (n >= nt || n < sr) {
      final nightSpan = ((1440 - nt) + sr).clamp(1, 1440);
      final elapsed = n >= nt ? (n - nt) : ((1440 - nt) + n);
      return _Phase(
        'Nuit profonde',
        'Écran apaisé pour préparer le sommeil',
        Icons.bedtime_rounded,
        AppC.night,
        (elapsed / nightSpan).clamp(0.08, 1.0),
      );
    }
    if (n >= ss) {
      final span = (nt - ss).clamp(1, 1440);
      return _Phase(
        'Soirée douce',
        'Transition en douceur vers la nuit',
        Icons.wb_twilight_rounded,
        AppC.dusk,
        ((n - ss) / span).clamp(0.08, 1.0),
      );
    }
    final span = (ss - sr).clamp(1, 1440);
    return _Phase(
      'Journée lumineuse',
      'Écran à pleine énergie',
      Icons.wb_sunny_rounded,
      AppC.sun,
      ((n - sr) / span).clamp(0.08, 1.0),
    );
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
    if (_pauseUntil == -1) return 'Pause manuelle active';
    final d = DateTime.fromMillisecondsSinceEpoch(_pauseUntil);
    final tomorrow = d.day != _now.day;
    return 'Jusqu\'à ${tomorrow ? 'demain ' : ''}${hhmm(d.hour, d.minute)}';
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
    final missing =
        [!_write, !_exact, !_notif, !_batteryOk].where((e) => e).length;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildTopHeroHeader(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            children: [
              _buildSmartTipCard(),
              const SizedBox(height: 16),
              _buildQuickActions(),
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
      ],
    );
  }

 Widget _buildTopHeroHeader() {
    final phase = _phase;
    final accent = _paused ? AppC.muted : phase.color;
    final next = _next;
    final remaining = next.$2.difference(_now);
    final scoreValue =
        _paused ? 'PAUSE' : '${(phase.progress * 100).round()}%';

    final nowMin = _now.hour * 60 + _now.minute;
    final isNight = nowMin >= _min(_night) || nowMin < _min(_sunrise);
    final isEvening = nowMin >= _min(_sunset) || _now.hour >= 18;

    final topRightGreeting = isEvening
        ? 'Bonsoir'
        : (_now.hour < 12 ? 'Bonjour' : 'Bon après-midi');
    final topRightIcon = isNight
        ? Icons.bedtime_rounded
        : (isEvening ? Icons.wb_twilight_rounded : Icons.wb_sunny_rounded);
    final topRightColor = isNight
        ? AppC.night
        : (isEvening ? AppC.dusk : AppC.sun);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppC.bgTop, withA(AppC.bgTop, 0.35), AppC.bg],
          stops: const [0.0, 0.65, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Transform.translate(
                      offset: const Offset(-19, 0), // ← Change -4 en -8 ou -10 (plus le chiffre négatif est grand, plus il va à gauche)
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SvgPicture.asset(
                         'assets/icons/healthy_screen_logo.svg',
                          height: 28,
                          fit: BoxFit.contain,
                          alignment: Alignment.centerLeft,
                          colorFilter: const ColorFilter.mode(
                         AppC.indigo, // ← Remplace par la couleur souhaitée (ex: AppC.indigo, Color(0xFF7B5CFA), Colors.white...)
                          BlendMode.srcIn,
                          ),
                          placeholderBuilder: (_) => Text(
                            'Healthy Screen',
                            style: tx(24, w: FontWeight.w800, ls: -0.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppC.card,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: withA(const Color(0xFF2D3766), 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          topRightIcon,
                          size: 18,
                          color: topRightColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          topRightGreeting,
                          style: tx(15, w: FontWeight.w700, c: AppC.ink),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // Jauge circulaire centrale
              SizedBox(
                width: 158,
                height: 158,
                child: CustomPaint(
                  painter: _RhythmRingPainter(
                    progress: _paused ? 0.0 : phase.progress,
                    color: accent,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _paused ? 'Pause' : 'Rythme',
                          style: tx(12, w: FontWeight.w600, c: AppC.muted),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          scoreValue,
                          style: tx(
                            _paused ? 22 : 28,
                            w: FontWeight.w800,
                            ls: -0.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _paused
                              ? _pauseLabel
                              : 'dans ${_fmtDuration(remaining)}',
                          style: tx(11, w: FontWeight.w600, c: accent),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _paused
                    ? 'Votre fond habituel est restauré pendant la pause.'
                    : '${phase.subtitle} · ${next.$1} dans ${_fmtDuration(remaining)}',
                textAlign: TextAlign.center,
                style: tx(12, c: AppC.muted),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: _paused
                    ? FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppC.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        onPressed: () => _setPause(0),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Reprendre l\'automatisation'),
                      )
                    : FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppC.card,
                          foregroundColor: AppC.ink,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        onPressed: _showPauseSheet,
                        icon: const Icon(Icons.pause_rounded, color: AppC.indigo),
                        label: const Text('Mettre en pause'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Carte conseil en indigo/violet inspirée de "Personal tip" dans Envol
  Widget _buildSmartTipCard() {
    final bed = (_min(_sunrise) - 450 - 15) % 1440;
    final nightStart = (bed - 60) % 1440;
    final target = TimeOfDay(hour: nightStart ~/ 60, minute: nightStart % 60);
    final already = _min(_night) == nightStart;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6B5CE7), Color(0xFF5344C9)],
        ),
        boxShadow: [
          BoxShadow(
            color: withA(const Color(0xFF5344C9), 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: withA(Colors.white, 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bedtime_outlined,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Conseil sommeil',
                style: tx(13, w: FontWeight.w700, c: withA(Colors.white, 0.9)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Pour 5 cycles complets avant ${hhmm(_sunrise.hour, _sunrise.minute)}, '
            'couchez-vous vers ${hhmm(bed ~/ 60, bed % 60)}.',
            style: tx(14, w: FontWeight.w500, c: Colors.white, h: 1.4),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: already
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: withA(Colors.white, 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle,
                            color: Colors.white, size: 15),
                        const SizedBox(width: 6),
                        Text(
                          'Nuit réglée à ${hhmm(target.hour, target.minute)}',
                          style: tx(12, w: FontWeight.w600, c: Colors.white),
                        ),
                      ],
                    ),
                  )
                : TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: withA(Colors.white, 0.18),
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _applyNight(target),
                    child: Text(
                      'Passer nuit à ${hhmm(target.hour, target.minute)}',
                      style: tx(12, w: FontWeight.w700, c: Colors.white),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Raccourcis circulaires rapides inspirés des icônes circulaires d'Envol
  Widget _buildQuickActions() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tester une ambiance', style: tx(15, w: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Appliquez instantanément le fond d\'écran d\'une phase',
            style: tx(12, c: AppC.muted),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _CircleAction(
                icon: Icons.wb_sunny_rounded,
                label: 'Matin',
                color: AppC.sun,
                onTap: () => _previewPhase('sunrise', 'Lever du soleil'),
              ),
              _CircleAction(
                icon: Icons.wb_twilight_rounded,
                label: 'Soirée',
                color: AppC.dusk,
                onTap: () => _previewPhase('sunset', 'Coucher du soleil'),
              ),
              _CircleAction(
                icon: Icons.bedtime_rounded,
                label: 'Nuit',
                color: AppC.night,
                onTap: () => _previewPhase('night', 'Nuit profonde'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPermissions(int missing) {
    return AppCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          iconColor: AppC.muted,
          collapsedIconColor: AppC.muted,
          title: Text('Configuration requise ($missing)',
              style: tx(15, w: FontWeight.w700)),
          subtitle: Text(
            'Indispensable pour que tout fonctionne en arrière-plan',
            style: tx(12, c: AppC.muted),
          ),
          children: [
            if (!_write)
              _PermRow(
                title: 'Modifier la luminosité',
                onTap: () => _bridge.openWriteSettings(),
              ),
            if (!_exact)
              _PermRow(
                title: 'Alarmes exactes',
                onTap: () => _bridge.openExactAlarmSettings(),
              ),
            if (!_notif)
              _PermRow(
                title: 'Notifications',
                onTap: _askNotifications,
              ),
            if (!_batteryOk)
              _PermRow(
                title: 'Batterie sans restriction',
                onTap: () => _bridge.openBatteryOptimizationSettings(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    double f(TimeOfDay t) => _min(t) / 1440;
    final nowF = (_now.hour * 60 + _now.minute) / 1440;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Votre journée', style: tx(15, w: FontWeight.w700)),
          const SizedBox(height: 16),
          SizedBox(
            height: 36,
            width: double.infinity,
            child: CustomPaint(
              painter: _DayBarPainter(f(_sunrise), f(_sunset), f(_night), nowF),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['0h', '6h', '12h', '18h', '24h']
                .map((e) => Text(e, style: tx(11, c: AppC.muted)))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSlots() {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          _SlotTile(
            icon: Icons.wb_sunny_rounded,
            color: AppC.sun,
            title: 'Lever du soleil',
            subtitle: 'Fond lumineux, luminosité auto',
            time: hhmm(_sunrise.hour, _sunrise.minute),
            onTap: () => _pickTime('sunrise'),
          ),
          const Divider(height: 1, color: AppC.stroke, indent: 72),
          _SlotTile(
            icon: Icons.wb_twilight_rounded,
            color: AppC.dusk,
            title: 'Coucher du soleil',
            subtitle: 'Tons chauds, transition douce',
            time: hhmm(_sunset.hour, _sunset.minute),
            onTap: () => _pickTime('sunset'),
          ),
          const Divider(height: 1, color: AppC.stroke, indent: 72),
          _SlotTile(
            icon: Icons.bedtime_rounded,
            color: AppC.night,
            title: 'Nuit profonde',
            subtitle: 'Fond sombre, basse luminosité',
            time: hhmm(_night.hour, _night.minute),
            onTap: () => _pickTime('night'),
          ),
        ],
      ),
    );
  }

  Widget _buildBrightness() {
    final pct = (_brightness / 255 * 100).round();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Luminosité de nuit',
                    style: tx(15, w: FontWeight.w700)),
              ),
              Text('$pct %', style: tx(15, w: FontWeight.w800, c: AppC.indigo)),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              activeTrackColor: AppC.indigo,
              inactiveTrackColor: AppC.cardTint,
              thumbColor: AppC.indigo,
              overlayColor: withA(AppC.indigo, 0.15),
            ),
            child: Slider(
              value: _brightness,
              min: 10,
              max: 255,
              onChanged: (v) {
                setState(() => _brightness = v);
                _restoreTimer?.cancel();
                _bridge.previewBrightness(v.toInt());
              },
              onChangeEnd: (_) {
                HapticFeedback.selectionClick();
                _persist();
                if (_phase.label != 'Nuit profonde') {
                  _restoreTimer?.cancel();
                  _restoreTimer = Timer(
                    const Duration(milliseconds: 1500),
                    () => _bridge.restoreBrightness(),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Sous-widgets ─────────────────────────
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: withA(color, 0.14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(label, style: tx(12, w: FontWeight.w600, c: AppC.ink)),
            ],
          ),
        ),
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
                  color: withA(color, 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: tx(15, w: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: tx(12, c: AppC.muted)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppC.cardTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    Text(time, style: tx(14, w: FontWeight.w800, c: AppC.indigo)),
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
            const Icon(Icons.error_outline_rounded, size: 18, color: AppC.dusk),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: tx(14))),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppC.indigo),
              onPressed: onTap,
              child: const Text('Activer'),
            ),
          ],
        ),
      );
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppC.indigo),
        title: Text(label, style: tx(15, w: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppC.muted),
        onTap: onTap,
      );
}

class _RhythmRingPainter extends CustomPainter {
  _RhythmRingPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeW = 12.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - strokeW / 2;

    final bgPaint = Paint()
      ..color = AppC.cardTint
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    if (progress > 0) {
      final fgPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        fgPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RhythmRingPainter old) =>
      old.progress != progress || old.color != color;
}

class _DayBarPainter extends CustomPainter {
  _DayBarPainter(this.sr, this.ss, this.nt, this.now);
  final double sr, ss, nt, now;

  @override
  void paint(Canvas canvas, Size size) {
    const y = 18.0;
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, y - 8, size.width, 16),
      const Radius.circular(8),
    );
    final shader = LinearGradient(
      colors: const [
        Color(0xFF6B5CE7),
        Color(0xFFF59E0B),
        Color(0xFF38BDF8),
        Color(0xFFFB7185),
        Color(0xFF6B5CE7),
        Color(0xFF6B5CE7),
      ],
      stops: [0, sr, (sr + ss) / 2, ss, nt, 1],
    ).createShader(Rect.fromLTWH(0, 0, size.width, 1));
    canvas.drawRRect(bar, Paint()..shader = shader);

    final tick = Paint()..color = Colors.white;
    for (final f in [sr, ss, nt]) {
      canvas.drawCircle(Offset(f * size.width, y), 3.2, tick);
    }

    final x = (now * size.width).clamp(9.0, size.width - 9.0);
    canvas.drawCircle(Offset(x, y), 10, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(x, y), 5.5, Paint()..color = AppC.indigo);
  }

  @override
  bool shouldRepaint(covariant _DayBarPainter old) =>
      old.sr != sr || old.ss != ss || old.nt != nt || old.now != now;
}