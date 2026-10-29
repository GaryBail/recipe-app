package com.garybail.vyborvkusa

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers

/**
 * Фоновая проверка уведомлений сервера (оценки сборок, «подешевело»). Раз в полчаса, только при наличии сети.
 * Работает без Firebase и без сервисов Google — подходит для любых Android-телефонов.
 * Мгновенные push (Firebase / RuStore Push) можно добавить позже, когда будут ключи проектов.
 */
class NotificationWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val model = (applicationContext as VyborVkusaApp).model
        // Модель грузит каталог и данные асинхронно — ждём до 10 с.
        repeat(50) { if (model.loaded == null) delay(200) }
        if (model.loaded == null || model.account == null) return Result.success()
        val list = withContext(Dispatchers.Main) { model.notifications() } ?: return Result.retry()
        val seen = model.data.notifiedIds.toSet()
        val fresh = list.items.filter { !it.isRead && it.id !in seen }.take(5)
        if (fresh.isEmpty()) return Result.success()
        for (n in fresh) show(applicationContext, n.id.toInt(), n.title, n.body)
        withContext(Dispatchers.Main) { model.rememberNotified(fresh.map { it.id }) }
        return Result.success()
    }

    companion object {
        const val CHANNEL = "updates"
        const val EXTRA_OPEN = "open"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<NotificationWorker>(30, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork("notifications", ExistingPeriodicWorkPolicy.KEEP, request)
        }

        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(CHANNEL, "Оценки и цены", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Оценки ваших сборок и напоминания, когда корзина подешевела"
                }
                context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
            }
        }

        fun show(context: Context, id: Int, title: String, body: String) {
            if (Build.VERSION.SDK_INT >= 33 &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) return
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(EXTRA_OPEN, "notifications")
            }
            val pending = PendingIntent.getActivity(context, id, intent,
                                                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setContentIntent(pending)
                .setAutoCancel(true)
                .build()
            NotificationManagerCompat.from(context).notify(id, notification)
        }
    }
}
