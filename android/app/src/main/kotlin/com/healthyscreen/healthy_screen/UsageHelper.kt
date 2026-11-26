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

    private fun mergedDurationMs(intervals: List<Pair<Long, Long>>): Long {
        if (intervals.isEmpty()) return 0L
        val sorted = intervals.sortedBy { it.first }
        var total = 0L
        var curStart = sorted[0].first
        var curEnd = sorted[0].second

        for (i in 1 until sorted.size) {
            val (s, e) = sorted[i]
            if (e <= curStart) continue
            if (s <= curEnd) {
                if (e > curEnd) curEnd = e
            } else {
                total += (curEnd - curStart).coerceAtLeast(0L)
                curStart = s
                curEnd = e
            }
        }
        total += (curEnd - curStart).coerceAtLeast(0L)
        return total
    }

    @Suppress("DEPRECATION")
    fun weekly(ctx: Context): Map<String, Any> {
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()

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
        val excluded = setOf(
            ctx.packageName,
            home,
            "com.android.systemui",
            "android"
        )

        val dayIntervals = Array(7) { mutableListOf<Pair<Long, Long>>() }
        val appIntervalsToday = HashMap<String, MutableList<Pair<Long, Long>>>()

        fun recordInterval(pkg: String, rawStart: Long, rawEnd: Long, maxSpanMs: Long) {
            if (pkg in excluded) return
            val clampedStart = maxOf(rawStart, bounds[0], rawEnd - maxSpanMs)
            val clampedEnd = minOf(rawEnd, now)
            if (clampedEnd <= clampedStart) return

            for (d in 0..6) {
                val a = maxOf(clampedStart, bounds[d])
                val b = minOf(clampedEnd, bounds[d + 1])
                if (b > a) {
                    dayIntervals[d].add(a to b)
                    if (d == 6) {
                        appIntervalsToday.getOrPut(pkg) { mutableListOf() }.add(a to b)
                    }
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
                UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                    foreground[pkg] = e.timeStamp
                }
                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    val start = foreground.remove(pkg)
                    if (start != null) {
                        // Session fermée normalement : plafond généreux de 6 h
                        recordInterval(pkg, start, e.timeStamp, 6 * 3600_000L)
                    }
                }
            }
        }

        // Session encore ouverte à l'instant `now` : limitée aux 15 dernières min max
        for ((pkg, start) in foreground) {
            recordInterval(pkg, start, now, 15 * 60_000L)
        }

        val perDayMin = (0..6).map { d ->
            val ms = mergedDurationMs(dayIntervals[d]).coerceAtMost(24 * 3600_000L)
            (ms / 60_000L).toInt()
        }

        val top = appIntervalsToday.entries
            .map { (pkg, list) ->
                val mins = (mergedDurationMs(list).coerceAtMost(24 * 3600_000L) / 60_000L).toInt()
                label(ctx, pkg) to mins
            }
            .filter { it.second >= 1 }
            .sortedByDescending { it.second }
            .take(4)
            .map { mapOf("name" to it.first, "minutes" to it.second) }

        return mapOf(
            "daily" to perDayMin,
            "top" to top
        )
    }

    private fun label(ctx: Context, pkg: String): String = try {
        val pm = ctx.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) {
        pkg.substringAfterLast('.').replaceFirstChar { it.uppercase() }
    }
}