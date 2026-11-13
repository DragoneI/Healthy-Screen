package com.healthyscreen.healthy_screen

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object NotificationHelper {
    const val CHANNEL_ID = "bedtime_reminder"
    const val NOTIF_ID = 2001

    private const val FLAGS = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

    fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Rappel du coucher",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Un rappel doux pour ralentir avant de dormir"
            setShowBadge(false)
        }
        ctx.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    fun showBedtime(ctx: Context) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return

        ensureChannel(ctx)

        val openApp = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let {
            PendingIntent.getActivity(ctx, 0, it, FLAGS)
        }

        val snooze = PendingIntent.getBroadcast(
            ctx, 1,
            Intent(ctx, NotificationActionReceiver::class.java)
                .setAction(NotificationActionReceiver.ACTION_SNOOZE),
            FLAGS
        )
        val pause = PendingIntent.getBroadcast(
            ctx, 2,
            Intent(ctx, NotificationActionReceiver::class.java)
                .setAction(NotificationActionReceiver.ACTION_PAUSE_UNTIL_MORNING),
            FLAGS
        )

        val notification = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(ctx.applicationInfo.icon) // idéal : remplacer par une icône monochrome ic_stat_moon
            .setContentTitle("Il est temps de ralentir 🌙")
            .setContentText("Écran apaisé. Posez le téléphone pour mieux dormir.")
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "Votre écran est passé en mode nuit. Poser le téléphone 30 minutes " +
                        "avant de dormir aide votre rythme biologique."
                )
            )
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setColor(0xFF2DD4BF.toInt())
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .setContentIntent(openApp)
            .addAction(0, "Rappel dans 15 min", snooze)
            .addAction(0, "Pause jusqu'à demain", pause)
            .build()

        NotificationManagerCompat.from(ctx).notify(NOTIF_ID, notification)
    }
}