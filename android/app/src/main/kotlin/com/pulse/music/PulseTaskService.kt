package com.pulse.music

import android.app.NotificationManager
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log
import android.view.KeyEvent
import com.ryanheise.audioservice.MediaButtonReceiver

/**
 * Monitors app task removal (when the user closes/swipes Pulse away from the
 * Recent Apps screen). If the user has enabled "Stop playback on app close",
 * it immediately stops playback, dismisses the notification, and stops the
 * audio service.
 */
class PulseTaskService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        try {
            val prefs = getSharedPreferences("pulse_preferences", Context.MODE_PRIVATE)
            val stopOnClose = prefs.getBoolean("stop_on_close", false)
            if (stopOnClose) {
                stopPlayback(applicationContext)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling task removal: ${e.message}", e)
        }
        stopSelf()
    }

    companion object {
        private const val TAG = "PulseTaskService"

        fun start(context: Context) {
            try {
                context.startService(Intent(context, PulseTaskService::class.java))
            } catch (e: Exception) {
                Log.d(TAG, "Cannot start PulseTaskService: ${e.message}")
            }
        }

        fun stopPlayback(context: Context) {
            // 1. Notify Flutter via channel if engine is alive
            try {
                MainActivity.channel?.invokeMethod("stopPlayback", null)
            } catch (e: Exception) {
                Log.d(TAG, "MethodChannel stopPlayback failed: ${e.message}")
            }

            // 2. Dispatch KEYCODE_MEDIA_STOP to audio_service's MediaButtonReceiver
            try {
                val mediaButton = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                    component = ComponentName(context, MediaButtonReceiver::class.java)
                    putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_STOP))
                }
                context.sendBroadcast(mediaButton)

                val mediaButtonUp = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                    component = ComponentName(context, MediaButtonReceiver::class.java)
                    putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_STOP))
                }
                context.sendBroadcast(mediaButtonUp)
            } catch (e: Exception) {
                Log.e(TAG, "Sending KEYCODE_MEDIA_STOP failed", e)
            }

            // 3. Stop AudioService instance via reflection
            try {
                val audioServiceClass = Class.forName("com.ryanheise.audioservice.AudioService")
                val instanceField = audioServiceClass.getDeclaredField("instance")
                instanceField.isAccessible = true
                val instance = instanceField.get(null)
                if (instance != null) {
                    val stopMethod = audioServiceClass.getMethod("stop")
                    stopMethod.invoke(instance)
                }
            } catch (e: Exception) {
                Log.d(TAG, "Reflection AudioService.instance.stop() failed: ${e.message}")
            }

            // 4. Cancel notification (AudioService notification ID is 1124)
            try {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                notificationManager?.cancel(1124)
            } catch (_: Exception) {}

            // 5. Update widget to show paused/idle state
            try {
                context.getSharedPreferences(PulseWidgetProvider.PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean("playing", false)
                    .apply()
                PulseWidgetProvider.refresh(context)
            } catch (_: Exception) {}
        }
    }
}
