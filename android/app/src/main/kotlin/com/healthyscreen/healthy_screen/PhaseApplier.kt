package com.healthyscreen.healthy_screen

import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.provider.Settings
import java.io.File

object PhaseApplier {
    private const val NATIVE_PREFS = "healthy_screen_native"
    private const val KEY_PREV_MODE = "prev_brightness_mode"
    private const val KEY_PREV_LEVEL = "prev_brightness_level"
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"

    fun apply(ctx: Context, phase: String) {
        setCustomOrResourceWallpaper(ctx, phase)

        if (phase == "night") {
            dimBrightness(ctx, AutomationState.nightBrightness(ctx))
        } else if (phase == "sunrise") {
            restoreBrightness(ctx)
        }
    }

    fun applyCurrent(ctx: Context) = apply(ctx, AutomationState.currentPhase(ctx))

    /**
     * CORRECTION DU BUG DE PAUSE : On ne supprime plus le fond d'écran avec wm.clear(),
     * ce qui évite de remettre le fond d'écran par défaut du téléphone. Le fond actuel est simplement figé.
     */
    fun release(ctx: Context) {
        restoreBrightness(ctx)
    }

    fun previewBrightness(ctx: Context, level: Int) = dimBrightness(ctx, level)

    private fun setCustomOrResourceWallpaper(ctx: Context, phase: String) {
        try {
            val sp = ctx.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val customPath = sp.getString("flutter.${phase}_wallpaper_path", null)
            val wm = WallpaperManager.getInstance(ctx)
            val m = ctx.resources.displayMetrics

            var bmp: Bitmap? = null
            if (!customPath.isNullOrEmpty()) {
                val file = File(customPath)
                if (file.exists()) {
                    bmp = BitmapFactory.decodeFile(file.absolutePath)
                }
            }

            if (bmp == null) {
                val resId = when (phase) {
                    "sunrise" -> R.drawable.wp_sunrise
                    "sunset" -> R.drawable.wp_sunset
                    else -> R.drawable.wp_night
                }
                bmp = BitmapFactory.decodeResource(ctx.resources, resId)
            }

            if (bmp != null) {
                val scaled = Bitmap.createScaledBitmap(bmp, m.widthPixels, m.heightPixels, true)
                wm.setBitmap(scaled, null, true, WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun backupBrightnessIfNeeded(ctx: Context) {
        val sp = ctx.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
        if (sp.contains(KEY_PREV_MODE)) return
        val cr = ctx.contentResolver
        val mode = Settings.System.getInt(
            cr, Settings.System.SCREEN_BRIGHTNESS_MODE,
            Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC
        )
        val level = Settings.System.getInt(cr, Settings.System.SCREEN_BRIGHTNESS, 128)
        sp.edit().putInt(KEY_PREV_MODE, mode).putInt(KEY_PREV_LEVEL, level).commit()
    }

    private fun dimBrightness(ctx: Context, level: Int) {
        if (!Settings.System.canWrite(ctx)) return
        val cr = ctx.contentResolver
        try {
            backupBrightnessIfNeeded(ctx)
            Settings.System.putInt(
                cr, Settings.System.SCREEN_BRIGHTNESS_MODE,
                Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL
            )
            Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS, level.coerceIn(1, 255))
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun restoreBrightness(ctx: Context) {
        if (!Settings.System.canWrite(ctx)) return
        val cr = ctx.contentResolver
        val sp = ctx.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
        try {
            if (sp.contains(KEY_PREV_MODE)) {
                val mode = sp.getInt(KEY_PREV_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC)
                val level = sp.getInt(KEY_PREV_LEVEL, 128)
                Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS, level.coerceIn(1, 255))
                Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS_MODE, mode)
                sp.edit().remove(KEY_PREV_MODE).remove(KEY_PREV_LEVEL).commit()
            } else {
                Settings.System.putInt(
                    cr, Settings.System.SCREEN_BRIGHTNESS_MODE,
                    Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}