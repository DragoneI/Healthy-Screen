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

// ── Dans NativeBridge ──
Future<bool> canAccessUsageStats() async {
  final result = await _channel.invokeMethod<bool>('canAccessUsageStats');
  return result ?? false;
}

Future<void> openUsageAccessSettings() async {
  await _channel.invokeMethod('openUsageAccessSettings');
}

Future<int> getScreenTimeToday() async {
  final result = await _channel.invokeMethod<int>('getScreenTimeToday');
  return result ?? 0;
}

}