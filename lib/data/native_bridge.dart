import 'package:flutter/services.dart';
import '../domain/schedule_config.dart';

class NativeBridge {
  static const _channel = MethodChannel('circadian/native');

  // Envoie la configuration horaire au côté Android
  Future<void> saveSchedule(ScheduleConfig config) async {
    await _channel.invokeMethod('saveSchedule', config.toMap());
  }

  // Vérification des permissions spéciales
  Future<bool> canWriteSettings() async {
    final result = await _channel.invokeMethod<bool>('canWriteSettings');
    return result ?? false;
  }

  Future<void> openWriteSettings() async {
    await _channel.invokeMethod('openWriteSettings');
  }

  Future<bool> canScheduleExact() async {
    final result = await _channel.invokeMethod<bool>('canScheduleExact');
    return result ?? false;
  }

  Future<void> openExactAlarmSettings() async {
    await _channel.invokeMethod('openExactAlarmSettings');
  }

  /// Aperçu en direct de la luminosité (0–255) pendant que l'on bouge le curseur.
  Future<void> previewBrightness(int level) async {
    await _channel.invokeMethod('previewBrightness', {'level': level});
  }

  /// Remet la luminosité d'avant l'aperçu.
  Future<void> restoreBrightness() async {
    await _channel.invokeMethod('restoreBrightness');
  }

  /// 0 = reprendre · -1 = pause jusqu'à reprise manuelle · >0 = pause jusqu'à ce timestamp (ms).
  /// Retire le fond d'écran de l'app à la pause, le réapplique à la reprise.
  Future<void> setPaused(int untilMs) async {
    await _channel.invokeMethod('setPaused', {'untilMs': untilMs});
  }

  // ───────── Fonds d'écran ─────────

  /// Chemins des fonds personnalisés : original, sunrise, sunset, night (null = par défaut).
  Future<Map<String, String?>> getWallpapers() async {
    final r = await _channel.invokeMethod<Map>('getWallpapers');
    return {
      for (final e in (r ?? {}).entries) e.key as String: e.value as String?,
    };
  }

  /// Copie et redimensionne l'image choisie ; retourne le nouveau chemin (ou null si échec).
  Future<String?> importWallpaper(String slot, String path) async {
    return _channel.invokeMethod<String>('importWallpaper', {'slot': slot, 'path': path});
  }

  Future<void> removeWallpaper(String slot) async {
    await _channel.invokeMethod('removeWallpaper', {'slot': slot});
  }

  /// Applique tout de suite le fond d'une phase (sunrise / sunset / night).
  Future<void> applyPhaseNow(String phase) async {
    await _channel.invokeMethod('applyPhaseNow', {'phase': phase});
  }

  // ───────── Temps d'écran ─────────

  Future<bool> hasUsageAccess() async {
    return (await _channel.invokeMethod<bool>('hasUsageAccess')) ?? false;
  }

  Future<void> openUsageAccess() async {
    await _channel.invokeMethod('openUsageAccess');
  }

  Future<ScreenTimeData?> getScreenTime() async {
    final r = await _channel.invokeMethod<Map>('getScreenTime');
    if (r == null) return null;
    final daily = (r['daily'] as List).map((e) => (e as num).toInt()).toList();
    final top = (r['top'] as List).map((e) {
      final m = e as Map;
      return (name: m['name'] as String, minutes: (m['minutes'] as num).toInt());
    }).toList();
    return ScreenTimeData(daily, top);
  }

  // ───────── Sessions focus ─────────

  Future<void> startFocus(int minutes, int breakMinutes, String label) async {
    await _channel.invokeMethod(
        'startFocus', {'minutes': minutes, 'breakMinutes': breakMinutes, 'label': label});
  }

  Future<void> cancelFocus() async {
    await _channel.invokeMethod('cancelFocus');
  }
}

class ScreenTimeData {
  ScreenTimeData(this.daily, this.top);

  /// Minutes d'utilisation par jour, du plus ancien (il y a 6 jours) à aujourd'hui.
  final List<int> daily;
  final List<({String name, int minutes})> top;
}