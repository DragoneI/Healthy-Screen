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
                // Fin d'une session focus : notification uniquement.
                if (phase == "focus_end") {
                    NotificationHelper.showFocusEnd(
                        ctx,
                        intent.getStringExtra("label") ?: "Focus",
                        intent.getIntExtra("break", 0)
                    )
                    return@Thread
                }

                // Fin d'une pause temporaire : on reprend et on réapplique la phase en cours.
                if (phase == "resume") {
                    PauseController.setPaused(ctx, 0L)
                    return@Thread
                }

                // Rappel différé (bouton "Rappel dans 15 min") : notification seulement.
                if (phase == "reminder") {
                    if (!AutomationState.isPaused(ctx)) NotificationHelper.showBedtime(ctx)
                    return@Thread
                }

                // 1) Reprogramme toujours la prochaine alarme avec les horaires configurés.
                val (h, m) = AutomationState.time(ctx, phase)
                AlarmScheduler.schedule(ctx, phase, h, m)

                // 2) Applique le fond, la luminosité et la notification si non en pause.
                if (!AutomationState.isPaused(ctx)) {
                    PhaseApplier.apply(ctx, phase)
                    NotificationHelper.showPhaseTransition(ctx, phase)
                }
            } finally {
                pending.finish()
            }
        }.start()
    }
}