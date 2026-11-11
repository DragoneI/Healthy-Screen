package com.healthyscreen.healthy_screen

import android.content.Context

object ScheduleStore {
    private const val PREF_NAME = "HealthyScreenPrefs"

    fun saveConfig(ctx: Context, map: Map<String, Any>) {
        val prefs = ctx.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        prefs.edit().apply {
            map["sunriseHour"]?.let { putInt("sunriseHour", it as Int) }
            map["sunriseMinute"]?.let { putInt("sunriseMinute", it as Int) }
            map["sunsetHour"]?.let { putInt("sunsetHour", it as Int) }
            map["sunsetMinute"]?.let { putInt("sunsetMinute", it as Int) }
            map["nightHour"]?.let { putInt("nightHour", it as Int) }
            map["nightMinute"]?.let { putInt("nightMinute", it as Int) }
            map["nightBrightness"]?.let { putInt("nightBrightness", it as Int) }
            apply()
        }
    }
}