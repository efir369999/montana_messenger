package quest.montana.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log

/**
 * THE EAR WITH THE APP CLOSED (iOS: the platform's push — PushKit rings a call, the node's push reads the box — wakes the app
 * from nothing). There is no such push here, and none is borrowed from a third party: the phone keeps its own ear on our own
 * doors. A foreground service of the platform's own kind for a messenger's link (remoteMessaging) holds the lane of every
 * conversation (Signal.ear) while the phone stands, so a call rings and a letter's hint lands the moment it is said — the app
 * closed, the screen dark. Its notification is the system's quietest. It starts with the app, again after a reboot and after
 * an update, and it raises the call engine at once: a call answered from the lock screen finds it standing.
 */
class EarService : Service() {
    companion object {
        private const val CHANNEL = "ear"
        private const val ID = 0x4d45
        private const val BOX_MS = 5 * 60_000L   // the box between hints: a letter whose hint was lost is read within five minutes
        @Volatile private var wake: PowerManager.WakeLock? = null

        fun start(c: Context) {
            if (!MontanaSeed.hasSeed || !Prefs.termsAccepted) return
            runCatching { c.startForegroundService(Intent(c, EarService::class.java)) }.onFailure { log("start: " + it.message) }
        }

        /** A word landed: the phone stays awake the few seconds its handling and the next long question need. */
        fun awake() { runCatching { wake?.acquire(5000) } }

        private fun log(s: String) { Log.d("Montana", "ear: " + s) }
    }

    @Volatile private var live = false
    private val round = object : Runnable {
        override fun run() {
            if (!live) return
            Signal.ear(true)   // a conversation born since is heard too
            Thread { runCatching { Post.fetch() }; runCatching { Post.flush() } }.start()   // the wake drains the queue too (iOS 1673)
            MainThread.later(BOX_MS, this)
        }
    }

    override fun onCreate() {
        super.onCreate()
        // the app may have been started by this service alone: what the first screen sets up, set up here (as BoxJob)
        DeviceVault.init(applicationContext)
        Prefs.init(applicationContext)
        Book.ctx = applicationContext
        Diary.start(applicationContext)   // the ear may stand before any page: its lines are the diary's too
        wake = getSystemService(PowerManager::class.java)?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "montana:ear")?.apply { setReferenceCounted(false) }
        CallEngine.warm(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        publish()   // asked into the foreground, it stands there at once — then lets go if no person stands on this phone
        if (!MontanaSeed.hasSeed || !Prefs.termsAccepted) { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); return START_NOT_STICKY }
        if (!live) { live = true; MainThread.later(0, round); log("up") }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        live = false
        log("down")
        super.onDestroy()
    }

    private fun publish() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, getString(R.string.ear_channel), NotificationManager.IMPORTANCE_MIN).apply {
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
        })
        val open = PendingIntent.getActivity(this, 5, Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentText(getString(R.string.ear_ready))
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(open)
            .build()
        runCatching {
            if (Build.VERSION.SDK_INT >= 34) startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING) else startForeground(ID, n)
        }.onFailure { log("foreground: " + it.message); stopSelf() }
    }
}

/** The ear comes back with the phone (a reboot) and with the app (an update): the platform lets a foreground service start on these words. */
class EarStart : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        val app = c.applicationContext
        DeviceVault.init(app)
        Prefs.init(app)
        Book.ctx = app
        EarService.start(app)
    }
}
