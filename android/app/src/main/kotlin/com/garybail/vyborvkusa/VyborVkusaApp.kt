package com.garybail.vyborvkusa

import android.app.Application

class VyborVkusaApp : Application() {
    val model: AppModel by lazy { AppModel(this) }
}
