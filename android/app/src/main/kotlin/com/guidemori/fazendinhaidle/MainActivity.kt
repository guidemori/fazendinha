package com.guidemori.fazendinhaidle

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "little_farm/daily_login_reminder"
        ).setMethodCallHandler { call, result ->
            if (call.method == "enable") {
                enableDailyReminder()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun enableDailyReminder() {
        val settings = getSharedPreferences("daily_login_reminder", MODE_PRIVATE)
        settings.edit().putBoolean("configured", true).apply()
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            if (!settings.getBoolean("permission_requested", false)) {
                settings.edit().putBoolean("permission_requested", true).apply()
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REMINDER_PERMISSION)
            }
            return
        }
        DailyLoginReminder.schedule(this)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REMINDER_PERMISSION &&
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        ) {
            DailyLoginReminder.schedule(this)
        }
    }

    companion object {
        private const val REMINDER_PERMISSION = 4101
    }
}
