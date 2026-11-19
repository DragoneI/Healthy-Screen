package com.healthyscreen.healthy_screen

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File
import java.io.FileOutputStream
import kotlin.math.ceil
import kotlin.math.max

/**
 * Stocke les fonds choisis par l'utilisateur dans filesDir/wallpapers/<slot>_<timestamp>.jpg
 * Slots : "original" (fond habituel, remis à la pause), "sunrise", "sunset", "night".
 */
object WallpaperStore {
    private fun dir(ctx: Context): File = File(ctx.filesDir, "wallpapers").apply { mkdirs() }

    fun get(ctx: Context, slot: String): File? =
        dir(ctx).listFiles()?.firstOrNull { it.name.startsWith("${slot}_") }

    fun remove(ctx: Context, slot: String) {
        dir(ctx).listFiles()?.filter { it.name.startsWith("${slot}_") }?.forEach { it.delete() }
    }

    /** Copie l'image choisie, la recadre à la taille de l'écran et retourne son chemin. */
    fun importImage(ctx: Context, slot: String, srcPath: String): String? {
        val dm = ctx.resources.displayMetrics
        val w = dm.widthPixels
        val h = dm.heightPixels

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
        val scale = max(w.toFloat() / src.width, h.toFloat() / src.height)
        val sw = max(w, ceil(src.width * scale).toInt())
        val sh = max(h, ceil(src.height * scale).toInt())
        val scaled = Bitmap.createScaledBitmap(src, sw, sh, true)
        return Bitmap.createBitmap(scaled, (sw - w) / 2, (sh - h) / 2, w, h)
    }
}