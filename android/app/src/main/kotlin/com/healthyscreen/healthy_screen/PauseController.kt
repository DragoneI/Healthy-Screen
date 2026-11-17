package com.healthyscreen.healthy_screen

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

object PauseController {
    private const val RESUME_REQUEST = 3002

    private fun resumeIntent(ctx: Context): PendingIntent =
        PendingIntent.getBroadcast(
            ctx,
            RESUME_REQUEST,
            Intent(ctx, PhaseReceiver::class.java).putExtra("phase", "resume"),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

    /**
     * untilMs : 0 = reprendre, -1 = pause jusqu'à reprise manuelle,
     * >0 = pause jusqu'à ce timestamp (reprise automatique par alarme).
     * À appeler hors du thread principal (modifie le fond d'écran).
     */
    fun setPaused(ctx: Context, untilMs: Long) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        am.cancel(resumeIntent(ctx))
        AutomationState.setPausedUntil(ctx, untilMs)

        if (untilMs == 0L) {
            PhaseApplier.applyCurrent(ctx)
            return
        }

        PhaseApplier.release(ctx)

        if (untilMs > 0) {
            val pi = resumeIntent(ctx)
            if (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, untilMs, pi)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, untilMs, pi)
            }
        }
    }
}