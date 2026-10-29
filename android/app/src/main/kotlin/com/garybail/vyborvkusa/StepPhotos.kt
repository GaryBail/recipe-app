package com.garybail.vyborvkusa

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import java.io.File

/**
 * Фото шагов своих рецептов — только на телефоне: files/StepPhotos/<recipeId>/<шаг>.jpg.
 * Фото уменьшается до 1600 px по длинной стороне, чтобы не занимать память.
 */
object StepPhotos {
    private const val MAX_SIDE = 1600

    private fun dir(context: Context, recipeId: String) = File(context.filesDir, "StepPhotos/$recipeId")

    fun file(context: Context, recipeId: String, step: Int): File? =
        File(dir(context, recipeId), "$step.jpg").takeIf { it.exists() }

    fun save(context: Context, recipeId: String, step: Int, uri: Uri): Boolean = runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_SIDE) sample *= 2
        val bitmap = context.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: return false
        // Фото с камеры часто хранится «боком» с пометкой поворота в EXIF — поворачиваем сами.
        val rotation = context.contentResolver.openInputStream(uri)?.use {
            when (ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        } ?: 0f
        val scale = minOf(1f, MAX_SIDE.toFloat() / maxOf(bitmap.width, bitmap.height))
        val matrix = Matrix().apply { postScale(scale, scale); postRotate(rotation) }
        val scaled = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        val target = File(dir(context, recipeId).apply { mkdirs() }, "$step.jpg")
        target.outputStream().use { scaled.compress(Bitmap.CompressFormat.JPEG, 85, it) }
        true
    }.getOrDefault(false)

    fun delete(context: Context, recipeId: String, step: Int) {
        File(dir(context, recipeId), "$step.jpg").delete()
    }

    fun deleteAll(context: Context, recipeId: String) {
        dir(context, recipeId).deleteRecursively()
    }
}
