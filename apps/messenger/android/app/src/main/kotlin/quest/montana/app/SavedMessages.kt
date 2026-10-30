package quest.montana.app

import android.content.Context
import android.text.format.DateUtils
import org.json.JSONArray
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * THE OLD SAVED MESSAGES FILE: until build 427 Android kept its letters to itself as words in a file of their own, on a page of their
 * own. The room is now a feed of the book like every chat (Book.SAVED, iOS savedMessagesKey) -- this reads the old file once, for
 * Book.saved to carry its letters over, and forgets it.
 */
object SavedMessages {
    class Letter(val id: String, val text: String, val at: Long)

    private fun file(ctx: Context) = File(ctx.filesDir, "saved_messages.json")

    fun all(ctx: Context): List<Letter> = try {
        val a = JSONArray(file(ctx).readText())
        (0 until a.length()).map { a.getJSONObject(it).let { o -> Letter(o.getString("id"), o.getString("text"), o.getLong("at")) } }
    } catch (e: Exception) { emptyList() }

    /** Carried over, or «Forget this device»: the old file goes. */
    fun forget(ctx: Context) { file(ctx).delete() }
}

/** THE LIST'S STAMP (iOS MTClock.listStamp, MontanaMessageFeed.swift:570-588 at 2155, the author's word 22.09; asked for
 * the chats row by ChatStore.rowTime, MontanaChatStore.swift:420-423): today -- the time; within a week -- the weekday's
 * short name with a capital; further -- the day and the month in the region's own order. */
fun rowTime(c: Context, at: Long): String {
    if (DateUtils.isToday(at)) return android.text.format.DateFormat.getTimeFormat(c).format(Date(at))
    val weekStart = Calendar.getInstance().apply {
        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        add(Calendar.DAY_OF_YEAR, -6)
    }.timeInMillis
    if (at >= weekStart) {
        val w = SimpleDateFormat("EEE", Locale.getDefault()).format(Date(at))
        return w.take(1).uppercase(Locale.getDefault()) + w.drop(1)
    }
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "ddMM")
    return SimpleDateFormat(pattern, Locale.getDefault()).format(Date(at))
}
