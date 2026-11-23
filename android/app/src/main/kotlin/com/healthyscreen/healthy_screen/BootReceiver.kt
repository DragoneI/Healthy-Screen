package com.healthyscreen.healthy_screen

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val phases = listOf("sunrise", "sunset", "night")
        for (phase in phases) {
            val (hour, minute) = AutomationState.time(ctx, phase)
            AlarmScheduler.schedule(ctx, phase, hour, minute)
        }
    }
}