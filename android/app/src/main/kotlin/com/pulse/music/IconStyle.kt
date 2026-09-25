package com.pulse.music

import android.content.Context

/**
 * The light/dark app icon choice (Settings > App icon), for everything
 * Pulse draws itself: the widget placeholder, notification large icons, the
 * recent-apps entry. Stored natively so the widget and the download service
 * can read it without the Flutter engine.
 *
 * What Android does NOT let an app change at runtime: the status-bar small
 * icon (always a one-colour silhouette) and the icon in the notification
 * header, App info and the system settings list (fixed at install).
 */
object IconStyle {
    private const val KEY = "darkIcon"

    fun isDark(context: Context): Boolean =
        context.getSharedPreferences(PulseWidgetProvider.PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY, false)

    fun setDark(context: Context, dark: Boolean) {
        context.getSharedPreferences(PulseWidgetProvider.PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY, dark).apply()
    }

    /** Full-colour square icon (bitmap), for large icons and placeholders. */
    fun imageRes(context: Context): Int =
        if (isDark(context)) R.drawable.app_icon_dark else R.drawable.app_icon_light
}
