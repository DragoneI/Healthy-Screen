import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../data/native_bridge.dart';
import 'ui.dart';

// (slot, titre, sous-titre, icône, couleur)
const _phaseSlots = [
  ('sunrise', 'Lever du soleil', 'Affiché le matin', Icons.wb_sunny_rounded, AppC.sun),
  ('sunset', 'Coucher du soleil', 'Affiché en soirée', Icons.wb_twilight_rounded, AppC.dusk),
  ('night', 'Nuit profonde', 'Affiché la nuit', Icons.bedtime_rounded, AppC.night),
];

List<Color> _placeholder(String slot) => switch (slot) {
      'sunrise' => const [Color(0xFFF59E0B), Color(0xFFFDE68A)],
      'sunset' => const [Color(0xFFFB923C), Color(0xFF7C3AED)],
      'night' => const [Color(0xFF1E1B4B), Color(0xFF0B1020)],
      _ => const [Color(0xFF334155), Color(0xFF64748B)],
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
              Text('Personnalisation', style: tx(14, c: AppC.muted)),
              const SizedBox(height: 2),
              Text('Fonds d\'écran', style: tx(28, w: FontWeight.w800, ls: -0.5)),
              const SizedBox(height: 20),
              _slotCard(
                slot: 'original',
                title: 'Mon fond habituel',
                subtitle: 'Remis quand vous mettez l\'app en pause',
                icon: Icons.home_rounded,
                color: AppC.accent,
                highlight: !hasOriginal,
                hint: hasOriginal
                    ? null
                    : 'Choisissez le fond que vous aviez avant : sinon Android remet son fond par défaut pendant les pauses.',
              ),
              const SizedBox(height: 20),
              Text('FONDS PAR PHASE',
                  style: tx(12, w: FontWeight.w700, c: AppC.muted, ls: 1.2)),
              const SizedBox(height: 10),
              for (final s in _phaseSlots) ...[
                _slotCard(
                  slot: s.$1,
                  title: s.$2,
                  subtitle: s.$3,
                  icon: s.$4,
                  color: s.$5,
                  canTry: true,
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
          if (_busy)
            Container(
              color: withA(Colors.black, 0.4),
              child: const Center(child: CircularProgressIndicator(color: AppC.accent)),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppC.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: highlight ? AppC.dusk : AppC.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 72,
                  height: 128,
                  child: custom
                      ? Image.file(File(path), fit: BoxFit.cover, cacheWidth: 216)
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: _placeholder(slot),
                            ),
                          ),
                          child: Icon(icon, color: withA(Colors.white, 0.8)),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(icon, color: color, size: 18),
                      const SizedBox(width: 6),
                      Expanded(child: Text(title, style: tx(15, w: FontWeight.w700))),
                    ]),
                    const SizedBox(height: 2),
                    Text(subtitle, style: tx(12, c: AppC.muted)),
                    const SizedBox(height: 4),
                    Text(custom ? 'Personnalisé' : 'Par défaut',
                        style: tx(12, w: FontWeight.w600, c: custom ? AppC.accent : AppC.muted)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact),
                          onPressed: () => _pick(slot),
                          child: Text(custom ? 'Changer' : 'Choisir'),
                        ),
                        if (canTry)
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: AppC.stroke)),
                            onPressed: () => _try(slot),
                            child: const Text('Essayer'),
                          ),
                        if (custom)
                          TextButton(
                            style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: AppC.muted),
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
          if (hint != null) ...[
            const SizedBox(height: 12),
            Text(hint, style: tx(12, c: AppC.dusk)),
          ],
        ],
      ),
    );
  }
}