package com.pulse.music

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    companion object {
        /**
         * Set once the app's engine is up. Static, so it resets when the
         * process dies — which is exactly when widget buttons have nothing to
         * control (see PulseWidgetActionReceiver).
         */
        @Volatile
        var engineReady = false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        engineReady = true
        // Application context: the engine can outlive this activity while
        // audio keeps playing in the background.
        val app = applicationContext
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pulse/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
                    "setLauncherIcon" -> {
                        setLauncherIcon(app, call.argument<Boolean>("dark") ?: false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
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
}
