import 'dart:async';
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
  _Tip(Icons.wb_sunny_rounded, 'Lumière du matin',
      'Quelques minutes de lumière naturelle après le réveil aident à caler votre horloge interne.', 'sunrise'),
  _Tip(Icons.water_drop_rounded, 'Hydratation',
      'Un verre d\'eau au réveil aide à relancer la concentration.', 'sunrise'),
  _Tip(Icons.visibility_rounded, 'Règle 20-20-20',
      'Toutes les 20 min, regardez un point à 6 m pendant 20 s pour reposer vos yeux.', 'day'),
  _Tip(Icons.directions_walk_rounded, 'Micro-pause active',
      'Levez-vous 2 minutes chaque heure : marche, étirements, respiration.', 'day'),
  _Tip(Icons.coffee_rounded, 'Caféine',
      'Évitez la caféine au moins 6 h avant le coucher pour ne pas retarder l\'endormissement.', 'sunset'),
  _Tip(Icons.restaurant_rounded, 'Dîner léger',
      'Un repas léger quelques heures avant de dormir favorise un meilleur sommeil.', 'sunset'),
  _Tip(Icons.bedtime_rounded, 'Téléphone hors du lit',
      'Posez le téléphone hors de portée : un lit sans écran aide à mieux s\'endormir.', 'night'),
  _Tip(Icons.self_improvement_rounded, 'Respiration 4-7-8',
      'Inspirez 4 s, retenez 7 s, expirez 8 s, quatre fois : un classique pour se détendre.', 'night'),
  _Tip(Icons.timer_rounded, 'Règle des 2 minutes',
      'Si une tâche prend moins de 2 minutes, faites-la tout de suite plutôt que de la repousser.', 'focus'),
  _Tip(Icons.checklist_rounded, 'Une seule priorité',
      'Choisissez UNE tâche importante pour la journée et commencez par elle.', 'focus'),
];

// (nom, description, minutes de focus, minutes de pause, icône)
const _modes = [
  ('Pomodoro', '25 min de focus, puis 5 min de pause', 25, 5, Icons.local_fire_department_rounded),
  ('Deep work', '50 min sans distraction, puis 10 min de pause', 50, 10, Icons.psychology_rounded),
  ('Détox express', '15 min loin de l\'écran pour respirer', 15, 0, Icons.spa_rounded),
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
      _focusEnd = p.getInt('focus_end') ?? 0;
      _focusLabel = p.getString('focus_label') ?? '';
      _focusTotalMin = p.getInt('focus_total_min') ?? 0;
    });
  }

  // ───────── Focus ─────────
  Future<void> _startFocus((String, String, int, int, IconData) m) async {
    final end = DateTime.now().add(Duration(minutes: m.$3));
    await _prefs?.setInt('focus_end', end.millisecondsSinceEpoch);
    await _prefs?.setString('focus_label', m.$1);
    await _prefs?.setInt('focus_total_min', m.$3);
    await _bridge.startFocus(m.$3, m.$4, m.$1);
    HapticFeedback.mediumImpact();
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

  // ───────── Conseils ─────────
  String get _phaseKey {
    final p = _prefs;
    int m(String k, int dh, int dm) =>
        (p?.getInt('${k}_hour') ?? dh) * 60 + (p?.getInt('${k}_minute') ?? dm);
    final n = _now.hour * 60 + _now.minute;
    final sr = m('sunrise', 7, 0), ss = m('sunset', 19, 0), nt = m('night', 22, 0);
    if (n >= nt || n < sr) return 'night';
    if (n >= ss) return 'sunset';
    return n < sr + 180 ? 'sunrise' : 'day';
  }

  _Tip get _tipNow {
    final pool = _tips.where((t) => t.phase == _phaseKey).toList();
    final day = _now.difference(DateTime(_now.year, 1, 1)).inDays;
    return pool[day % pool.length];
  }

  // ───────── UI ─────────
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text('Votre bien-être', style: tx(14, c: AppC.muted)),
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
            Row(children: [
              const Icon(Icons.hourglass_bottom_rounded, color: AppC.accent),
              const SizedBox(width: 10),
              Text('Temps d\'écran', style: tx(16, w: FontWeight.w700)),
            ]),
            const SizedBox(height: 10),
            Text(
              'Pour afficher le temps passé sur votre téléphone, autorisez l\'accès à '
              'l\'utilisation dans les réglages Android. Ces données restent sur votre téléphone.',
              style: tx(13, c: AppC.muted),
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppC.accent, foregroundColor: Colors.black),
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
    final barColor = ratio < 0.8 ? AppC.accent : (ratio < 1 ? AppC.dusk : Colors.redAccent);
    final maxV = math.max(1, _daily.reduce(math.max));
    const letters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Temps d\'écran aujourd\'hui', style: tx(13, c: AppC.muted)),
          const SizedBox(height: 4),
          Text(fmtMinutes(today), style: tx(34, w: FontWeight.w800, ls: -1)),
          Text('Hier : ${fmtMinutes(yesterday)}', style: tx(12, c: AppC.muted)),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppC.stroke,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                  child: Text('Objectif : ${fmtMinutes(_goal)}', style: tx(12, c: AppC.muted))),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _setGoal(_goal - 30),
                  icon: const Icon(Icons.remove_circle_outline, color: AppC.muted)),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _setGoal(_goal + 30),
                  icon: const Icon(Icons.add_circle_outline, color: AppC.muted)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final d = _now.subtract(Duration(days: 6 - i));
                final h = math.max(4.0, 70.0 * _daily[i] / maxV);
                final isToday = i == 6;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 18,
                        height: h,
                        decoration: BoxDecoration(
                          color: isToday ? AppC.accent : withA(AppC.accent, 0.3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(letters[d.weekday - 1],
                          style: tx(11, c: isToday ? Colors.white : AppC.muted)),
                    ],
                  ),
                );
              }),
            ),
          ),
          if (_top.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('Applications les plus utilisées', style: tx(13, c: AppC.muted)),
            const SizedBox(height: 10),
            for (final a in _top)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(a.name, style: tx(14, w: FontWeight.w600))),
                      Text(fmtMinutes(a.minutes), style: tx(13, c: AppC.muted)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: a.minutes / _top.first.minutes,
                        minHeight: 5,
                        backgroundColor: AppC.stroke,
                        valueColor: AlwaysStoppedAnimation(withA(AppC.night, 0.9)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _focusCard() {
    if (_focusActive) {
      final remaining = Duration(milliseconds: _focusEnd - _now.millisecondsSinceEpoch);
      final totalMs = math.max(1, _focusTotalMin * 60000);
      final progress = 1 - (remaining.inMilliseconds / totalMs).clamp(0.0, 1.0);
      final mm = remaining.inMinutes.toString().padLeft(2, '0');
      final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');
      return AppCard(
        child: Column(
          children: [
            Text(_focusLabel, style: tx(15, w: FontWeight.w700)),
            const SizedBox(height: 12),
            SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 150,
                    height: 150,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 8,
                      backgroundColor: AppC.stroke,
                      valueColor: const AlwaysStoppedAnimation(AppC.accent),
                    ),
                  ),
                  Text('$mm:$ss', style: tx(32, w: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('Posez le téléphone, je vous préviens à la fin.',
                style: tx(12, c: AppC.muted)),
            const SizedBox(height: 8),
            TextButton(onPressed: _stopFocus, child: const Text('Arrêter la session')),
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
          Text('Lancez une session : une notification vous prévient à la fin.',
              style: tx(12, c: AppC.muted)),
          const SizedBox(height: 10),
          for (final m in _modes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: withA(AppC.accent, 0.15), borderRadius: BorderRadius.circular(14)),
                child: Icon(m.$5, color: AppC.accent),
              ),
              title: Text(m.$1, style: tx(15, w: FontWeight.w700)),
              subtitle: Text(m.$2, style: tx(12, c: AppC.muted)),
              trailing: const Icon(Icons.play_circle_fill_rounded, color: AppC.accent, size: 30),
              onTap: () => _startFocus(m),
            ),
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
          Text('Conseil du moment', style: tx(13, c: AppC.muted)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: withA(AppC.sun, 0.15), borderRadius: BorderRadius.circular(14)),
                child: Icon(tip.icon, color: AppC.sun),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tip.title, style: tx(15, w: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(tip.text, style: tx(13, c: AppC.muted)),
                  ],
                ),
              ),
            ],
          ),
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
                    leading: Icon(t.icon, color: AppC.muted, size: 20),
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