package com.guidemori.fazendinhaidle

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar
import java.util.TimeZone

class DailyLoginReminder : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIME_CHANGED -> {
                val settings = context.getSharedPreferences("daily_login_reminder", Context.MODE_PRIVATE)
                if (settings.getBoolean("configured", false)) schedule(context)
            }
            ACTION_REMIND -> {
                notify(context)
                schedule(context)
            }
        }
    }

    private fun notify(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (Build.VERSION.SDK_INT >= 24 && !manager.areNotificationsEnabled()) return

        val builder = if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Login diário", NotificationManager.IMPORTANCE_DEFAULT)
            )
            Notification.Builder(context, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val openGame = PendingIntent.getActivity(
            context, ID, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        try {
            manager.notify(
                ID,
                builder.setSmallIcon(android.R.drawable.ic_popup_reminder)
                    .setContentTitle("Login diário · Little Farm")
                    .setContentText("Abra a fazenda para manter sua sequência de recompensas.")
                    .setContentIntent(openGame)
                    .setAutoCancel(true)
                    .build(),
            )
        } catch (_: SecurityException) {
            // A permissão pode ser revogada entre a checagem e a entrega.
        }
    }

    companion object {
        private const val ACTION_REMIND = "com.guidemori.fazendinhaidle.DAILY_LOGIN_REMINDER"
        private const val CHANNEL = "daily_login"
        private const val ID = 4100

        fun schedule(context: Context) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            if (Build.VERSION.SDK_INT >= 24 && !manager.areNotificationsEnabled()) return
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val reminder = PendingIntent.getBroadcast(
                context, ID, Intent(context, DailyLoginReminder::class.java).setAction(ACTION_REMIND),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val next = Calendar.getInstance(TimeZone.getTimeZone("America/Sao_Paulo")).apply {
                set(Calendar.HOUR_OF_DAY, 20)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
            }
            if (Build.VERSION.SDK_INT >= 23) {
                alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, reminder)
            } else {
                alarm.set(AlarmManager.RTC_WAKEUP, next.timeInMillis, reminder)
            }
        }
    }
}
