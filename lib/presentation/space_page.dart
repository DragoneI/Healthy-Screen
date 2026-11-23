import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/native_bridge.dart';
import 'ui.dart';

class _Tip {
  const _Tip(this.icon, this.title, this.text, this.phase);
  final IconData icon;
  final String title, text, phase;
}

const _tips = [
  _Tip(
    Icons.wb_sunny_rounded,
    'Lumière du matin',
    'Quelques minutes de lumière naturelle après le réveil aident à caler votre horloge interne.',
    'sunrise',
  ),
  _Tip(
    Icons.water_drop_rounded,
    'Hydratation',
    'Un verre d\'eau au réveil aide à relancer la concentration.',
    'sunrise',
  ),
  _Tip(
    Icons.visibility_rounded,
    'Règle 20-20-20',
    'Toutes les 20 min, regardez un point à 6 m pendant 20 s pour reposer vos yeux.',
    'day',
  ),
  _Tip(
    Icons.directions_walk_rounded,
    'Micro-pause active',
    'Levez-vous 2 minutes chaque heure : marche, étirements, respiration.',
    'day',
  ),
  _Tip(
    Icons.coffee_rounded,
    'Caféine',
    'Évitez la caféine au moins 6 h avant le coucher pour ne pas retarder l\'endormissement.',
    'sunset',
  ),
  _Tip(
    Icons.restaurant_rounded,
    'Dîner léger',
    'Un repas léger quelques heures avant de dormir favorise un meilleur sommeil.',
    'sunset',
  ),
  _Tip(
    Icons.bedtime_rounded,
    'Téléphone hors du lit',
    'Posez le téléphone hors de portée : un lit sans écran aide à mieux s\'endormir.',
    'night',
  ),
  _Tip(
    Icons.self_improvement_rounded,
    'Respiration 4-7-8',
    'Inspirez 4 s, retenez 7 s, expirez 8 s, quatre fois : un classique pour se détendre.',
    'night',
  ),
  _Tip(
    Icons.timer_rounded,
    'Règle des 2 minutes',
    'Si une tâche prend moins de 2 minutes, faites-la tout de suite plutôt que de la repousser.',
    'focus',
  ),
  _Tip(
    Icons.checklist_rounded,
    'Une seule priorité',
    'Choisissez UNE tâche importante pour la journée et commencez par elle.',
    'focus',
  ),
];

// (nom, description, minutes focus, minutes pause, icône, couleur carte)
const _modes = [
  (
    'Pomodoro',
    '25 min de focus, puis 5 min de pause',
    25,
    5,
    Icons.local_fire_department_rounded,
    Color(0xFF26A69A),
  ),
  (
    'Deep work',
    '50 min sans distraction, puis 10 min de pause',
    50,
    10,
    Icons.psychology_rounded,
    Color(0xFF6B5CE7),
  ),
  (
    'Détox express',
    '15 min loin de l\'écran pour respirer',
    15,
    0,
    Icons.spa_rounded,
    Color(0xFF38B2AC),
  ),
];

const _ringColors = [
  AppC.sky,
  AppC.night,
  AppC.dusk,
  AppC.teal,
  AppC.sun,
];

class SpacePage extends StatefulWidget {
  const SpacePage({super.key});

  @override
  State<SpacePage> createState() => _SpacePageState();
}

class _SpacePageState extends State<SpacePage> with WidgetsBindingObserver {
  final _bridge = NativeBridge();
  SharedPreferences? _prefs;
  Timer? _ticker;
  int _tick = 0;
  DateTime _now = DateTime.now();

  bool _hasAccess = false;
  List<int> _daily = List.filled(7, 0);
  List<({String name, int minutes})> _top = [];
  int _goal = 240;

  Map<String, int> _appLimits = {};
  final Set<String> _remindedApps = {};

  int _focusEnd = 0;
  String _focusLabel = '';
  int _focusTotalMin = 0;

  bool get _focusActive => _focusEnd > _now.millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  void _onTick() {
    if (!mounted) return;
    _tick++;
    final wasActive = _focusActive;
    _now = DateTime.now();
    if (wasActive && !_focusActive) {
      _clearFocus();
      showToast(context, 'Session terminée, bravo !');
    }
    if (_focusActive || _tick % 30 == 0) setState(() {});
  }

  Map<String, int> _decodeLimits(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _setAppLimit(String appName, int minutes) async {
    final updated = Map<String, int>.from(_appLimits);
    if (minutes <= 0) {
      updated.remove(appName);
      _remindedApps.remove(appName);
    } else {
      updated[appName] = minutes.clamp(15, 480);
      _remindedApps.remove(appName);
    }
    setState(() => _appLimits = updated);
    await _prefs?.setString('app_limits_min', jsonEncode(updated));
    _checkGentleReminders();
  }

  void _checkGentleReminders() {
    for (final app in _top) {
      final limit = _appLimits[app.name];
      if (limit != null && app.minutes >= limit && !_remindedApps.contains(app.name)) {
        _remindedApps.add(app.name);
        if (mounted) {
          showToast(
            context,
            'Rappel doux : ${fmtMinutes(app.minutes)} sur ${app.name} (limite ${fmtMinutes(limit)}).',
          );
        }
      }
    }
  }

  Future<void> _editAppLimit(String appName) async {
    int selected = _appLimits[appName] ?? 30;
    final result = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppC.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Limite quotidienne · $appName', style: tx(18, w: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  'Recevez un rappel bienveillant quand vous atteignez cette durée.',
                  style: tx(12, c: AppC.muted),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => setModalState(
                        () => selected = (selected - 15).clamp(15, 480),
                      ),
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        color: AppC.indigo,
                        size: 30,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(fmtMinutes(selected), style: tx(24, w: FontWeight.w800)),
                    ),
                    IconButton(
                      onPressed: () => setModalState(
                        () => selected = (selected + 15).clamp(15, 480),
                      ),
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: AppC.indigo,
                        size: 30,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (_appLimits.containsKey(appName))
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, 0),
                        child: Text(
                          'Retirer',
                          style: tx(13, w: FontWeight.w600, c: AppC.dusk),
                        ),
                      ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppC.indigo,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, selected),
                      child: const Text('Enregistrer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null) {
      await _setAppLimit(appName, result);
    }
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final access = await _bridge.hasUsageAccess();
    final data = access ? await _bridge.getScreenTime() : null;
    if (!mounted) return;
    setState(() {
      _prefs = p;
      _now = DateTime.now();
      _hasAccess = access;
      if (data != null) {
        _daily = data.daily.length == 7 ? data.daily : List.filled(7, 0);
        _top = data.top;
      }
      _goal = p.getInt('screen_goal_min') ?? 240;
      _appLimits = _decodeLimits(p.getString('app_limits_min'));
      _focusEnd = p.getInt('focus_end') ?? 0;
      _focusLabel = p.getString('focus_label') ?? '';
      _focusTotalMin = p.getInt('focus_total_min') ?? 0;
    });
    _checkGentleReminders();
  }

  Future<void> _startFocus((String, String, int, int, IconData, Color) m) async {
    final end = DateTime.now().add(Duration(minutes: m.$3));
    await _prefs?.setInt('focus_end', end.millisecondsSinceEpoch);
    await _prefs?.setString('focus_label', m.$1);
    await _prefs?.setInt('focus_total_min', m.$3);
    await _bridge.startFocus(m.$3, m.$4, m.$1);
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() {
      _focusEnd = end.millisecondsSinceEpoch;
      _focusLabel = m.$1;
      _focusTotalMin = m.$3;
      _now = DateTime.now();
    });
  }

  Future<void> _stopFocus() async {
    await _bridge.cancelFocus();
    await _clearFocus();
    HapticFeedback.selectionClick();
  }

  Future<void> _clearFocus() async {
    await _prefs?.remove('focus_end');
    await _prefs?.remove('focus_label');
    await _prefs?.remove('focus_total_min');
    if (mounted) setState(() => _focusEnd = 0);
  }

  Future<void> _setGoal(int v) async {
    final g = v.clamp(60, 720);
    setState(() => _goal = g);
    await _prefs?.setInt('screen_goal_min', g);
  }

  String get _phaseKey {
    final p = _prefs;
    int m(String k, int dh, int dm) =>
        (p?.getInt('${k}_hour') ?? dh) * 60 + (p?.getInt('${k}_minute') ?? dm);
    final n = _now.hour * 60 + _now.minute;
    final sr = m('sunrise', 7, 0),
        ss = m('sunset', 19, 0),
        nt = m('night', 22, 0);
    if (n >= nt || n < sr) return 'night';
    if (n >= ss) return 'sunset';
    return n < sr + 180 ? 'sunrise' : 'day';
  }

  _Tip get _tipNow {
    final pool = _tips.where((t) => t.phase == _phaseKey).toList();
    final day = _now.difference(DateTime(_now.year, 1, 1)).inDays;
    return pool[day % pool.length];
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text('Votre bien-être', style: tx(13, c: AppC.muted)),
          const SizedBox(height: 2),
          Text('Mon espace', style: tx(28, w: FontWeight.w800, ls: -0.5)),
          const SizedBox(height: 20),
          _screenTimeCard(),
          const SizedBox(height: 16),
          _focusCard(),
          const SizedBox(height: 16),
          _tipsCard(),
        ],
      ),
    );
  }

  Widget _screenTimeCard() {
    if (!_hasAccess) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: withA(AppC.sky, 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.hourglass_bottom_rounded, color: AppC.sky),
                ),
                const SizedBox(width: 12),
                Text('Temps d\'écran', style: tx(16, w: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Pour afficher le temps passé sur votre téléphone, autorisez l\'accès à '
              'l\'utilisation dans les réglages Android. Ces données restent sur votre téléphone.',
              style: tx(13, c: AppC.muted, h: 1.35),
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppC.sky,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => _bridge.openUsageAccess(),
              child: const Text('Autoriser l\'accès'),
            ),
          ],
        ),
      );
    }

    final today = _daily.last;
    final yesterday = _daily[5];
    final ratio = (today / _goal).clamp(0.0, 1.0);
    final maxV = math.max(1, _daily.reduce(math.max));
    const letters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    final totalTopMin = math.max(
      1,
      _top.fold<int>(0, (sum, item) => sum + item.minutes),
    );
    final segments = _top.isEmpty
        ? [(ratio.clamp(0.15, 1.0), AppC.sky)]
        : [
            for (var i = 0; i < _top.length; i++)
              (
                (_top[i].minutes / totalTopMin).clamp(0.08, 1.0),
                _ringColors[i % _ringColors.length],
              ),
          ];

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Temps d\'écran', style: tx(16, w: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppC.cardTint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Hier : ${fmtMinutes(yesterday)}',
                  style: tx(11, w: FontWeight.w600, c: AppC.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          SizedBox(
            width: 196,
            height: 196,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(176, 176),
                  painter: _SegmentedRingPainter(segments: segments),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'AUJOURD\'HUI',
                      style: tx(11, w: FontWeight.w700, c: AppC.muted, ls: 0.8),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fmtMinutes(today),
                      style: tx(24, w: FontWeight.w800, ls: -0.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Obj. ${fmtMinutes(_goal)}',
                      style: tx(11, w: FontWeight.w600, c: AppC.sky),
                    ),
                  ],
                ),
                Positioned(
                  top: 6,
                  right: 16,
                  child: _PastelBubble(
                    color: AppC.sky,
                    icon: Icons.phone_android_rounded,
                  ),
                ),
                Positioned(
                  bottom: 14,
                  left: 12,
                  child: _PastelBubble(
                    color: AppC.night,
                    icon: Icons.apps_rounded,
                  ),
                ),
                Positioned(
                  bottom: 18,
                  right: 10,
                  child: _PastelBubble(
                    color: AppC.dusk,
                    icon: Icons.timelapse_rounded,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Objectif quotidien : ${fmtMinutes(_goal)}',
                  style: tx(12, w: FontWeight.w600, c: AppC.muted),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _setGoal(_goal - 30),
                icon: const Icon(Icons.remove_circle_outline, color: AppC.muted),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _setGoal(_goal + 30),
                icon: const Icon(Icons.add_circle_outline, color: AppC.sky),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('7 derniers jours', style: tx(13, w: FontWeight.w700)),
          ),
          const SizedBox(height: 10),

          SizedBox(
            height: 104,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final d = _now.subtract(Duration(days: 6 - i));
                final h = math.max(6.0, 72.0 * _daily[i] / maxV);
                final isToday = i == 6;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 14,
                        height: h,
                        decoration: BoxDecoration(
                          color: isToday ? AppC.sky : AppC.cardTint,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        letters[d.weekday - 1],
                        style: tx(
                          11,
                          w: isToday ? FontWeight.w800 : FontWeight.w500,
                          c: isToday ? AppC.sky : AppC.muted,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),

          if (_top.isNotEmpty) ...[
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Applications les plus utilisées',
                style: tx(13, w: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _top.length; i++) ...[
              Builder(
                builder: (context) {
                  final app = _top[i];
                  final limit = _appLimits[app.name];
                  final exceeded = limit != null && app.minutes >= limit;
                  final barColor = exceeded
                      ? AppC.dusk
                      : _ringColors[i % _ringColors.length];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: barColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                app.name,
                                style: tx(14, w: FontWeight.w600),
                              ),
                            ),
                            Text(
                              fmtMinutes(app.minutes),
                              style: tx(
                                13,
                                w: FontWeight.w600,
                                c: exceeded ? AppC.dusk : AppC.muted,
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _editAppLimit(app.name),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: exceeded
                                      ? withA(AppC.dusk, 0.14)
                                      : AppC.cardTint,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  limit != null
                                      ? 'Lim. ${fmtMinutes(limit)}'
                                      : 'Limite',
                                  style: tx(
                                    11,
                                    w: FontWeight.w700,
                                    c: exceeded
                                        ? AppC.dusk
                                        : (limit != null ? AppC.indigo : AppC.muted),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (app.minutes / _top.first.minutes).clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: AppC.cardTint,
                            valueColor: AlwaysStoppedAnimation(barColor),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _focusCard() {
    if (_focusActive) {
      final remaining =
          Duration(milliseconds: _focusEnd - _now.millisecondsSinceEpoch);
      final totalMs = math.max(1, _focusTotalMin * 60000);
      final progress = 1 - (remaining.inMilliseconds / totalMs).clamp(0.0, 1.0);
      final mm = remaining.inMinutes.toString().padLeft(2, '0');
      final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');
      return AppCard(
        child: Column(
          children: [
            Text(_focusLabel, style: tx(16, w: FontWeight.w700)),
            const SizedBox(height: 14),
            SizedBox(
              width: 152,
              height: 152,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 152,
                    height: 152,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 10,
                      strokeCap: StrokeCap.round,
                      backgroundColor: AppC.cardTint,
                      valueColor: const AlwaysStoppedAnimation(AppC.indigo),
                    ),
                  ),
                  Text('$mm:$ss', style: tx(30, w: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Posez le téléphone, je vous préviens à la fin.',
              style: tx(12, c: AppC.muted),
            ),
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppC.dusk),
              onPressed: _stopFocus,
              child: const Text('Arrêter la session'),
            ),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Modes anti-procrastination', style: tx(16, w: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Lancez une session : une notification vous prévient à la fin.',
            style: tx(12, c: AppC.muted),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _modes.length; i++) ...[
            _FocusModeTile(
              mode: _modes[i],
              onTap: () => _startFocus(_modes[i]),
            ),
            if (i < _modes.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _tipsCard() {
    final tip = _tipNow;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Conseil du moment', style: tx(13, w: FontWeight.w700, c: AppC.muted)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: withA(AppC.sun, 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(tip.icon, color: AppC.sun),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tip.title, style: tx(15, w: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(tip.text, style: tx(13, c: AppC.muted, h: 1.35)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              iconColor: AppC.muted,
              collapsedIconColor: AppC.muted,
              title: Text('Tous les conseils', style: tx(14, w: FontWeight.w600)),
              children: [
                for (final t in _tips)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(t.icon, color: AppC.indigo, size: 20),
                    title: Text(t.title, style: tx(14, w: FontWeight.w600)),
                    subtitle: Text(t.text, style: tx(12, c: AppC.muted)),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Conseils généraux de bien-être, ils ne remplacent pas un avis médical.',
                    style: tx(11, c: AppC.muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusModeTile extends StatelessWidget {
  const _FocusModeTile({required this.mode, required this.onTap});
  final (String, String, int, int, IconData, Color) mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: withA(mode.$6, 0.1),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: mode.$6,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(mode.$5, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mode.$1, style: tx(15, w: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(mode.$2, style: tx(12, c: AppC.muted)),
                ],
              ),
            ),
            Icon(Icons.play_circle_fill_rounded, color: mode.$6, size: 30),
          ],
        ),
      ),
    );
  }
}

class _PastelBubble extends StatelessWidget {
  const _PastelBubble({required this.color, required this.icon});
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppC.card,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: withA(color, 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, size: 17, color: color),
    );
  }
}

class _SegmentedRingPainter extends CustomPainter {
  _SegmentedRingPainter({required this.segments});
  final List<(double, Color)> segments;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeW = 12.0;
    const gap = 0.08;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - strokeW / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppC.cardTint
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );

    final totalWeight = segments.fold<double>(0, (s, e) => s + e.$1);
    var startAngle = -math.pi / 2;

    for (final seg in segments) {
      final sweep = ((seg.$1 / math.max(0.01, totalWeight)) * 2 * math.pi) - gap;
      if (sweep > 0.04) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle + gap / 2,
          sweep,
          false,
          Paint()
            ..color = seg.$2
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeW
            ..strokeCap = StrokeCap.round,
        );
      }
      startAngle += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedRingPainter old) =>
      old.segments != segments;
}