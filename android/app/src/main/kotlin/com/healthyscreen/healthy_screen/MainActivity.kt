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

                // ── Nouveau : aperçu en direct de la luminosité (curseur) ──
                "previewBrightness" -> {
                    val level = call.argument<Number>("level")?.toInt() ?: 50
                    PhaseApplier.previewBrightness(applicationContext, level)
                    result.success(null)
                }
                // ── Nouveau : remet la luminosité d'avant l'aperçu ──
                "restoreBrightness" -> {
                    PhaseApplier.restoreBrightness(applicationContext)
                    result.success(null)
                }
                // ── Nouveau : pause réelle (0 = reprise, -1 = manuelle, >0 = jusqu'à ce timestamp) ──
                "setPaused" -> {
                    val until = call.argument<Number>("untilMs")?.toLong() ?: 0L
                    Thread { PauseController.setPaused(applicationContext, until) }.start()
                    result.success(null)
                }
                // ── Fonds d'écran personnalisés ──
                "getWallpapers" -> {
                    val slots = listOf("original", "sunrise", "sunset", "night")
                    result.success(slots.associateWith { WallpaperStore.get(applicationContext, it)?.absolutePath })
                }
                "importWallpaper" -> {
                    val slot = call.argument<String>("slot")
                    val path = call.argument<String>("path")
                    if (slot == null || path == null) {
                        result.error("ARGS", "slot ou path manquant", null)
                    } else {
                        Thread {
                            val out = try {
                                WallpaperStore.importImage(applicationContext, slot, path)
                            } catch (e: Exception) {
                                null
                            }
                            runOnUiThread { result.success(out) }
                        }.start()
                    }
                }
                "removeWallpaper" -> {
                    call.argument<String>("slot")?.let { WallpaperStore.remove(applicationContext, it) }
                    result.success(null)
                }
                "applyPhaseNow" -> {
                    val phase = call.argument<String>("phase") ?: "night"
                    Thread { PhaseApplier.apply(applicationContext, phase) }.start()
                    result.success(null)
                }

                // ── Temps d'écran ──
                "hasUsageAccess" -> {
                    result.success(UsageHelper.hasAccess(applicationContext))
                }
                "openUsageAccess" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(null)
                }
                "getScreenTime" -> {
                    Thread {
                        val data = try {
                            UsageHelper.weekly(applicationContext)
                        } catch (e: Exception) {
                            null
                        }
                        runOnUiThread { result.success(data) }
                    }.start()
                }

                // ── Sessions focus ──
                "startFocus" -> {
                    val minutes = call.argument<Number>("minutes")?.toInt() ?: 25
                    val breakMin = call.argument<Number>("breakMinutes")?.toInt() ?: 0
                    val label = call.argument<String>("label") ?: "Focus"
                    FocusController.start(applicationContext, minutes, breakMin, label)
                    result.success(null)
                }
                "cancelFocus" -> {
                    FocusController.cancel(applicationContext)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}