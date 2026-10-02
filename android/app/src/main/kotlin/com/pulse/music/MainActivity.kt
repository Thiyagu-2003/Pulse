package com.pulse.music

import android.app.ActivityManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.RingtoneManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer

class MainActivity : AudioServiceActivity() {

    companion object {
        /**
         * Set once the app's engine is up. Static, so it resets when the
         * process dies — which is exactly when widget buttons have nothing to
         * control (see PulseWidgetActionReceiver).
         */
        @Volatile
        var engineReady = false

        var channel: MethodChannel? = null
    }

    override fun onStart() {
        super.onStart()
        PulseTaskService.start(applicationContext)
    }

    override fun onResume() {
        super.onResume()
        PulseTaskService.start(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        engineReady = true
        applyTaskIcon()
        PulseTaskService.start(applicationContext)
        // Application context: the engine can outlive this activity while
        // audio keeps playing in the background.
        val app = applicationContext
        val platformChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pulse/platform")
        channel = platformChannel
        platformChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setStopOnClose" -> {
                        val stop = call.argument<Boolean>("stop") ?: false
                        app.getSharedPreferences("pulse_preferences", Context.MODE_PRIVATE)
                            .edit()
                            .putBoolean("stop_on_close", stop)
                            .apply()
                        result.success(null)
                    }
                    "updateWidget" -> {
                        app.getSharedPreferences(PulseWidgetProvider.PREFS, Context.MODE_PRIVATE)
                            .edit()
                            .putString("title", call.argument<String>("title"))
                            .putString("artist", call.argument<String>("artist"))
                            .putString("artPath", call.argument<String>("artPath"))
                            .putBoolean("playing", call.argument<Boolean>("playing") ?: false)
                            .apply()
                        PulseWidgetProvider.refresh(app)
                        result.success(null)
                    }
                    "appVersion" -> {
                        result.success(packageManager.getPackageInfo(packageName, 0).versionName)
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url != null) {
                            startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url)))
                        }
                        result.success(null)
                    }
                    "share" -> {
                        // The activity, not the app context: the chooser is a
                        // screen of its own.
                        val send = Intent(Intent.ACTION_SEND)
                            .setType("text/plain")
                            .putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                        startActivity(Intent.createChooser(send, null))
                        result.success(null)
                    }
                    "scanFile" -> {
                        val path = call.argument<String>("path")
                        if (path != null) {
                            MediaScannerConnection.scanFile(app, arrayOf(path), null, null)
                        }
                        result.success(null)
                    }
                    "setDownloadsRunning" -> {
                        DownloadKeepAliveService.setRunning(app, call.argument<Boolean>("running") ?: false)
                        result.success(null)
                    }
                    "setIconStyle" -> {
                        // Applied at once to everything Pulse draws; the
                        // launcher entry itself switches on leaving the app.
                        IconStyle.setDark(app, call.argument<Boolean>("dark") ?: false)
                        applyTaskIcon()
                        PulseWidgetProvider.refresh(app)
                        result.success(null)
                    }
                    "setLauncherIcon" -> {
                        setLauncherIcon(app, call.argument<Boolean>("dark") ?: false)
                        result.success(null)
                    }
                    "setRingtone" -> {
                        Thread {
                            val tempTrimmed = File(app.cacheDir, "ringtone_trimmed_${System.currentTimeMillis()}.m4a")
                            try {
                                val filePath = call.argument<String>("filePath")!!
                                val title = call.argument<String>("title") ?: "Pulse Ringtone"
                                val artist = call.argument<String>("artist") ?: "Unknown"
                                val type = call.argument<String>("type") ?: "ringtone"
                                val startMs = (call.argument<Int>("startMs") ?: 0).toLong()
                                val endMs = (call.argument<Int>("endMs") ?: 0).toLong()

                                val ringtoneType = when (type) {
                                    "notification" -> RingtoneManager.TYPE_NOTIFICATION
                                    "alarm"        -> RingtoneManager.TYPE_ALARM
                                    else           -> RingtoneManager.TYPE_RINGTONE
                                }

                                val sourceFile = File(filePath)
                                if (!sourceFile.exists()) {
                                    runOnUiThread { result.success(false) }
                                    return@Thread
                                }

                                // Trim audio if custom timing is requested
                                var useTrimmed = false
                                if (endMs > startMs) {
                                    useTrimmed = trimAudio(
                                        sourceFile.absolutePath,
                                        tempTrimmed.absolutePath,
                                        startMs,
                                        endMs
                                    ) && tempTrimmed.exists() && tempTrimmed.length() > 0
                                }
                                val inputFile = if (useTrimmed) tempTrimmed else sourceFile

                                // Copy to the appropriate shared directory.
                                val subDir = when (type) {
                                    "notification" -> Environment.DIRECTORY_NOTIFICATIONS
                                    "alarm"        -> Environment.DIRECTORY_ALARMS
                                    else           -> Environment.DIRECTORY_RINGTONES
                                }

                                val ext = if (useTrimmed) "m4a" else sourceFile.extension.ifEmpty { "m4a" }
                                val mimeType = when (ext.lowercase()) {
                                    "mp3" -> "audio/mpeg"
                                    "ogg", "opus" -> "audio/ogg"
                                    "wav" -> "audio/wav"
                                    else -> "audio/mp4"
                                }

                                val safeName = title.replace(Regex("[^\\w\\s-]"), "")
                                    .replace(Regex("\\s+"), "_")
                                    .take(60)
                                val destName = "Pulse_${safeName}_${System.currentTimeMillis() % 100000}.$ext"

                                val contentUri: Uri?
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    // Android 10+: use MediaStore with IS_PENDING to prevent premature scanning.
                                    val values = ContentValues().apply {
                                        put(MediaStore.Audio.Media.DISPLAY_NAME, destName)
                                        put(MediaStore.Audio.Media.TITLE, "$title (Pulse)")
                                        put(MediaStore.Audio.Media.ARTIST, artist)
                                        put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
                                        put(MediaStore.Audio.Media.RELATIVE_PATH, "$subDir/Pulse")
                                        put(MediaStore.Audio.Media.IS_RINGTONE, type == "ringtone")
                                        put(MediaStore.Audio.Media.IS_NOTIFICATION, type == "notification")
                                        put(MediaStore.Audio.Media.IS_ALARM, type == "alarm")
                                        put(MediaStore.Audio.Media.IS_MUSIC, false)
                                        put(MediaStore.Audio.Media.IS_PENDING, 1)
                                    }
                                    contentUri = app.contentResolver.insert(
                                        MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                                        values
                                    )
                                    if (contentUri != null) {
                                        app.contentResolver.openOutputStream(contentUri)?.use { out ->
                                            inputFile.inputStream().use { inp -> inp.copyTo(out) }
                                        }
                                        val publishValues = ContentValues().apply {
                                            put(MediaStore.Audio.Media.IS_PENDING, 0)
                                        }
                                        app.contentResolver.update(contentUri, publishValues, null, null)
                                    }
                                } else {
                                    // Pre-Q: write to external storage directly.
                                    val dir = File(
                                        Environment.getExternalStoragePublicDirectory(subDir),
                                        "Pulse"
                                    )
                                    dir.mkdirs()
                                    val destFile = File(dir, destName)
                                    inputFile.copyTo(destFile, overwrite = true)

                                    val values = ContentValues().apply {
                                        put(MediaStore.Audio.Media.DATA, destFile.absolutePath)
                                        put(MediaStore.Audio.Media.TITLE, "$title (Pulse)")
                                        put(MediaStore.Audio.Media.ARTIST, artist)
                                        put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
                                        put(MediaStore.Audio.Media.IS_RINGTONE, type == "ringtone")
                                        put(MediaStore.Audio.Media.IS_NOTIFICATION, type == "notification")
                                        put(MediaStore.Audio.Media.IS_ALARM, type == "alarm")
                                        put(MediaStore.Audio.Media.IS_MUSIC, false)
                                    }
                                    contentUri = app.contentResolver.insert(
                                        MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                                        values
                                    )
                                }

                                if (contentUri != null) {
                                    RingtoneManager.setActualDefaultRingtoneUri(app, ringtoneType, contentUri)
                                    runOnUiThread { result.success(true) }
                                } else {
                                    runOnUiThread { result.success(false) }
                                }
                            } catch (e: Exception) {
                                e.printStackTrace()
                                runOnUiThread { result.success(false) }
                            } finally {
                                try {
                                    if (tempTrimmed.exists()) tempTrimmed.delete()
                                } catch (_: Exception) {}
                            }
                        }.start()
                    }
                    "hasWriteSettings" -> {
                        result.success(Settings.System.canWrite(app))
                    }
                    "requestWriteSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                                data = Uri.parse("package:${app.packageName}")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                        } catch (e: Exception) {
                            val fallbackIntent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(fallbackIntent)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** The recent-apps entry shows the chosen icon too. */
    private fun applyTaskIcon() {
        val res = IconStyle.imageRes(this)
        @Suppress("DEPRECATION")
        val description = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            ActivityManager.TaskDescription("Pulse", res)
        } else {
            ActivityManager.TaskDescription("Pulse", BitmapFactory.decodeResource(resources, res))
        }
        setTaskDescription(description)
    }

    /**
     * The launcher entry is one of two activity-aliases (see the manifest);
     * the icon is switched by enabling one and disabling the other. Skipped
     * when already right, since every switch makes the launcher refresh.
     */
    private fun setLauncherIcon(context: Context, dark: Boolean) {
        val pm = context.packageManager
        val light = ComponentName(context, "com.pulse.music.LauncherLight")
        val darkAlias = ComponentName(context, "com.pulse.music.LauncherDark")
        // DEFAULT means "as in the manifest": light enabled, dark disabled.
        fun enabled(c: ComponentName, byDefault: Boolean) =
            when (pm.getComponentEnabledSetting(c)) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> byDefault
                else -> false
            }
        if (enabled(darkAlias, false) == dark && enabled(light, true) == !dark) return
        val wanted = if (dark) darkAlias else light
        val other = if (dark) light else darkAlias
        pm.setComponentEnabledSetting(wanted, PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        pm.setComponentEnabledSetting(other, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
    }

    /**
     * Trims an audio file from [startMs] to [endMs] using MediaExtractor and MediaMuxer.
     * Keeps the original compression without re-encoding. Returns true on success.
     */
    private fun trimAudio(sourcePath: String, destPath: String, startMs: Long, endMs: Long): Boolean {
        var extractor: MediaExtractor? = null
        var muxer: MediaMuxer? = null
        try {
            extractor = MediaExtractor()
            extractor.setDataSource(sourcePath)

            var audioTrackIndex = -1
            var audioFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    audioFormat = format
                    break
                }
            }

            if (audioTrackIndex < 0 || audioFormat == null) {
                return false
            }

            extractor.selectTrack(audioTrackIndex)

            val startUs = startMs * 1000L
            val endUs = endMs * 1000L
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)

            muxer = MediaMuxer(destPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val muxerTrackIndex = muxer.addTrack(audioFormat)
            muxer.start()

            val maxBufferSize = if (audioFormat.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                audioFormat.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
            } else {
                128 * 1024
            }
            val buffer = ByteBuffer.allocate(Math.max(maxBufferSize, 128 * 1024))
            val bufferInfo = MediaCodec.BufferInfo()
            var firstSampleTimeUs = -1L
            var samplesWritten = 0

            while (true) {
                buffer.clear()
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize < 0) break

                val sampleTimeUs = extractor.sampleTime
                if (sampleTimeUs > endUs && samplesWritten > 0) break

                if (sampleTimeUs >= startUs || firstSampleTimeUs >= 0L) {
                    if (firstSampleTimeUs < 0L) {
                        firstSampleTimeUs = sampleTimeUs
                    }
                    bufferInfo.offset = 0
                    bufferInfo.size = sampleSize
                    bufferInfo.presentationTimeUs = Math.max(0L, sampleTimeUs - firstSampleTimeUs)
                    bufferInfo.flags = extractor.sampleFlags
                    muxer.writeSampleData(muxerTrackIndex, buffer, bufferInfo)
                    samplesWritten++
                }

                extractor.advance()
            }

            muxer.stop()
            muxer.release()
            muxer = null
            extractor.release()
            extractor = null
            return samplesWritten > 0
        } catch (e: Exception) {
            android.util.Log.w("MainActivity", "trimAudio failed: ${e.message}")
            try { muxer?.release() } catch (_: Exception) {}
            try { extractor?.release() } catch (_: Exception) {}
            return false
        }
    }
}
