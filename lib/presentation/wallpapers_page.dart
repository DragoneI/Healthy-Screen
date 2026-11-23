import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/native_bridge.dart';
import 'ui.dart';

class _WallpaperPack {
  const _WallpaperPack({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.dawnAsset,
    required this.afternoonAsset,
    required this.duskAsset,
    required this.nightAsset,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final String dawnAsset;
  final String afternoonAsset;
  final String duskAsset;
  final String nightAsset;

  String assetForMoment(String moment) => switch (moment) {
        'dawn' => dawnAsset,
        'afternoon' => afternoonAsset,
        'dusk' => duskAsset,
        _ => nightAsset,
      };
}

const _packs = [
  _WallpaperPack(
    id: 'snow_mountain',
    title: 'Montagne enneigée',
    subtitle: 'Sommets blancs & lumière alpine',
    icon: Icons.landscape_rounded,
    accent: AppC.sky,
    dawnAsset: 'assets/wallpapers/snow_mountain/dawn.jpg',
    afternoonAsset: 'assets/wallpapers/snow_mountain/afternoon.jpg',
    duskAsset: 'assets/wallpapers/snow_mountain/dusk.jpg',
    nightAsset: 'assets/wallpapers/snow_mountain/night.jpg',
  ),
  _WallpaperPack(
    id: 'ancient_temple',
    title: 'Temple antique',
    subtitle: 'Architecture sacrée & sérénité',
    icon: Icons.account_balance_rounded,
    accent: AppC.sun,
    dawnAsset: 'assets/wallpapers/ancient_temple/dawn.jpg',
    afternoonAsset: 'assets/wallpapers/ancient_temple/afternoon.jpg',
    duskAsset: 'assets/wallpapers/ancient_temple/dusk.jpg',
    nightAsset: 'assets/wallpapers/ancient_temple/night.jpg',
  ),
  _WallpaperPack(
    id: 'sea',
    title: 'Mer',
    subtitle: 'Océan, vagues & horizon calme',
    icon: Icons.water_rounded,
    accent: AppC.teal,
    dawnAsset: 'assets/wallpapers/sea/dawn.jpg',
    afternoonAsset: 'assets/wallpapers/sea/afternoon.jpg',
    duskAsset: 'assets/wallpapers/sea/dusk.jpg',
    nightAsset: 'assets/wallpapers/sea/night.jpg',
  ),
  _WallpaperPack(
    id: 'desert_1',
    title: 'Désert I',
    subtitle: 'Dunes dorées & grands espaces',
    icon: Icons.wb_sunny_rounded,
    accent: Color(0xFFE07A5F),
    dawnAsset: 'assets/wallpapers/desert_1/dawn.jpg',
    afternoonAsset: 'assets/wallpapers/desert_1/afternoon.jpg',
    duskAsset: 'assets/wallpapers/desert_1/dusk.jpg',
    nightAsset: 'assets/wallpapers/desert_1/night.jpg',
  ),
  _WallpaperPack(
    id: 'desert_2',
    title: 'Désert II',
    subtitle: 'Reliefs minéraux & ciel pur',
    icon: Icons.terrain_rounded,
    accent: AppC.dusk,
    dawnAsset: 'assets/wallpapers/desert_2/dawn.jpg',
    afternoonAsset: 'assets/wallpapers/desert_2/afternoon.jpg',
    duskAsset: 'assets/wallpapers/desert_2/dusk.jpg',
    nightAsset: 'assets/wallpapers/desert_2/night.jpg',
  ),
  _WallpaperPack(
    id: 'forest',
    title: 'Forêt',
    subtitle: 'Canopée verte & fraîcheur naturelle',
    icon: Icons.forest_rounded,
    accent: AppC.indigo,
    dawnAsset: 'assets/wallpapers/forest/dawn.jpg',
    afternoonAsset: 'assets/wallpapers/forest/afternoon.jpg',
    duskAsset: 'assets/wallpapers/forest/dusk.jpg',
    nightAsset: 'assets/wallpapers/forest/night.jpg',
  ),
];

class WallpapersPage extends StatefulWidget {
  const WallpapersPage({super.key});

  @override
  State<WallpapersPage> createState() => _WallpapersPageState();
}

class _WallpapersPageState extends State<WallpapersPage> {
  final _bridge = NativeBridge();
  final _picker = ImagePicker();

  SharedPreferences? _prefs;
  Map<String, String?> _customPaths = {};
  String _selectedPackId = 'snow_mountain';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final custom = await _bridge.getWallpapers();
    if (!mounted) return;
    setState(() {
      _prefs = p;
      _customPaths = custom;
      _selectedPackId = p.getString('selected_wallpaper_pack') ?? 'snow_mountain';
    });
  }

  _WallpaperPack get _activePack => _packs.firstWhere(
        (pack) => pack.id == _selectedPackId,
        orElse: () => _packs.first,
      );

  String _currentMomentKey() {
    final p = _prefs;
    int mins(String k, int dh, int dm) =>
        (p?.getInt('${k}_hour') ?? dh) * 60 + (p?.getInt('${k}_minute') ?? dm);
    final now = DateTime.now();
    final n = now.hour * 60 + now.minute;
    final sr = mins('sunrise', 7, 0);
    final ss = mins('sunset', 19, 0);
    final nt = mins('night', 22, 0);

    if (n >= nt || n < sr) return 'night';
    if (n >= ss) return 'dusk';
    if (n < sr + 180) return 'dawn';
    return 'afternoon';
  }

  String _momentToNativePhase(String moment) => switch (moment) {
        'dawn' => 'sunrise',
        'afternoon' => 'sunrise',
        'dusk' => 'sunset',
        _ => 'night',
      };

  Future<String?> _materialiseAsset(String assetPath, String fileTag) async {
    try {
      final data = await rootBundle.load(assetPath);
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/hs_$fileTag.jpg');
      await out.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return out.path;
    } catch (_) {
      return null;
    }
  }

  /// Synchronise les 4 images du pack choisi vers les slots Kotlin et applique la phase courante.
  Future<void> _selectPack(_WallpaperPack pack, {bool applyNow = true}) async {
    setState(() => _busy = true);
    try {
      await _prefs?.setString('selected_wallpaper_pack', pack.id);

      final dawnFile = await _materialiseAsset(pack.dawnAsset, '${pack.id}_dawn');
      final afternoonFile =
          await _materialiseAsset(pack.afternoonAsset, '${pack.id}_afternoon');
      final duskFile = await _materialiseAsset(pack.duskAsset, '${pack.id}_dusk');
      final nightFile = await _materialiseAsset(pack.nightAsset, '${pack.id}_night');

      if (dawnFile != null) {
        await _bridge.importWallpaper('sunrise', dawnFile);
      }
      if (afternoonFile != null) {
        await _bridge.importWallpaper('day', afternoonFile);
      }
      if (duskFile != null) {
        await _bridge.importWallpaper('sunset', duskFile);
      }
      if (nightFile != null) {
        await _bridge.importWallpaper('night', nightFile);
      }

      if (applyNow) {
        final moment = _currentMomentKey();
        final momentAsset = pack.assetForMoment(moment);
        final activeFile =
            await _materialiseAsset(momentAsset, '${pack.id}_active');
        if (activeFile != null) {
          await _bridge.importWallpaper(
            _momentToNativePhase(moment),
            activeFile,
          );
        }
        await _bridge.applyPhaseNow(_momentToNativePhase(moment));
      }

      await _load();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showToast(
        context,
        applyNow
            ? 'Pack « ${pack.title} » activé et appliqué'
            : 'Pack « ${pack.title} » sélectionné',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewMoment(_WallpaperPack pack, String moment, String label) async {
    setState(() => _busy = true);
    try {
      final file = await _materialiseAsset(
        pack.assetForMoment(moment),
        '${pack.id}_preview_$moment',
      );
      if (file != null) {
        final nativePhase = _momentToNativePhase(moment);
        await _bridge.importWallpaper(nativePhase, file);
        await _bridge.applyPhaseNow(nativePhase);
      }
      if (!mounted) return;
      HapticFeedback.selectionClick();
      showToast(context, 'Aperçu « ${pack.title} · $label » appliqué');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickOriginal() async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;
    setState(() => _busy = true);
    final path = await _bridge.importWallpaper('original', x.path);
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    HapticFeedback.selectionClick();
    showToast(
      context,
      path == null ? 'Image impossible à lire' : 'Fond habituel enregistré',
    );
  }

  Future<void> _captureOriginal() async {
    setState(() => _busy = true);
    final path = await _bridge.captureOriginalWallpaper();
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    HapticFeedback.selectionClick();
    showToast(
      context,
      path == null
          ? 'Capture impossible : choisissez votre image manuellement'
          : 'Fond d\'écran actuel enregistré',
    );
  }

  Future<void> _resetOriginal() async {
    await _bridge.removeWallpaper('original');
    await _load();
    if (mounted) showToast(context, 'Fond habituel réinitialisé');
  }

  @override
  Widget build(BuildContext context) {
    final hasOriginal = _customPaths['original'] != null;
    final activePack = _activePack;

    return SafeArea(
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text('Personnalisation', style: tx(13, c: AppC.muted)),
              const SizedBox(height: 2),
              Text(
                'Catalogue de fonds',
                style: tx(28, w: FontWeight.w800, ls: -0.5),
              ),
              const SizedBox(height: 6),
              Text(
                'Choisissez un univers de 4 images qui évolue selon le moment de la journée.',
                style: tx(13, c: AppC.muted, h: 1.35),
              ),
              const SizedBox(height: 18),

              _originalCard(hasOriginal),
              const SizedBox(height: 22),

              Text(
                'THÈMES DISPONIBLES (6 × 4 IMAGES)',
                style: tx(11, w: FontWeight.w700, c: AppC.muted, ls: 1.1),
              ),
              const SizedBox(height: 12),

              for (final pack in _packs) ...[
                _packCard(pack, isSelected: pack.id == activePack.id),
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

  Widget _originalCard(bool hasOriginal) {
    final path = _customPaths['original'];
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: withA(AppC.indigo, 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.home_rounded, color: AppC.indigo),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mon fond habituel', style: tx(15, w: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      hasOriginal
                          ? 'Enregistré · restauré lors des pauses'
                          : 'Non défini · restauré lors des pauses',
                      style: tx(
                        12,
                        w: hasOriginal ? FontWeight.w600 : FontWeight.w500,
                        c: hasOriginal ? AppC.indigo : AppC.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (path != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(path),
                    width: 44,
                    height: 68,
                    fit: BoxFit.cover,
                    cacheWidth: 132,
                  ),
                ),
            ],
          ),
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
                onPressed: _pickOriginal,
                child: Text(hasOriginal ? 'Changer' : 'Choisir'),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppC.ink,
                  side: const BorderSide(color: AppC.stroke),
                ),
                onPressed: _captureOriginal,
                child: const Text('Capturer actuel'),
              ),
              if (hasOriginal)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppC.muted,
                  ),
                  onPressed: _resetOriginal,
                  child: const Text('Effacer'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _packCard(_WallpaperPack pack, {required bool isSelected}) {
    final moments = [
      ('dawn', 'Aube', pack.dawnAsset),
      ('afternoon', 'Après-midi', pack.afternoonAsset),
      ('dusk', 'Crépuscule', pack.duskAsset),
      ('night', 'Nuit', pack.nightAsset),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppC.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isSelected ? pack.accent : AppC.stroke,
          width: isSelected ? 1.8 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: withA(const Color(0xFF2D3766), 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: withA(pack.accent, 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(pack.icon, color: pack.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pack.title, style: tx(16, w: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(pack.subtitle, style: tx(12, c: AppC.muted)),
                  ],
                ),
              ),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: withA(pack.accent, 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Actif',
                    style: tx(11, w: FontWeight.w700, c: pack.accent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Aperçu des 4 moments de la journée (touchez un aperçu pour l'essayer)
          Row(
            children: [
              for (var i = 0; i < moments.length; i++) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => _previewMoment(pack, moments[i].$1, moments[i].$2),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: 9 / 16,
                            child: Image.asset(
                              moments[i].$3,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppC.cardTint,
                                child: const Icon(
                                  Icons.image_not_supported_outlined,
                                  color: AppC.muted,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          moments[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(10, w: FontWeight.w600, c: AppC.muted),
                        ),
                      ],
                    ),
                  ),
                ),
                if (i < moments.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),

          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: isSelected
                ? FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: withA(pack.accent, 0.14),
                      foregroundColor: pack.accent,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _selectPack(pack, applyNow: true),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Réappliquer ce pack maintenant'),
                  )
                : FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppC.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _selectPack(pack, applyNow: true),
                    child: const Text('Utiliser ce pack'),
                  ),
          ),
        ],
      ),
    );
  }
}