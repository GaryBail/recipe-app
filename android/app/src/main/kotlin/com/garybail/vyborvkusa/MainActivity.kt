package com.garybail.vyborvkusa

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import com.garybail.vyborvkusa.ui.AppRoot

class MainActivity : ComponentActivity() {
    private val model get() = (application as VyborVkusaApp).model

    /** Разрешение на уведомления (Android 13+) спрашиваем, когда человек вошёл в аккаунт. */
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handle(intent)
        setContent {
            AppRoot(model, onLoggedIn = {
                if (Build.VERSION.SDK_INT >= 33) notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            })
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        intent?.getStringExtra(NotificationWorker.EXTRA_OPEN)?.let { model.pendingRoute = it }
        // Возврат из браузера после входа через VK ID / Яндекс ID.
        intent?.data?.let { model.handleOAuthRedirect(it) }
    }
}
