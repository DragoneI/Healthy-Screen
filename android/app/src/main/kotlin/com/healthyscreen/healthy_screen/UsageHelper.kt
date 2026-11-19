package com.healthyscreen.healthy_screen

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process
import java.util.Calendar

object UsageHelper {

    @Suppress("DEPRECATION")
    fun hasAccess(ctx: Context): Boolean {
        val ops = ctx.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= 29) {
            ops.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName
            )
        } else {
            ops.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * Retourne {"daily": [min x7, du plus ancien à aujourd'hui], "top": [{name, minutes} x4]}.
     * Le temps compté est le temps passé au premier plan par les applications.
     */
    @Suppress("DEPRECATION")
    fun weekly(ctx: Context): Map<String, Any> {
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()

        // bornes de minuit des 7 jours (+ demain)
        val bounds = LongArray(8)
        val c = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            add(Calendar.DAY_OF_YEAR, -6)
        }
        for (i in 0..7) {
            bounds[i] = c.timeInMillis
            c.add(Calendar.DAY_OF_YEAR, 1)
        }

        val home = ctx.packageManager
            .resolveActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), 0)
            ?.activityInfo?.packageName
        val excluded = setOf(ctx.packageName, home, "com.android.systemui")

        val perDay = LongArray(7)
        val perAppToday = HashMap<String, Long>()

        fun add(pkg: String, start: Long, end: Long) {
            if (pkg in excluded) return
            val s = maxOf(start, bounds[0])
            val t = minOf(end, now)
            if (t <= s) return
            for (d in 0..6) {
                val a = maxOf(s, bounds[d])
                val b = minOf(t, bounds[d + 1])
                if (b > a) {
                    perDay[d] += b - a
                    if (d == 6) perAppToday[pkg] = (perAppToday[pkg] ?: 0L) + (b - a)
                }
            }
        }

        val events = usm.queryEvents(bounds[0], now)
        val e = UsageEvents.Event()
        val foreground = HashMap<String, Long>()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            val pkg = e.packageName ?: continue
            when (e.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> foreground[pkg] = e.timeStamp
                UsageEvents.Event.MOVE_TO_BACKGROUND ->
                    foreground.remove(pkg)?.let { add(pkg, it, e.timeStamp) }
            }
        }
        foreground.forEach { (pkg, start) -> add(pkg, start, now) }

        val top = perAppToday.entries
            .sortedByDescending { it.value }
            .map { label(ctx, it.key) to (it.value / 60000).toInt() }
            .filter { it.second >= 1 }
            .take(4)
            .map { mapOf("name" to it.first, "minutes" to it.second) }

        return mapOf(
            "daily" to perDay.map { (it / 60000).toInt() },
            "top" to top
        )
    }

    private fun label(ctx: Context, pkg: String): String = try {
        val pm = ctx.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) {
        pkg.substringAfterLast('.').replaceFirstChar { it.uppercase() }
    }
}