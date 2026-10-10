package com.pulse.music

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.view.KeyEvent

/**
 * Shared utilities, art transformations, and dispatch helpers for all Pulse
 * home-screen widgets.
 */
object PulseWidgetHelper {
    const val PREFS = "pulse_widget"

    /**
     * Redraws all placed widgets across all widget types with the latest state.
     */
    fun refreshAll(context: Context) {
        PulseWidgetProvider.refresh(context)
        PulseCompactWidgetProvider.refresh(context)
        PulseSquareWidgetProvider.refresh(context)
        PulseCardWidgetProvider.refresh(context)
    }

    /**
     * Decodes and downsamples artwork to avoid exceeding binder transaction
     * size limits (which would cause Android to drop widget updates).
     */
    fun loadArt(path: String, targetSize: Int = 192, cornerRatio: Float = 0.16f): Bitmap? = try {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= targetSize && bounds.outHeight / (sample * 2) >= targetSize) {
            sample *= 2
        }
        BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
            ?.let { roundedSquare(it, cornerRatio) }
    } catch (e: Exception) {
        null
    }

    /**
     * Crops [source] to a centered square and rounds its corners.
     */
    fun roundedSquare(source: Bitmap, cornerRatio: Float = 0.16f): Bitmap {
        val size = minOf(source.width, source.height)
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val rect = RectF(0f, 0f, size.toFloat(), size.toFloat())
        canvas.drawRoundRect(rect, size * cornerRatio, size * cornerRatio, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        val left = (source.width - size) / 2f
        val top = (source.height - size) / 2f
        canvas.drawBitmap(source, -left, -top, paint)
        return out
    }

    /**
     * Returns an intent to launch MainActivity. Always permitted by Android
     * from a widget touch.
     */
    fun openApp(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    /**
     * Builds an explicit broadcast pending intent to trigger media controls via
     * [PulseWidgetActionReceiver].
     */
    fun mediaButton(context: Context, keyCode: Int): PendingIntent {
        val intent = Intent(context, PulseWidgetActionReceiver::class.java)
            .putExtra(PulseWidgetActionReceiver.EXTRA_KEY_CODE, keyCode)
        return PendingIntent.getBroadcast(
            context, keyCode, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
