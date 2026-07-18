package com.prplegryn.fourgcut

import android.app.Application

class FourGCutApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        CrashLogStore.install(this)
    }
}
