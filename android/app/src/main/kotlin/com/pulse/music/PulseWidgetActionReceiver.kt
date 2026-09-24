package com.pulse.music

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.KeyEvent
import com.ryanheise.audioservice.MediaButtonReceiver

/**
 * The widget's prev / play-pause / next buttons.
 *
 * Sent straight to audio_service's receiver, a press made while the app's
 * process was dead reached a service whose Dart side wasn't set up yet and
 * was silently dropped — the widget looked alive and did nothing. So: with
 * the app running, pass the press on to audio_service; without it,
 * there's nothing to control — show the widget as idle and open the app.
 */
class PulseWidgetActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val keyCode = intent.getIntExtra(EXTRA_KEY_CODE, 0)
        if (keyCode == 0) return

        if (MainActivity.engineReady) {
            val mediaButton = Intent(Intent.ACTION_MEDIA_BUTTON)
                .setComponent(ComponentName(context, MediaButtonReceiver::class.java))
                .putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            // An explicit broadcast to the real receiver: calling its
            // onReceive directly would crash in goAsync(). Same app, so still
            // inside the window a widget tap grants to start the playback
            // (foreground) service.
            context.sendBroadcast(mediaButton)
            return
        }

        context.getSharedPreferences(PulseWidgetProvider.PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean("playing", false).apply()
        PulseWidgetProvider.refresh(context)
        try {
            context.startActivity(
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (e: Exception) {
            // Background activity starts can be refused; tapping the widget
            // itself still opens the app.
        }
    }

    companion object {
        const val EXTRA_KEY_CODE = "keyCode"
    }
}
