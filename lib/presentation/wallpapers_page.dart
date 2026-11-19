import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../data/native_bridge.dart';
import 'ui.dart';

const _phaseSlots = [
  ('sunrise', 'Lever du soleil', 'Affiché le matin', Icons.wb_sunny_rounded, AppC.sun),
  ('sunset', 'Coucher du soleil', 'Affiché en soirée', Icons.wb_twilight_rounded, AppC.dusk),
  ('night', 'Nuit profonde', 'Affiché la nuit', Icons.bedtime_rounded, AppC.night),
];

List<Color> _placeholder(String slot) => switch (slot) {
      'sunrise' => const [Color(0xFFFBBF24), Color(0xFFFDE68A)],
      'sunset' => const [Color(0xFFFB7185), Color(0xFF818CF8)],
      'night' => const [Color(0xFF6B5CE7), Color(0xFF3B308E)],
      _ => const [Color(0xFF60A5FA), Color(0xFF93C5FD)],
    };

class WallpapersPage extends StatefulWidget {
  const WallpapersPage({super.key});

  @override
  State<WallpapersPage> createState() => _WallpapersPageState();
}

class _WallpapersPageState extends State<WallpapersPage> {
  final _bridge = NativeBridge();
  final _picker = ImagePicker();
  Map<String, String?> _paths = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await _bridge.getWallpapers();
    if (mounted) setState(() => _paths = p);
  }

  Future<void> _pick(String slot) async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;
    setState(() => _busy = true);
    final path = await _bridge.importWallpaper(slot, x.path);
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    HapticFeedback.selectionClick();
    showToast(context, path == null ? 'Image impossible à lire' : 'Fond enregistré');
  }

  Future<void> _reset(String slot) async {
    await _bridge.removeWallpaper(slot);
    await _load();
    if (mounted) showToast(context, 'Retour au fond par défaut');
  }

  Future<void> _try(String slot) async {
    await _bridge.applyPhaseNow(slot);
    if (mounted) showToast(context, 'Fond appliqué à votre téléphone');
  }

  @override
  Widget build(BuildContext context) {
    final hasOriginal = _paths['original'] != null;
    return SafeArea(
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text('Personnalisation', style: tx(13, c: AppC.muted)),
              const SizedBox(height: 2),
              Text('Fonds d\'écran', style: tx(28, w: FontWeight.w800, ls: -0.5)),
              const SizedBox(height: 20),
              _slotCard(
                slot: 'original',
                title: 'Mon fond habituel',
                subtitle: 'Remis quand vous mettez l\'app en pause',
                icon: Icons.home_rounded,
                color: AppC.indigo,
                highlight: !hasOriginal,
                hint: hasOriginal
                    ? null
                    : 'Choisissez le fond que vous aviez avant : sinon Android remet son fond par défaut pendant les pauses.',
              ),
              const SizedBox(height: 22),
              Text(
                'FONDS PAR PHASE',
                style: tx(11, w: FontWeight.w700, c: AppC.muted, ls: 1.1),
              ),
              const SizedBox(height: 12),
              for (final s in _phaseSlots) ...[
                _slotCard(
                  slot: s.$1,
                  title: s.$2,
                  subtitle: s.$3,
                  icon: s.$4,
                  color: s.$5,
                  canTry: true,
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
          if (_busy)
            Container(
              color: withA(Colors.white, 0.55),
              child: const Center(
                child: CircularProgressIndicator(color: AppC.indigo),
              ),
            ),
        ],
      ),
    );
  }

  Widget _slotCard({
    required String slot,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    bool canTry = false,
    bool highlight = false,
    String? hint,
  }) {
    final path = _paths[slot];
    final custom = path != null;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Aperçu vertical avec badge pilule blanc façon Envol
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 82,
                      height: 132,
                      child: custom
                          ? Image.file(
                              File(path),
                              fit: BoxFit.cover,
                              cacheWidth: 246,
                            )
                          : Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: _placeholder(slot),
                                ),
                              ),
                              child: Icon(
                                icon,
                                color: withA(Colors.white, 0.9),
                                size: 30,
                              ),
                            ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppC.card,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        custom ? 'Perso' : 'Défaut',
                        style: tx(
                          10,
                          w: FontWeight.w700,
                          c: custom ? AppC.indigo : AppC.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, color: color, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(title, style: tx(15, w: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle, style: tx(12, c: AppC.muted)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: AppC.cardTint,
                            foregroundColor: AppC.indigo,
                          ),
                          onPressed: () => _pick(slot),
                          child: Text(custom ? 'Changer' : 'Choisir'),
                        ),
                        if (canTry)
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: AppC.ink,
                              side: const BorderSide(color: AppC.stroke),
                            ),
                            onPressed: () => _try(slot),
                            child: const Text('Essayer'),
                          ),
                        if (custom)
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: AppC.muted,
                            ),
                            onPressed: () => _reset(slot),
                            child: const Text('Par défaut'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (highlight && hint != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: withA(AppC.dusk, 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(hint, style: tx(12, c: AppC.dusk, h: 1.35)),
            ),
          ],
        ],
      ),
    );
  }
}