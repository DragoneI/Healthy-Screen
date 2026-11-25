package com.healthyscreen.healthy_screen

import android.content.Context
import java.util.Calendar

/**
 * Lit/écrit les mêmes valeurs que le code Dart (shared_preferences).
 * Les clés Flutter sont préfixées par "flutter." et les int sont stockés en Long.
 */
object AutomationState {
    private const val PREFS = "FlutterSharedPreferences"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** 0 = actif, -1 = pause manuelle, >0 = pause jusqu'à ce timestamp (ms). */
    fun isPaused(ctx: Context): Boolean {
        val until = prefs(ctx).getLong("flutter.pause_until", 0L)
        return until == -1L || until > System.currentTimeMillis()
    }

    fun setPausedUntil(ctx: Context, untilMs: Long) {
        prefs(ctx).edit().putLong("flutter.pause_until", untilMs).commit()
    }

    fun time(ctx: Context, phase: String): Pair<Int, Int> {
        val (dh, dm) = when (phase) {
            "sunrise" -> 7 to 0
            "afternoon" -> 14 to 0
            "sunset" -> 19 to 0
            else -> 22 to 0
        }
        val p = prefs(ctx)
        val h = p.getLong("flutter.${phase}_hour", dh.toLong()).toInt()
        val m = p.getLong("flutter.${phase}_minute", dm.toLong()).toInt()
        return h to m
    }

    /** Prochain passage (ms) de l'heure configurée pour cette phase. */
    fun nextOccurrenceMs(ctx: Context, phase: String): Long {
        val (h, m) = time(ctx, phase)
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, h)
            set(Calendar.MINUTE, m)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (cal.timeInMillis <= System.currentTimeMillis()) cal.add(Calendar.DAY_OF_YEAR, 1)
        return cal.timeInMillis
    }

    /** Luminosité de nuit choisie avec le curseur (10..255). */
    fun nightBrightness(ctx: Context): Int =
        prefs(ctx).getLong("flutter.night_brightness", 50L).toInt()

    /** Phase correspondant à l'heure actuelle : "sunrise", "afternoon", "sunset" ou "night". */
    fun currentPhase(ctx: Context): String {
        val cal = Calendar.getInstance()
        val now = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        val (sh, sm) = time(ctx, "sunrise")
        val (ah, am) = time(ctx, "afternoon")
        val (uh, um) = time(ctx, "sunset")
        val (nh, nm) = time(ctx, "night")

        val srMin = sh * 60 + sm
        val afMin = ah * 60 + am
        val ssMin = uh * 60 + um
        val ntMin = nh * 60 + nm

        return when {
            now >= ntMin || now < srMin -> "night"
            now >= ssMin -> "sunset"
            now >= afMin -> "afternoon"
            else -> "sunrise"
        }
    }
}