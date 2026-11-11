package com.healthyscreen.healthy_screen

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "circadian/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canWriteSettings" -> {
                    result.success(Settings.System.canWrite(context))
                }
                "openWriteSettings" -> {
                    val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
                    startActivity(intent)
                    result.success(null)
                }
                "canScheduleExact" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        result.success(alarmManager.canScheduleExactAlarms())
                    } else {
                        result.success(true)
                    }
                }
                "openExactAlarmSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                        startActivity(intent)
                    }
                    result.success(null)
                }
                "saveSchedule" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args != null) {
                        @Suppress("UNCHECKED_CAST")
                        val map = args as Map<String, Any>
                        ScheduleStore.saveConfig(context, map)

                        // Programmer les 3 alarmes
                        val sHour = map["sunriseHour"] as? Int ?: 7
                        val sMin = map["sunriseMinute"] as? Int ?: 0
                        AlarmScheduler.schedule(context, "sunrise", sHour, sMin)

                        val suHour = map["sunsetHour"] as? Int ?: 19
                        val suMin = map["sunsetMinute"] as? Int ?: 0
                        AlarmScheduler.schedule(context, "sunset", suHour, suMin)

                        val nHour = map["nightHour"] as? Int ?: 22
                        val nMin = map["nightMinute"] as? Int ?: 0
                        AlarmScheduler.schedule(context, "night", nHour, nMin)
                    }
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}