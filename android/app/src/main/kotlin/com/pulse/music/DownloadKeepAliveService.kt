package com.pulse.music

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps the app process alive while downloads run.
 *
 * The downloads themselves happen in Dart; without a foreground service
 * Android is free to kill the process soon after the user leaves the app,
 * and the half-written file would be abandoned. Started when the first
 * download begins, stopped when the last one ends (MainActivity).
 */
class DownloadKeepAliveService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        foreground = true
        // The downloads may already have finished while the service was
        // starting; stopping only now (after startForeground) is what keeps
        // Android from killing the app for a broken foreground promise.
        if (!wanted) stopSelf()
        // If Android kills us anyway, don't restart: the Dart side that owns
        // the downloads is gone with the process.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        foreground = false
        super.onDestroy()
    }

    // Android 15 caps dataSync services at 6h; song downloads never get close,
    // but the service must stop when told to.
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Background downloads", NotificationManager.IMPORTANCE_MIN),
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_download)
            .setContentTitle("Downloading songs")
            .setContentText("Pulse keeps going in the background")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "download_keepalive"
        private const val NOTIFICATION_ID = 4242

        // Main thread only (method channel), so no locking needed.
        private var wanted = false
        private var foreground = false

        fun setRunning(context: Context, running: Boolean) {
            wanted = running
            val intent = Intent(context, DownloadKeepAliveService::class.java)
            if (!running) {
                // Stopping a service that hasn't reached startForeground()
                // yet crashes the app (a download that fails instantly);
                // onStartCommand stops it itself in that case.
                if (foreground) context.stopService(intent)
                return
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                // Refused (e.g. app already in the background): downloads
                // still run, just without the keep-alive.
            }
        }
    }
}
