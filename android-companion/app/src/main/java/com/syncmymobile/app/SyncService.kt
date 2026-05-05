package com.syncmymobile.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder

class SyncService : Service() {
    private var httpServer: HttpFileServer? = null
    private var beacon: UdpBeacon? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(1, notification())
        val wifi = applicationContext.getSystemService(WIFI_SERVICE) as? WifiManager
        multicastLock = wifi?.createMulticastLock("sync-my-mobile-beacon")?.also {
            it.setReferenceCounted(false)
            it.acquire()
        }
        val index = FileIndex(this)
        httpServer = HttpFileServer(this, index, HTTP_PORT).also { it.start() }
        beacon = UdpBeacon(this, HTTP_PORT).also { it.start() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        beacon?.stop()
        httpServer?.stop()
        multicastLock?.let {
            if (it.isHeld) it.release()
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun notification(): Notification {
        val channelId = "sync-service"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "Sync service", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
                .setContentTitle("Sync My Mobile")
                .setContentText("Ready at ${NetworkInfo.localAddresses().firstOrNull() ?: "phone IP"}:$HTTP_PORT")
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("Sync My Mobile")
                .setContentText("Ready at ${NetworkInfo.localAddresses().firstOrNull() ?: "phone IP"}:$HTTP_PORT")
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .build()
        }
    }
}
