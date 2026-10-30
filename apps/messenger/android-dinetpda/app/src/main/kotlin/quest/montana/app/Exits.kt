package quest.montana.app

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.util.Log

/**
 * NO EXIT GOES UNWITNESSED (iOS 1336: the run sentinel, MontanaApp 1349-1560): the next run names how the last one ended. The
 * iPhone keeps a sentinel of its own and judges it by MetricKit; this platform keeps the record itself (ApplicationExitInfo)
 * and names the cause. The diary says each exit once, at the first launch after it.
 */
object Exits {
    fun witness(c: Context) {
        if (Build.VERSION.SDK_INT < 30) return
        val am = c.getSystemService(ActivityManager::class.java) ?: return
        val seen = Prefs.str("exitSeen", "0").toLongOrNull() ?: 0L
        val gone = runCatching { am.getHistoricalProcessExitReasons(c.packageName, 0, 8) }.getOrNull() ?: return
        val fresh = gone.filter { seen < it.timestamp }.sortedBy { it.timestamp }
        for (e in fresh) {
            Log.d("Montana", "run_exit reason=" + reason(e.reason) + " status=" + e.status + " importance=" + e.importance +
                " pss=" + e.pss + " rss=" + e.rss + " at=" + e.timestamp + " desc=" + (e.description ?: ""))
        }
        fresh.lastOrNull()?.let { Prefs.setStr("exitSeen", it.timestamp.toString()) }
    }

    private fun reason(r: Int): String = when (r) {
        ApplicationExitInfo.REASON_EXIT_SELF -> "exit-self"
        ApplicationExitInfo.REASON_SIGNALED -> "signaled"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "low-memory"
        ApplicationExitInfo.REASON_CRASH -> "crash"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "crash-native"
        ApplicationExitInfo.REASON_ANR -> "anr"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "init-failure"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "permission-change"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "excessive-resource"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "user-requested"
        ApplicationExitInfo.REASON_USER_STOPPED -> "user-stopped"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "dependency-died"
        ApplicationExitInfo.REASON_OTHER -> "other"
        else -> "code-" + r
    }
}
