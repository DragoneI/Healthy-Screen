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
                // 1. Appliquer le fond d'écran et la luminosité
                PhaseApplier.apply(ctx, phase)

                // 2. Ré-armer l'alarme pour le lendemain à la même heure
                // (Par défaut : sunrise à 7h00, sunset à 19h00, night à 22h00)
                when (phase) {
                    "sunrise" -> AlarmScheduler.schedule(ctx, "sunrise", 7, 0)
                    "sunset"  -> AlarmScheduler.schedule(ctx, "sunset", 19, 0)
                    "night"   -> AlarmScheduler.schedule(ctx, "night", 22, 0)
                }
            } finally {
                pending.finish()
            }
        }.start()
    }
}