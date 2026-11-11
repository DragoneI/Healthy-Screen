package com.healthyscreen.healthy_screen

import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.provider.Settings

object PhaseApplier {
    fun apply(ctx: Context, phase: String) {
        // Choix de l'image selon la phase
        val resId = when (phase) {
            "sunrise" -> R.drawable.wp_sunrise
            "sunset"  -> R.drawable.wp_sunset
            else      -> R.drawable.wp_night
        }

        setWallpaper(ctx, resId)

        // Gestion de la luminosité et notification pour la nuit
        if (phase == "night") {
            dimBrightness(ctx, 50) // Luminosité basse la nuit (ex: 50 sur 255)
        } else if (phase == "sunrise") {
            restoreBrightness(ctx)
        }
    }

    private fun setWallpaper(ctx: Context, resId: Int) {
        try {
            val wm = WallpaperManager.getInstance(ctx)
            val m = ctx.resources.displayMetrics
            val bmp = BitmapFactory.decodeResource(ctx.resources, resId)
            if (bmp != null) {
                val scaled = Bitmap.createScaledBitmap(bmp, m.widthPixels, m.heightPixels, true)
                wm.setBitmap(scaled, null, true, WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun dimBrightness(ctx: Context, level: Int) {
        if (!Settings.System.canWrite(ctx)) return
        val cr = ctx.contentResolver
        try {
            // Passe en mode manuel pour pouvoir modifier la luminosité
            Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL)
            Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS, level.coerceIn(0, 255))
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun restoreBrightness(ctx: Context) {
        if (!Settings.System.canWrite(ctx)) return
        val cr = ctx.contentResolver
        try {
            // Remet la luminosité en mode automatique (adaptatif) au réveil
            Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}