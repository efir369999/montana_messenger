package quest.montana.app

import android.app.Application
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.util.Log

/**
 * THE BOX IS READ WITH THE APP CLOSED (iOS: the node's push wakes MontanaWakePush, which reads the box). There is no push
 * here, so the platform's own scheduler wakes the app instead: every quarter of an hour while there is a network — the
 * shortest the system grants, stretched further when the phone sleeps deep — the box is picked up once, exactly as the
 * open app does it (Post.fetch), and every new letter of a person rings its banner (Notify.letter). The job outlives a
 * reboot by the system's own hand (persisted), and nothing runs before a person and their terms stand on this device.
 */
class BoxJob : JobService() {
    companion object {
        private const val ID = 7302
        private const val EVERY = 15 * 60 * 1000L

        /** Asked once per start of the app: the job is laid, unless the same job already stands. */
        fun schedule(c: Context) {
            val js = c.getSystemService(JobScheduler::class.java) ?: return
            if (js.getPendingJob(ID) != null) return
            val job = JobInfo.Builder(ID, ComponentName(c, BoxJob::class.java))
                .setPeriodic(EVERY)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPersisted(true)
                .build()
            runCatching { js.schedule(job) }.onFailure { Log.w("Montana", "box job: ${it.javaClass.simpleName}") }
        }
    }

    @Volatile private var stopped = false

    override fun onStartJob(params: JobParameters): Boolean {
        // the app may have been started by this job alone: what the first screen sets up, set up here
        DeviceVault.init(applicationContext)
        Prefs.init(applicationContext)
        Book.ctx = applicationContext
        if (!MontanaSeed.hasSeed || !Prefs.termsAccepted) return false
        stopped = false
        Thread {
            try { Post.fetch() } catch (e: Exception) { Log.w("Montana", "box job: ${e.javaClass.simpleName}") }
            // A WAKE DRAINS THE OUTGOING QUEUE TOO (iOS 1673, atom e6cb9251482f): a wake that read the box and stopped left the letter
            // of the hour before queued for eighteen more hours -- the drain lived in the screen, and there is no screen asleep
            if (!stopped) runCatching { Post.flush() }
            if (!stopped) Update.look(applicationContext)   // a newer build on the site rings its notice with the app closed
            if (!stopped) jobFinished(params, false)
        }.start()
        return true
    }

    /** The system took the time back (the network left, the phone went to sleep): the round is asked again later. */
    override fun onStopJob(params: JobParameters): Boolean { stopped = true; return true }
}

/** The app's first breath, whatever woke it — the screen, the music, or the box job: the job is laid if it is not. */
class MontanaApp : Application() {
    override fun onCreate() {
        super.onCreate()
        BoxJob.schedule(this)
    }
}
