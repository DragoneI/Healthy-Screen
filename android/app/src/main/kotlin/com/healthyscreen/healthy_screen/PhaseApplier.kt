package com.healthyscreen.healthy_screen

import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import java.util.Calendar

object PhaseApplier {
    private const val NATIVE_PREFS = "healthy_screen_native"
    private const val KEY_PREV_MODE = "prev_brightness_mode"
    private const val KEY_PREV_LEVEL = "prev_brightness_level"

    private const val MORNING_BRIGHTNESS = 135
    private const val AFTERNOON_BRIGHTNESS = 220

    private val mainHandler = Handler(Looper.getMainLooper())
    private var duskRunnable: Runnable? = null

    fun apply(ctx: Context, phase: String) {
        val appCtx = ctx.applicationContext
        cancelDuskRamp()
        setWallpaper(appCtx, phase)

        val nightLevel = AutomationState.nightBrightness(appCtx).coerceIn(10, 255)

        when (phase) {
            "night" -> setManualBrightness(appCtx, nightLevel)
            "sunrise" -> setManualBrightness(appCtx, MORNING_BRIGHTNESS)
            "afternoon", "day" -> setManualBrightness(appCtx, AFTERNOON_BRIGHTNESS)
            "sunset" -> startDuskRamp(appCtx, AFTERNOON_BRIGHTNESS, nightLevel)
        }
    }

    private fun startDuskRamp(ctx: Context, startLevel: Int, endLevel: Int) {
        val (sh, sm) = AutomationState.time(ctx, "sunset")
        val (nh, nm) = AutomationState.time(ctx, "night")

        val nowCal = Calendar.getInstance()
        val endCal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, nh)
            set(Calendar.MINUTE, nm)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= nowCal.timeInMillis) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }

        val startCal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, sh)
            set(Calendar.MINUTE, sm)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis > endCal.timeInMillis) {
                add(Calendar.DAY_OF_YEAR, -1)
            }
        }

        val totalMs = (endCal.timeInMillis - startCal.timeInMillis).coerceAtLeast(60_000L)
        val stepIntervalMs = 15_000L // mise à jour progressive toutes les 15 s

        fun step() {
            if (AutomationState.isPaused(ctx)) return
            val nowMs = System.currentTimeMillis()
            val fraction = ((nowMs - startCal.timeInMillis).toFloat() / totalMs.toFloat())
                .coerceIn(0f, 1f)
            val interpolated = (startLevel + (endLevel - startLevel) * fraction)
                .toInt()
                .coerceIn(1, 255)
            setManualBrightness(ctx, interpolated)

            if (fraction < 1f) {
                val r = Runnable { step() }
                duskRunnable = r
                mainHandler.postDelayed(r, stepIntervalMs)
            }
        }

        step()
    }

    private fun cancelDuskRamp() {
        duskRunnable?.let { mainHandler.removeCallbacks(it) }
        duskRunnable = null
    }

    /** Réapplique la phase correspondant à l'heure actuelle (reprise après pause). */
    fun applyCurrent(ctx: Context) = apply(ctx, AutomationState.currentPhase(ctx))

    /**
     * Pause : remet le fond d'écran habituel (ou efface les fonds appliqués)
     * et remet la luminosité d'avant.
     */
    fun release(ctx: Context) {
        cancelDuskRamp()
        try {
            val original = WallpaperStore.get(ctx, "original")
                ?.let { BitmapFactory.decodeFile(it.absolutePath) }
            if (original != null) {
                setBitmapEverywhere(ctx, original)
            } else {
                val wm = WallpaperManager.getInstance(ctx)
                if (Build.VERSION.SDK_INT >= 24) {
                    wm.clear(WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK)
                } else {
                    wm.clear()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        restoreBrightness(ctx)
    }

    /** Aperçu en direct depuis le curseur de l'app. */
    fun previewBrightness(ctx: Context, level: Int) = setManualBrightness(ctx, level)

    private fun setWallpaper(ctx: Context, phase: String) {
        try {
            val m = ctx.resources.displayMetrics
            val file = WallpaperStore.get(ctx, phase)
                ?: when (phase) {
                    "afternoon", "day" -> WallpaperStore.get(ctx, "sunrise")
                    else -> null
                }
                ?: return
            val bmp = BitmapFactory.decodeFile(file.absolutePath) ?: return
            setBitmapEverywhere(ctx, WallpaperStore.coverCrop(bmp, m.widthPixels, m.heightPixels))
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun setBitmapEverywhere(ctx: Context, bmp: Bitmap) {
        WallpaperManager.getInstance(ctx)
            .setBitmap(bmp, null, true, WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK)
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

    private fun setManualBrightness(ctx: Context, level: Int) {
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

    /** Remet le mode et le niveau d'avant ; sinon, retour en luminosité automatique. */
    fun restoreBrightness(ctx: Context) {
        cancelDuskRamp()
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