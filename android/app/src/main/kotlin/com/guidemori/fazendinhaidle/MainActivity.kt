package com.guidemori.fazendinhaidle

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
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
                enableDailyReminder(fromSettingsButton = call.arguments == true)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "little_farm/social"
        ).setMethodCallHandler { call, result ->
            if (call.method != "shareInvite") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val message = call.arguments as? String
            if (message.isNullOrBlank()) {
                result.error("invalid_invite", "Convite vazio", null)
                return@setMethodCallHandler
            }

            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, message)
            }
            startActivity(Intent.createChooser(intent, "Convidar para o Little Farm"))
            result.success(null)
        }
    }

    private fun enableDailyReminder(fromSettingsButton: Boolean) {
        val settings = getSharedPreferences("daily_login_reminder", MODE_PRIVATE)
        settings.edit().putBoolean("configured", true).apply()
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            val permission = Manifest.permission.POST_NOTIFICATIONS
            val alreadyRequested = settings.getBoolean("permission_requested", false)
            if (!alreadyRequested ||
                (fromSettingsButton && shouldShowRequestPermissionRationale(permission))
            ) {
                settings.edit().putBoolean("permission_requested", true).apply()
                requestPermissions(arrayOf(permission), REMINDER_PERMISSION)
            } else if (fromSettingsButton) {
                openNotificationSettings()
            }
            return
        }
        if (fromSettingsButton && Build.VERSION.SDK_INT >= 26) {
            openNotificationSettings()
        }
        DailyLoginReminder.schedule(this)
    }

    private fun openNotificationSettings() {
        startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        })
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
