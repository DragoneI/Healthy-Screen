package com.healthyscreen.healthy_screen

import android.content.Context

object ScheduleStore {
    private const val PREF_NAME = "HealthyScreenPrefs"

    fun saveConfig(ctx: Context, map: Map<String, Any>) {
        val prefs = ctx.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        prefs.edit().apply {
            (map["sunriseHour"] as? Number)?.let { putInt("sunriseHour", it.toInt()) }
            (map["sunriseMinute"] as? Number)?.let { putInt("sunriseMinute", it.toInt()) }
            (map["afternoonHour"] as? Number)?.let { putInt("afternoonHour", it.toInt()) }
            (map["afternoonMinute"] as? Number)?.let { putInt("afternoonMinute", it.toInt()) }
            (map["sunsetHour"] as? Number)?.let { putInt("sunsetHour", it.toInt()) }
            (map["sunsetMinute"] as? Number)?.let { putInt("sunsetMinute", it.toInt()) }
            (map["nightHour"] as? Number)?.let { putInt("nightHour", it.toInt()) }
            (map["nightMinute"] as? Number)?.let { putInt("nightMinute", it.toInt()) }
            (map["nightBrightness"] as? Number)?.let { putInt("nightBrightness", it.toInt()) }
            apply()
        }
    }
}