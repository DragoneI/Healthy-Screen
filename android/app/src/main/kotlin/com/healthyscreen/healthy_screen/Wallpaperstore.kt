package com.healthyscreen.healthy_screen

import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import java.io.File
import java.io.FileOutputStream
import kotlin.math.ceil
import kotlin.math.max

/**
 * Stocke les fonds choisis par l'utilisateur dans filesDir/wallpapers/<slot>_<timestamp>.jpg
 * Slots : "original" (fond habituel, remis à la pause), "sunrise", "afternoon", "sunset", "night".
 */
object WallpaperStore {
    private fun dir(ctx: Context): File = File(ctx.filesDir, "wallpapers").apply { mkdirs() }

    fun get(ctx: Context, slot: String): File? =
        dir(ctx).listFiles()?.firstOrNull { it.name.startsWith("${slot}_") }

    fun remove(ctx: Context, slot: String) {
        dir(ctx).listFiles()?.filter { it.name.startsWith("${slot}_") }?.forEach { it.delete() }
    }

    /** Capture le fond d'écran actuel de l'appareil dans le slot "original" s'il n'existe pas déjà. */
    fun captureCurrentWallpaperIfMissing(ctx: Context): String? {
        get(ctx, "original")?.let { return it.absolutePath }
        return captureCurrentWallpaper(ctx)
    }

    /** Force la capture du fond d'écran actuel dans le slot "original". */
    fun captureCurrentWallpaper(ctx: Context): String? {
        return try {
            val wm = WallpaperManager.getInstance(ctx)
            val drawable = wm.drawable ?: return null
            val rawBitmap: Bitmap? = if (drawable is BitmapDrawable && drawable.bitmap != null) {
                drawable.bitmap
            } else {
                val w = drawable.intrinsicWidth.takeIf { it > 0 } ?: ctx.resources.displayMetrics.widthPixels
                val h = drawable.intrinsicHeight.takeIf { it > 0 } ?: ctx.resources.displayMetrics.heightPixels
                val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bmp)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                bmp
            }
            val src = rawBitmap ?: return null
            val dm = ctx.resources.displayMetrics
            val cover = coverCrop(src, dm.widthPixels, dm.heightPixels)
            remove(ctx, "original")
            val out = File(dir(ctx), "original_${System.currentTimeMillis()}.jpg")
            FileOutputStream(out).use { cover.compress(Bitmap.CompressFormat.JPEG, 92, it) }
            out.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    /** Copie l'image choisie, la recadre à la taille de l'écran et retourne son chemin. */
    fun importImage(ctx: Context, slot: String, srcPath: String): String? {
        val dm = ctx.resources.displayMetrics
        val w = dm.widthPixels.coerceAtLeast(1)
        val h = dm.heightPixels.coerceAtLeast(1)

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(srcPath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sample = 1
        while (bounds.outWidth / (sample * 2) >= w && bounds.outHeight / (sample * 2) >= h) {
            sample *= 2
        }
        val bmp = BitmapFactory.decodeFile(
            srcPath, BitmapFactory.Options().apply { inSampleSize = sample }
        ) ?: return null

        val cover = coverCrop(bmp, w, h)
        remove(ctx, slot)
        val out = File(dir(ctx), "${slot}_${System.currentTimeMillis()}.jpg")
        FileOutputStream(out).use { cover.compress(Bitmap.CompressFormat.JPEG, 92, it) }
        return out.absolutePath
    }

    /** Remplit tout l'écran sans déformer l'image (recadrage centré). */
    fun coverCrop(src: Bitmap, w: Int, h: Int): Bitmap {
        val targetW = w.coerceAtLeast(1)
        val targetH = h.coerceAtLeast(1)
        val srcW = src.width.coerceAtLeast(1)
        val srcH = src.height.coerceAtLeast(1)

        val scale = max(targetW.toFloat() / srcW, targetH.toFloat() / srcH)
        val sw = max(targetW, ceil(srcW * scale).toInt())
        val sh = max(targetH, ceil(srcH * scale).toInt())
        val scaled = Bitmap.createScaledBitmap(src, sw, sh, true)

        val cropW = targetW.coerceAtMost(scaled.width)
        val cropH = targetH.coerceAtMost(scaled.height)
        val dx = ((scaled.width - cropW) / 2).coerceAtLeast(0)
        val dy = ((scaled.height - cropH) / 2).coerceAtLeast(0)
        return Bitmap.createBitmap(scaled, dx, dy, cropW, cropH)
    }
}