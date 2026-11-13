package com.healthyscreen.healthy_screen

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PhaseReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val phase = intent.getStringExtra("phase") ?: return
        val pending = goAsync()

        Thread {
            try {
                // Rappel différé (bouton "Rappel dans 15 min") : notification seulement.
                if (phase == "reminder") {
                    if (!AutomationState.isPaused(ctx)) NotificationHelper.showBedtime(ctx)
                    return@Thread
                }

                // 1) On reprogramme TOUJOURS la prochaine alarme, avec les horaires de
                //    l'utilisateur (plus de 7h/19h/22h en dur), même en pause : la chaîne
                //    d'alarmes ne doit jamais se casser.
                val (h, m) = AutomationState.time(ctx, phase)
                AlarmScheduler.schedule(ctx, phase, h, m)

                // 2) On n'applique le fond d'écran / la luminosité que si non en pause.
                if (!AutomationState.isPaused(ctx)) {
                    PhaseApplier.apply(ctx, phase)
                    if (phase == "night") NotificationHelper.showBedtime(ctx)
                }
            } finally {
                pending.finish()
            }
        }.start()
    }
}