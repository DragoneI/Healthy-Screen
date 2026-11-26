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

const _dayNames = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];

// Corrige l'affichage de certains noms d'apps renvoyés par le code natif.
// Format : 'nom affiché actuellement': 'nom voulu'
const _nameAliases = <String, String>{
  'DLS 7': 'DLS 26',
};

String _label(String raw) => _nameAliases[raw] ?? raw;

Color _goalColor(double ratio) {
  if (ratio < 0.75) return AppC.teal;
  if (ratio < 1.0) return AppC.sun;
  return AppC.dusk;
}

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
  int? _selectedRingIndex;
  int _selectedDay = 6;

  Map<String, int> _appLimits = {};
  Set<String> _hidden = {};
  final Set<String> _remindedApps = {};

  int _focusEnd = 0;
  String _focusLabel = '';
  int _focusTotalMin = 0;

  bool get _focusActive => _focusEnd > _now.millisecondsSinceEpoch;

  // Apps affichées : noms corrigés + apps masquées retirées du classement.
  List<({String name, int minutes})> get _apps => [
        for (final a in _top)
          if (!_hidden.contains(_label(a.name)))
            (name: _label(a.name), minutes: a.minutes),
      ];

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
    for (final app in _apps) {
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

  Future<void> _hideApp(String name) async {
    setState(() {
      _hidden = {..._hidden, name};
      _selectedRingIndex = null;
    });
    await _prefs?.setStringList('hidden_apps', _hidden.toList());
    if (mounted) {
      showToast(context, '$name masqué du classement (le total du jour ne change pas).');
    }
  }

  Future<void> _unhideAll() async {
    setState(() => _hidden = {});
    await _prefs?.remove('hidden_apps');
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

  // Fiche détaillée d'une app (façon AppBlock) : temps, part du jour, limite, actions.
  Future<void> _showAppSheet(int index) async {
    final apps = _apps;
    if (index >= apps.length) return;
    final app = apps[index];
    final color = _ringColors[index % _ringColors.length];
    final today = _daily.last;
    setState(() => _selectedRingIndex = index);
    HapticFeedback.selectionClick();

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppC.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final limit = _appLimits[app.name];
        final share = ((app.minutes / math.max(1, today)) * 100).round().clamp(0, 100);
        final limitRatio = limit == null ? 0.0 : (app.minutes / limit);
        final exceeded = limit != null && app.minutes >= limit;
        final barColor = exceeded ? AppC.dusk : color;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(app.name, style: tx(18, w: FontWeight.w700))),
                  ],
                ),
                const SizedBox(height: 14),
                Text(fmtMinutes(app.minutes), style: tx(34, w: FontWeight.w800, ls: -0.8)),
                const SizedBox(height: 2),
                Text(
                  '$share % de votre temps d\'écran aujourd\'hui',
                  style: tx(12, c: AppC.muted),
                ),
                const SizedBox(height: 16),
                if (limit != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          exceeded
                              ? 'Limite atteinte (${fmtMinutes(limit)})'
                              : 'Limite : ${fmtMinutes(limit)} · reste ${fmtMinutes(limit - app.minutes)}',
                          style: tx(12, w: FontWeight.w600, c: exceeded ? AppC.dusk : AppC.muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: limitRatio.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: AppC.cardTint,
                      valueColor: AlwaysStoppedAnimation(barColor),
                    ),
                  ),
                ] else
                  Text(
                    'Aucune limite définie pour cette application.',
                    style: tx(12, c: AppC.muted),
                  ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: AppC.muted),
                      onPressed: () => Navigator.pop(ctx, 'hide'),
                      icon: const Icon(Icons.visibility_off_rounded, size: 18),
                      label: const Text('Masquer'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppC.indigo,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, 'limit'),
                      icon: const Icon(Icons.timer_outlined, size: 18),
                      label: Text(limit == null ? 'Définir une limite' : 'Modifier la limite'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (action == 'limit') {
      await _editAppLimit(app.name);
    } else if (action == 'hide') {
      await _hideApp(app.name);
    }
  }

  int? _segmentIndexAt(Offset localPos, Size size, List<(double, Color)> segments) {
    if (segments.isEmpty) return null;
    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    const baseStrokeW = 12.0;
    final outerR = math.min(size.width, size.height) / 2;
    final innerR = outerR - (baseStrokeW + 14);
    if (dist < innerR || dist > outerR + 8) return null;

    var angle = math.atan2(dy, dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;

    final totalWeight = segments.fold<double>(0, (s, e) => s + e.$1);
    var cursor = 0.0;
    for (var i = 0; i < segments.length; i++) {
      final sweep = (segments[i].$1 / math.max(0.01, totalWeight)) * 2 * math.pi;
      if (angle >= cursor && angle <= cursor + sweep) return i;
      cursor += sweep;
    }
    return segments.length - 1;
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
      _hidden = (p.getStringList('hidden_apps') ?? const <String>[]).toSet();
      if (data != null) {
        _daily = data.daily.length == 7 ? data.daily : List.filled(7, 0);
        _top = data.top;
      }
      if (_selectedRingIndex != null && _selectedRingIndex! >= _apps.length) {
        _selectedRingIndex = null;
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
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text('Votre bien-être', style: tx(13, c: AppC.muted)),
            const SizedBox(height: 2),
            Text('Mon espace', style: tx(28, w: FontWeight.w800, ls: -0.5)),
            const SizedBox(height: 20),
            _screenTimeCard(),
            if (_hasAccess) ...[
              const SizedBox(height: 16),
              _reportCard(),
              if (_apps.isNotEmpty || _hidden.isNotEmpty) ...[
                const SizedBox(height: 16),
                _appsCard(),
              ],
            ],
            const SizedBox(height: 16),
            _focusCard(),
            const SizedBox(height: 16),
            _tipsCard(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Carte 1 : jauge animée
  // ---------------------------------------------------------------------------
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
                    color: withA(AppC.indigo, 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.hourglass_bottom_rounded, color: AppC.indigo),
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
                backgroundColor: AppC.indigo,
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
    final ratio = today / math.max(1, _goal);
    final goalColor = _goalColor(ratio);
    final apps = _apps;

    final totalTopMin = math.max(1, apps.fold<int>(0, (sum, item) => sum + item.minutes));
    final List<(double, Color)> segments = apps.isEmpty
        ? [(1.0, AppC.indigo)]
        : [
            for (var i = 0; i < apps.length; i++)
              (
                (apps[i].minutes / totalTopMin).clamp(0.08, 1.0),
                _ringColors[i % _ringColors.length],
              ),
          ];

    final selectedApp = (_selectedRingIndex != null && _selectedRingIndex! < apps.length)
        ? apps[_selectedRingIndex!]
        : null;
    final selectedColor = _selectedRingIndex != null
        ? _ringColors[_selectedRingIndex! % _ringColors.length]
        : AppC.indigo;

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
          GestureDetector(
            onTapDown: (details) {
              if (apps.isEmpty) return;
              const ringSize = Size(176, 176);
              const outerBox = Size(196, 196);
              final offsetInRing = Offset(
                details.localPosition.dx - (outerBox.width - ringSize.width) / 2,
                details.localPosition.dy - (outerBox.height - ringSize.height) / 2,
              );
              final hitIdx = _segmentIndexAt(offsetInRing, ringSize, segments);
              setState(() {
                if (hitIdx != null) {
                  _selectedRingIndex = _selectedRingIndex == hitIdx ? null : hitIdx;
                } else if (_selectedRingIndex == null) {
                  _selectedRingIndex = 0;
                } else if (_selectedRingIndex! + 1 < apps.length) {
                  _selectedRingIndex = _selectedRingIndex! + 1;
                } else {
                  _selectedRingIndex = null;
                }
              });
              HapticFeedback.selectionClick();
            },
            onLongPress: () {
              if (selectedApp != null) {
                HapticFeedback.mediumImpact();
                _editAppLimit(selectedApp.name);
              }
            },
            child: SizedBox(
              width: 196,
              height: 196,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, _) => CustomPaint(
                      size: const Size(176, 176),
                      painter: _SegmentedRingPainter(
                        segments: segments,
                        selectedIndex: _selectedRingIndex,
                        progress: t,
                        goalRatio: ratio,
                        goalColor: goalColor,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: selectedApp != null
                        ? Column(
                            key: ValueKey('app_${selectedApp.name}'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 96),
                                child: Text(
                                  selectedApp.name.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: tx(10, w: FontWeight.w700, c: selectedColor, ls: 0.6),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                fmtMinutes(selectedApp.minutes),
                                style: tx(22, w: FontWeight.w800, ls: -0.5),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${((selectedApp.minutes / math.max(1, today)) * 100).round().clamp(0, 100)}% du jour',
                                style: tx(10, w: FontWeight.w600, c: AppC.muted),
                              ),
                            ],
                          )
                        : Column(
                            key: const ValueKey('total'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'AUJOURD\'HUI',
                                style: tx(11, w: FontWeight.w700, c: AppC.muted, ls: 0.8),
                              ),
                              const SizedBox(height: 4),
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: today.toDouble()),
                                duration: const Duration(milliseconds: 900),
                                curve: Curves.easeOutCubic,
                                builder: (context, v, _) => Text(
                                  fmtMinutes(v.round()),
                                  style: tx(24, w: FontWeight.w800, ls: -0.5),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${(ratio * 100).round()}% de l\'objectif',
                                style: tx(10, w: FontWeight.w700, c: goalColor),
                              ),
                            ],
                          ),
                  ),
                  Positioned(
                    top: 6,
                    right: 16,
                    child: _PastelBubble(
                      color: AppC.indigo,
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
          ),
          if (selectedApp != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: withA(selectedColor, 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(selectedApp.name, style: tx(13, w: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          _appLimits[selectedApp.name] != null
                              ? 'Limite : ${fmtMinutes(_appLimits[selectedApp.name]!)}'
                              : 'Aucune limite définie',
                          style: tx(11, c: AppC.muted),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppC.indigo,
                    ),
                    onPressed: () => _editAppLimit(selectedApp.name),
                    child: Text('Limite', style: tx(12, w: FontWeight.w700, c: AppC.indigo)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Masquer cette application',
                    onPressed: () => _hideApp(selectedApp.name),
                    icon: const Icon(Icons.visibility_off_rounded, size: 18, color: AppC.muted),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _selectedRingIndex = null),
                    icon: const Icon(Icons.close_rounded, size: 18, color: AppC.muted),
                  ),
                ],
              ),
            ),
          ] else if (apps.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Touchez un segment pour inspecter, appuyez longuement pour limiter',
              textAlign: TextAlign.center,
              style: tx(11, c: AppC.muted),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: goalColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
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
                icon: const Icon(Icons.add_circle_outline, color: AppC.indigo),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Carte 2 : compte rendu quotidien + graphique 7 jours interactif
  // ---------------------------------------------------------------------------
  Widget _reportCard() {
    final today = _daily.last;
    final yesterday = _daily[5];
    final ratio = today / math.max(1, _goal);
    final color = _goalColor(ratio);
    final apps = _apps;

    final prev6 = _daily.sublist(0, 6);
    final avg6 = (prev6.reduce((a, b) => a + b) / 6).round();

    var streak = 0;
    for (var i = 5; i >= 0; i--) {
      if (_daily[i] > 0 && _daily[i] <= _goal) {
        streak++;
      } else {
        break;
      }
    }

    late final IconData headIcon;
    late final String headTitle;
    if (today == 0) {
      headIcon = Icons.hourglass_empty_rounded;
      headTitle = 'Pas encore de données aujourd\'hui';
    } else if (ratio < 0.5) {
      headIcon = Icons.check_circle_rounded;
      headTitle = 'Très bon rythme';
    } else if (ratio < 0.8) {
      headIcon = Icons.trending_up_rounded;
      headTitle = 'Rythme correct';
    } else if (ratio < 1.0) {
      headIcon = Icons.warning_amber_rounded;
      headTitle = 'Vous approchez de votre objectif';
    } else {
      headIcon = Icons.error_outline_rounded;
      headTitle = 'Objectif dépassé';
    }
    final headSub = today >= _goal
        ? 'Dépassé de ${fmtMinutes(today - _goal)} sur un objectif de ${fmtMinutes(_goal)}.'
        : 'Il reste ${fmtMinutes(_goal - today)} avant votre objectif (${(ratio * 100).round()} % atteint).';

    final maxV = math.max(math.max(1, _goal), _daily.reduce(math.max));
    const chartH = 72.0;
    final goalH = chartH * _goal / maxV;
    const letters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    final selD = _now.subtract(Duration(days: 6 - _selectedDay));
    final selV = _daily[_selectedDay];
    final selName = _selectedDay == 6 ? 'Aujourd\'hui' : _dayNames[selD.weekday - 1];
    final selDiff = selV - _goal;
    final selColor = _goalColor(selV / math.max(1, _goal));

    final overs = apps.where((a) {
      final l = _appLimits[a.name];
      return l != null && a.minutes >= l;
    }).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Compte rendu du jour', style: tx(16, w: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppC.cardTint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_dayNames[_now.weekday - 1]} ${_now.day}',
                  style: tx(11, w: FontWeight.w600, c: AppC.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: withA(color, 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: withA(color, 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(headIcon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(headTitle, style: tx(14, w: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(headSub, style: tx(12, c: AppC.muted, h: 1.3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.history_rounded,
                  color: today > yesterday ? AppC.dusk : AppC.teal,
                  value: fmtMinutes(yesterday),
                  label: 'Hier',
                  caption: today > yesterday ? 'Déjà dépassé' : 'Pas encore atteint',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  icon: Icons.show_chart_rounded,
                  color: AppC.indigo,
                  value: fmtMinutes(avg6),
                  label: 'Moy. 6 jours',
                  caption: today > avg6
                      ? '+${fmtMinutes(today - avg6)} auj.'
                      : 'En dessous',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  icon: Icons.local_fire_department_rounded,
                  color: AppC.sun,
                  value: '$streak j',
                  label: 'Sous l\'objectif',
                  caption: streak >= 3 ? 'Bravo !' : 'Continuez',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('7 derniers jours', style: tx(13, w: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Touchez une barre pour voir le détail', style: tx(11, c: AppC.muted)),
          const SizedBox(height: 12),
          SizedBox(
            height: chartH + 6,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: goalH,
                  child: Container(height: 1, color: withA(AppC.dusk, 0.45)),
                ),
                Positioned(
                  right: 0,
                  bottom: goalH + 3,
                  child: Text('objectif', style: tx(9, c: AppC.dusk)),
                ),
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(7, (i) {
                      final h = math.max(6.0, chartH * _daily[i] / maxV);
                      final sel = i == _selectedDay;
                      final over = _daily[i] > _goal;
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() => _selectedDay = i);
                            HapticFeedback.selectionClick();
                          },
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: h),
                              duration: const Duration(milliseconds: 600),
                              curve: Curves.easeOutCubic,
                              builder: (context, v, _) => AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: sel ? 20 : 14,
                                height: v,
                                decoration: BoxDecoration(
                                  color: sel
                                      ? AppC.indigo
                                      : (over ? withA(AppC.dusk, 0.55) : AppC.cardTint),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(7, (i) {
              final d = _now.subtract(Duration(days: 6 - i));
              final sel = i == _selectedDay;
              return Expanded(
                child: Center(
                  child: Text(
                    letters[d.weekday - 1],
                    style: tx(
                      11,
                      w: sel ? FontWeight.w800 : FontWeight.w500,
                      c: sel ? AppC.indigo : AppC.muted,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: withA(selColor, 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(selName, style: tx(13, w: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        selV == 0
                            ? 'Aucune donnée'
                            : (selDiff <= 0
                                ? 'Sous l\'objectif de ${fmtMinutes(-selDiff)}'
                                : 'Au-dessus de l\'objectif de ${fmtMinutes(selDiff)}'),
                        style: tx(11, c: AppC.muted),
                      ),
                    ],
                  ),
                ),
                Text(fmtMinutes(selV), style: tx(20, w: FontWeight.w800, ls: -0.4)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (apps.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.emoji_events_rounded, size: 18, color: AppC.sun),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'N°1 : ${apps.first.name} · ${fmtMinutes(apps.first.minutes)}',
                    style: tx(12, w: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (overs.isNotEmpty) ...[
            Text('Limites atteintes', style: tx(12, w: FontWeight.w700, c: AppC.dusk)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in overs)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: withA(AppC.dusk, 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${a.name} · ${fmtMinutes(a.minutes)}',
                      style: tx(11, w: FontWeight.w600, c: AppC.dusk),
                    ),
                  ),
              ],
            ),
          ] else if (_appLimits.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 18, color: AppC.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Toutes vos limites sont respectées.',
                    style: tx(12, w: FontWeight.w600, c: AppC.teal),
                  ),
                ),
              ],
            )
          else
            Text(
              'Astuce : touchez une application ci-dessous pour lui fixer une limite.',
              style: tx(11, c: AppC.muted),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Carte 3 : classement des applications
  // ---------------------------------------------------------------------------
  Widget _appsCard() {
    final apps = _apps;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Applications les plus utilisées', style: tx(14, w: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Touchez une application pour voir sa fiche', style: tx(11, c: AppC.muted)),
          const SizedBox(height: 12),
          for (var i = 0; i < apps.length; i++)
            Builder(
              builder: (context) {
                final app = apps[i];
                final limit = _appLimits[app.name];
                final exceeded = limit != null && app.minutes >= limit;
                final near = limit != null && !exceeded && app.minutes >= limit * 0.8;
                final isSelected = _selectedRingIndex == i;
                final base = _ringColors[i % _ringColors.length];
                final barColor = exceeded ? AppC.dusk : (near ? AppC.sun : base);
                final barValue = limit != null
                    ? (app.minutes / limit).clamp(0.0, 1.0)
                    : (app.minutes / math.max(1, apps.first.minutes)).clamp(0.0, 1.0);
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _showAppSheet(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? withA(barColor, 0.08) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(color: base, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                app.name,
                                style: tx(
                                  14,
                                  w: isSelected ? FontWeight.w800 : FontWeight.w600,
                                ),
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
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: exceeded
                                      ? withA(AppC.dusk, 0.14)
                                      : AppC.cardTint,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  limit != null ? 'Lim. ${fmtMinutes(limit)}' : 'Limite',
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
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: barValue),
                            duration: const Duration(milliseconds: 700),
                            curve: Curves.easeOutCubic,
                            builder: (context, v, _) => LinearProgressIndicator(
                              value: v,
                              minHeight: 6,
                              backgroundColor: AppC.cardTint,
                              valueColor: AlwaysStoppedAnimation(barColor),
                            ),
                          ),
                        ),
                        if (limit != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            exceeded
                                ? 'Limite atteinte'
                                : '${((app.minutes / limit) * 100).round()} % de la limite',
                            style: tx(10, c: exceeded ? AppC.dusk : AppC.muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          if (_hidden.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppC.muted,
                ),
                onPressed: _unhideAll,
                icon: const Icon(Icons.visibility_rounded, size: 16),
                label: Text(
                  'Réafficher ${_hidden.length} application${_hidden.length > 1 ? 's' : ''} masquée${_hidden.length > 1 ? 's' : ''}',
                  style: tx(12, w: FontWeight.w600, c: AppC.muted),
                ),
              ),
            ),
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

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.caption,
  });
  final IconData icon;
  final Color color;
  final String value, label, caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: withA(color, 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: tx(16, w: FontWeight.w800, ls: -0.3)),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tx(11, w: FontWeight.w600, c: AppC.muted),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tx(10, w: FontWeight.w700, c: color),
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
  _SegmentedRingPainter({
    required this.segments,
    required this.progress,
    required this.goalRatio,
    required this.goalColor,
    this.selectedIndex,
  });
  final List<(double, Color)> segments;
  final int? selectedIndex;
  final double progress;
  final double goalRatio;
  final Color goalColor;

  @override
  void paint(Canvas canvas, Size size) {
    const baseStrokeW = 12.0;
    const gap = 0.08;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - (baseStrokeW + 3) / 2;

    // Anneau extérieur : répartition par application
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppC.cardTint
        ..style = PaintingStyle.stroke
        ..strokeWidth = baseStrokeW,
    );

    final totalWeight = segments.fold<double>(0, (s, e) => s + e.$1);
    var startAngle = -math.pi / 2;

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final sweep = ((seg.$1 / math.max(0.01, totalWeight)) * 2 * math.pi) - gap;
      if (sweep > 0.04) {
        final isSelected = selectedIndex == i;
        final isDimmed = selectedIndex != null && !isSelected;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle + gap / 2,
          sweep * progress,
          false,
          Paint()
            ..color = isDimmed ? withA(seg.$2, 0.35) : seg.$2
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelected ? baseStrokeW + 3.0 : baseStrokeW
            ..strokeCap = StrokeCap.round,
        );
      }
      startAngle += sweep + gap;
    }

    // Anneau intérieur : progression vers l'objectif quotidien
    final goalR = radius - 22;
    canvas.drawCircle(
      center,
      goalR,
      Paint()
        ..color = AppC.cardTint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    final goalSweep = 2 * math.pi * goalRatio.clamp(0.0, 1.0) * progress;
    if (goalSweep > 0.02) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: goalR),
        -math.pi / 2,
        goalSweep,
        false,
        Paint()
          ..color = goalColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedRingPainter old) =>
      old.segments != segments ||
      old.selectedIndex != selectedIndex ||
      old.progress != progress ||
      old.goalRatio != goalRatio ||
      old.goalColor != goalColor;
}