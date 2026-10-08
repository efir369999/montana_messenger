package quest.montana.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * THE CALL IN HAND, KNOWN TO THE SYSTEM (iOS: CallKit's ongoing call and the audio session that keeps the app speaking): from
 * «Answer» to the end the call stands as the platform's own ongoing call — the caller's name and face, the clock from the moment
 * the voice joined, «Hang up» — and holds the microphone in the foreground, so the voice goes on with the screen dark or the app
 * left. The press of «Hang up» is the ring's own receiver (CallDecline): one end for every road.
 */
class CallService : Service() {
    companion object {
        private const val CHANNEL = "call_line"
        private const val ID = 0x4d4c
        @Volatile private var running: CallService? = null
        @Volatile private var ref: String? = null

        fun start(c: Context, who: String) {
            ref = who
            runCatching { c.startForegroundService(Intent(c, CallService::class.java)) }.onFailure { log("start: " + it.message) }
        }

        /** The voice joined: the clock starts on the call's notification. */
        fun sync() { running?.let { s -> MainThread.post { s.publish() } } }

        /** At once, on the main thread: the screen's projection asks for its foreground before it may begin (Android 14). */
        fun publishNow() { running?.publish() }

        fun stop() {
            ref = null
            running?.let { s -> MainThread.post { s.end() } }
        }

        private fun log(s: String) { Log.d("Montana", "call service: " + s) }
    }

    override fun onCreate() {
        super.onCreate()
        running = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // started in the foreground's name, it stands there at once — even a call gone meanwhile is shown, then let go
        publish()
        if (ref == null) end()
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        running = null
        super.onDestroy()
    }

    private fun end() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun publish() {
        val who = ref
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, getString(R.string.app_calls), NotificationManager.IMPORTANCE_DEFAULT).apply {
            setSound(null, null)   // the call in hand is silent: the ring was the other channel's
            enableVibration(false)
            setShowBadge(false)
        })
        val name = who?.let { Book.chat(it)?.shown?.ifBlank { null } } ?: getString(R.string.peer)
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val open = PendingIntent.getActivity(this, 4, Intent(this, MainActivity::class.java).apply { who?.let { putExtra(Calls.EXTRA_REF, it) } }
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP), flags)
        val hang = PendingIntent.getBroadcast(this, 3, Intent(this, CallDecline::class.java), flags)
        val since = CallLine.connectedAt
        val b = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(name)   // USER-DATA: the peer's name
            .setContentText(getString(if (CallLine.video) R.string.call_video else R.string.call_voice))
            .setCategory(Notification.CATEGORY_CALL)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
        if (since > 0L) b.setWhen(since).setUsesChronometer(true).setShowWhen(true) else b.setShowWhen(false)
        if (Build.VERSION.SDK_INT >= 31) {
            val face = who?.let { Book.shownFace(it) }?.takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }?.let { Icon.createWithBitmap(it) }
            b.setStyle(Notification.CallStyle.forOngoingCall(Person.Builder().setName(name).setIcon(face).build(), hang).setIsVideo(CallLine.video))
        } else {
            b.addAction(Notification.Action.Builder(null as Icon?, getString(R.string.call_end), hang).build())
        }
        val n = b.build()
        // the microphone's foreground needs the microphone granted: without it the call speaks only while the app stands in front;
        // a video call adds the camera's, so the picture goes on with the app left, and a shared screen its projection's —
        // a type refused, the next smaller set is asked, down to the voice alone
        if (Build.VERSION.SDK_INT < 30) { runCatching { startForeground(ID, n) }.onFailure { log("foreground: " + it.message); end() }; return }
        val voice = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        val screen = if (CallLine.sharing) voice or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION else voice
        // the camera's type stays through a share: the camera comes back at its end, and with the app behind it opens only under it
        val full = if (CallLine.video) screen or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA else screen
        for (types in listOf(full, screen, voice).distinct()) {
            if (runCatching { startForeground(ID, n, types) }.onFailure { log("foreground " + types + ": " + it.message) }.isSuccess) return
        }
        end()
    }
}
