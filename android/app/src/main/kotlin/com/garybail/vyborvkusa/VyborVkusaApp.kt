package com.garybail.vyborvkusa

import android.app.Application

class VyborVkusaApp : Application() {
    val model: AppModel by lazy { AppModel(this) }

    override fun onCreate() {
        super.onCreate()
        NotificationWorker.createChannel(this)
        NotificationWorker.schedule(this)
    }
}
