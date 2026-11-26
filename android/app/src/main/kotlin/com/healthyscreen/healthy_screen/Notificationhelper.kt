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

    private const val FOCUS_CHANNEL_ID = "focus_sessions"
    private const val FOCUS_NOTIF_ID = 2002

    fun showFocusEnd(ctx: Context, label: String, breakMin: Int) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return

        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(
                FOCUS_CHANNEL_ID,
                "Sessions focus",
                NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "Fin de vos sessions anti-procrastination" }
            ctx.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }

        val openApp = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let {
            PendingIntent.getActivity(ctx, 0, it, FLAGS)
        }
        val text = if (breakMin > 0) {
            "Prenez $breakMin minutes de pause : levez-vous, buvez de l'eau, regardez au loin."
        } else {
            "Beau moment loin de l'écran. Reprenez quand vous êtes prêt."
        }

        val notification = NotificationCompat.Builder(ctx, FOCUS_CHANNEL_ID)
            .setSmallIcon(ctx.applicationInfo.icon)
            .setContentTitle("Session $label terminée 🎉")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setColor(0xFF2DD4BF.toInt())
            .setAutoCancel(true)
            .setContentIntent(openApp)
            .build()

        NotificationManagerCompat.from(ctx).notify(FOCUS_NOTIF_ID, notification)
    }
    fun showPhaseTransition(ctx: Context, phase: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return

        ensureChannel(ctx)

        val (title, body) = when (phase) {
            "sunrise" -> "Bonjour ☀️" to
                "Douce lumière du matin. Prenez un instant pour respirer et démarrer la journée à votre rythme."
            "afternoon", "day" -> "Bon après-midi 🌤️" to
                "La journée avance : pensez à boire un peu d'eau et à reposer vos yeux quelques secondes."
            "sunset" -> "Le jour décline 🌅" to
                "Le crépuscule s'installe en douceur pour vous aider à lever le pied."
            else -> "Il est temps de ralentir 🌙" to
                "Écran apaisé. Posez le téléphone pour préparer une nuit reposante."
        }

        val openApp = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let {
            PendingIntent.getActivity(ctx, phase.hashCode(), it, FLAGS)
        }

        val notification = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(ctx.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setColor(0xFF2DD4BF.toInt())
            .setAutoCancel(true)
            .setContentIntent(openApp)
            .build()

        NotificationManagerCompat.from(ctx).notify(NOTIF_ID + phase.hashCode().and(0xFF), notification)
    }
}