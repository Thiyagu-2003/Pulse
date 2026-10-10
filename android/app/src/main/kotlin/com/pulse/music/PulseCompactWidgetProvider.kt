package com.pulse.music

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.view.KeyEvent
import android.widget.RemoteViews

/**
 * Compact / Mini now-playing home-screen widget (2x1).
 *
 * Space-saving design with artwork thumbnail, song title, and quick
 * Play/Pause control.
 */
class PulseCompactWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = build(context)
        ids.forEach { manager.updateAppWidget(it, views) }
    }

    companion object {
        const val PREFS = PulseWidgetHelper.PREFS

        /** Redraw every placed instance of this widget. */
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, PulseCompactWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val views = build(context)
            ids.forEach { manager.updateAppWidget(it, views) }
        }

        private fun build(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.pulse_widget_compact)

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

            val art = prefs.getString("artPath", null)?.let { PulseWidgetHelper.loadArt(it, targetSize = 144) }
            if (art != null) {
                views.setImageViewBitmap(R.id.widget_art, art)
            } else {
                views.setImageViewResource(R.id.widget_art, IconStyle.imageRes(context))
            }

            views.setOnClickPendingIntent(R.id.widget_root, PulseWidgetHelper.openApp(context))
            if (MainActivity.engineReady) {
                views.setOnClickPendingIntent(R.id.widget_play, PulseWidgetHelper.mediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
            } else {
                views.setOnClickPendingIntent(R.id.widget_play, PulseWidgetHelper.openApp(context))
            }
            return views
        }
    }
}
