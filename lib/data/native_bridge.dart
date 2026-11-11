
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
}

