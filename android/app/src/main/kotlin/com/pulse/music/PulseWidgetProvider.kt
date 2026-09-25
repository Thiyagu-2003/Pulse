package com.pulse.music

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
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
import android.widget.RemoteViews

/**
 * Now-playing home-screen widget.
 *
 * The app writes the current track into [PREFS] (see MainActivity) and asks
 * for a redraw; the buttons go through [PulseWidgetActionReceiver], which
 * turns them into media-button events for audio_service — the same path as
 * headset keys and the notification.
 */
class PulseWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = build(context)
        ids.forEach { manager.updateAppWidget(it, views) }
    }

    companion object {
        const val PREFS = "pulse_widget"

        /** Redraw every placed widget from the saved state. */
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, PulseWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val views = build(context)
            ids.forEach { manager.updateAppWidget(it, views) }
        }

        private fun build(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.pulse_widget)

            views.setTextViewText(R.id.widget_title, prefs.getString("title", null) ?: "Pulse")
            views.setTextViewText(
                R.id.widget_artist,
                prefs.getString("artist", null) ?: context.getString(R.string.widget_idle),
            )
            views.setImageViewResource(
                R.id.widget_play,
                if (prefs.getBoolean("playing", false)) R.drawable.ic_widget_pause
                else R.drawable.ic_widget_play,
            )

            val art = prefs.getString("artPath", null)?.let(::loadArt)
            if (art != null) {
                views.setImageViewBitmap(R.id.widget_art, art)
            } else {
                views.setImageViewResource(R.id.widget_art, R.mipmap.launcher_icon)
            }

            views.setOnClickPendingIntent(R.id.widget_root, openApp(context))
            if (MainActivity.engineReady) {
                views.setOnClickPendingIntent(R.id.widget_prev, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
                views.setOnClickPendingIntent(R.id.widget_play, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
                views.setOnClickPendingIntent(R.id.widget_next, mediaButton(context, KeyEvent.KEYCODE_MEDIA_NEXT))
            } else {
                // The app isn't running, so there's nothing to control. A
                // direct activity intent is the one launch Android always
                // allows from a widget (a receiver starting it is blocked).
                val open = openApp(context)
                views.setOnClickPendingIntent(R.id.widget_prev, open)
                views.setOnClickPendingIntent(R.id.widget_play, open)
                views.setOnClickPendingIntent(R.id.widget_next, open)
            }
            return views
        }

        /**
         * Downsampled and rounded. A full-size YouTube thumbnail is several MB
         * decoded, and widget updates over the binder size limit are dropped.
         */
        private fun loadArt(path: String): Bitmap? = try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= 192 && bounds.outHeight / (sample * 2) >= 192) {
                sample *= 2
            }
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
                ?.let(::roundedSquare)
        } catch (e: Exception) {
            null
        }

        private fun roundedSquare(source: Bitmap): Bitmap {
            val size = minOf(source.width, source.height)
            val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(out)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            val rect = RectF(0f, 0f, size.toFloat(), size.toFloat())
            canvas.drawRoundRect(rect, size * 0.16f, size * 0.16f, paint)
            paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            // Centre-crop: YouTube art is 16:9.
            val left = (source.width - size) / 2f
            val top = (source.height - size) / 2f
            canvas.drawBitmap(source, -left, -top, paint)
            return out
        }

        private fun openApp(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(
                context, 0, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        private fun mediaButton(context: Context, keyCode: Int): PendingIntent {
            val intent = Intent(context, PulseWidgetActionReceiver::class.java)
                .putExtra(PulseWidgetActionReceiver.EXTRA_KEY_CODE, keyCode)
            // Request code per key, or the three buttons would share one intent.
            return PendingIntent.getBroadcast(
                context, keyCode, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }
    }
}
