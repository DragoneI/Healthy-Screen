package com.healthyscreen.healthy_screen

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationManagerCompat

class NotificationActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_SNOOZE = "com.healthyscreen.healthy_screen.SNOOZE"
        const val ACTION_PAUSE_UNTIL_MORNING = "com.healthyscreen.healthy_screen.PAUSE_UNTIL_MORNING"
        private const val SNOOZE_REQUEST_CODE = 3001
        private const val SNOOZE_DELAY_MS = 15 * 60_000L
    }

    override fun onReceive(ctx: Context, intent: Intent) {
        when (intent.action) {
            ACTION_SNOOZE -> scheduleReminder(ctx)
            ACTION_PAUSE_UNTIL_MORNING ->
                AutomationState.setPausedUntil(ctx, AutomationState.nextOccurrenceMs(ctx, "sunrise"))
        }
        NotificationManagerCompat.from(ctx).cancel(NotificationHelper.NOTIF_ID)
    }

    private fun scheduleReminder(ctx: Context) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        val pi = PendingIntent.getBroadcast(
            ctx,
            SNOOZE_REQUEST_CODE,
            Intent(ctx, PhaseReceiver::class.java).putExtra("phase", "reminder"),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val at = System.currentTimeMillis() + SNOOZE_DELAY_MS
        if (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        } else {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }
}