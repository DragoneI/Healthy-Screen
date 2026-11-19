package com.healthyscreen.healthy_screen

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

object FocusController {
    private const val REQUEST_CODE = 3003

    private fun pendingIntent(ctx: Context, label: String, breakMin: Int): PendingIntent =
        PendingIntent.getBroadcast(
            ctx,
            REQUEST_CODE,
            Intent(ctx, PhaseReceiver::class.java)
                .putExtra("phase", "focus_end")
                .putExtra("label", label)
                .putExtra("break", breakMin),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

    fun start(ctx: Context, minutes: Int, breakMin: Int, label: String) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        val at = System.currentTimeMillis() + minutes * 60_000L
        val pi = pendingIntent(ctx, label, breakMin)
        if (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        } else {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }

    fun cancel(ctx: Context) {
        ctx.getSystemService(AlarmManager::class.java).cancel(pendingIntent(ctx, "", 0))
    }
}