package quest.montana.app

import org.json.JSONArray
import org.json.JSONObject

/**
 * THE LIST'S OWN MARKS ON A CHAT (iOS ChatStore pinnedChats, mutedChats, archivedNames, forcedUnread): pinned to the top —
 * five at most, the newest pin highest; muted — the chat's letters raise no banner; archived — the row leaves the list for
 * the «Archive» page; and the hand mark «unread» — the dot a person puts on a chat where nothing is unread. They are the
 * person's own bookkeeping: none of them is ever told to the correspondent. Kept sealed in the device vault, as iOS keeps
 * them in its local vault.
 */
object ChatMarks {
    private const val KEY = "chatMarks"
    const val MAX_PINNED = 5
    private val lock = Any()
    private var loaded = false
    private val pinned = mutableListOf<String>()
    private val muted = mutableSetOf<String>()
    private val archived = mutableSetOf<String>()
    private val forcedUnread = mutableSetOf<String>()
    private val contactPins = mutableListOf<String>()      // the contacts page's own pins (iOS pinnedContacts)
    private val contactArchive = mutableSetOf<String>()    // the contacts page's own archive (iOS archivedContacts)
    private val listeners = mutableListOf<() -> Unit>()
    /** The person forgotten: every mark of every chat leaves with them (Book.wipe). */
    fun wipe() = synchronized(lock) {
        pinned.clear(); muted.clear(); archived.clear(); forcedUnread.clear(); contactPins.clear(); contactArchive.clear()
        loaded = false; DeviceVault.delete(KEY)
    }

    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }

    private fun ensure() {
        if (loaded) return
        loaded = true
        val o = DeviceVault.get(KEY)?.toString(Charsets.UTF_8)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return
        fun read(name: String, into: MutableCollection<String>) = o.optJSONArray(name)?.let { a -> for (i in 0 until a.length()) into.add(a.getString(i)) }
        read("pin", pinned); read("mute", muted); read("arch", archived); read("unread", forcedUnread)
        read("cpin", contactPins); read("carch", contactArchive)
    }

    private fun save() {
        val o = JSONObject().put("pin", JSONArray(pinned)).put("mute", JSONArray(muted))
            .put("arch", JSONArray(archived)).put("unread", JSONArray(forcedUnread))
            .put("cpin", JSONArray(contactPins)).put("carch", JSONArray(contactArchive))
        DeviceVault.set(KEY, o.toString().toByteArray(Charsets.UTF_8))
    }

    private fun change(work: () -> Unit) {
        synchronized(lock) { ensure(); work(); save() }
        synchronized(listeners) { listeners.toList() }.forEach { it() }
    }

    fun isPinned(ref: String) = synchronized(lock) { ensure(); ref in pinned }
    fun isMuted(ref: String) = synchronized(lock) { ensure(); ref in muted }
    fun isArchived(ref: String) = synchronized(lock) { ensure(); ref in archived }
    /** The place of a pinned chat at the top (0 — highest), or null for a chat not pinned. */
    fun pinPlace(ref: String): Int? = synchronized(lock) { ensure(); pinned.indexOf(ref).takeIf { it >= 0 } }

    /** Pin or unpin; false when a sixth pin was asked (iOS: «maximum 5 pinned»). */
    fun togglePin(ref: String): Boolean {
        var ok = true
        change {
            when {
                ref in pinned -> pinned.remove(ref)
                pinned.size >= MAX_PINNED -> ok = false
                else -> pinned.add(0, ref)   // the new one — to the very top
            }
        }
        return ok
    }

    fun toggleMute(ref: String) = change { if (!muted.remove(ref)) muted.add(ref) }

    fun archive(ref: String) = change { archived.add(ref) }
    fun unarchive(ref: String) = change { archived.remove(ref) }

    /** The row's dot: a number of unread letters, or the hand mark where there is none (iOS hasUnread). */
    fun hasUnread(chat: Chat) = chat.unread > 0 || synchronized(lock) { ensure(); chat.ref in forcedUnread }
    fun handMark(ref: String) = synchronized(lock) { ensure(); ref in forcedUnread }

    /**
     * THE MARK BOTH WAYS (iOS toggleUnread): a chat with something unread is marked read — its letters become read here, and
     * the correspondent hears nothing, it is one's own bookkeeping; a chat with nothing unread takes the hand mark.
     */
    fun toggleUnread(chat: Chat) {
        if (hasUnread(chat)) {
            if (chat.unread > 0) Book.edit(chat.ref) { it.unread = 0 }
            change { forcedUnread.remove(chat.ref) }
        } else change { forcedUnread.add(chat.ref) }
    }

    /** The chat opened: the hand mark has done its work (iOS: the mark yields to reading). */
    fun opened(ref: String) { if (handMark(ref)) change { forcedUnread.remove(ref) } }

    // ── the contacts page's own marks (iOS togglePinContact / toggleArchiveContact): apart from the chats' ──
    fun isContactPinned(ref: String) = synchronized(lock) { ensure(); ref in contactPins }
    fun isContactArchived(ref: String) = synchronized(lock) { ensure(); ref in contactArchive }
    fun contactArchiveCount() = synchronized(lock) { ensure(); contactArchive.size }
    fun toggleContactPin(ref: String) = change { if (!contactPins.remove(ref)) contactPins.add(0, ref) }
    fun toggleContactArchive(ref: String) = change { if (!contactArchive.remove(ref)) contactArchive.add(ref) }

    /** A chat forgotten leaves no mark behind. */
    fun forget(ref: String) = change {
        pinned.remove(ref); muted.remove(ref); archived.remove(ref); forcedUnread.remove(ref); contactPins.remove(ref); contactArchive.remove(ref)
    }

    /** The iPhone's names of the six sets (iOS SeedScope.dataKeys, MontanaChatStore.swift 6120-6121, 6131): a copy carries them by these. */
    val NAMES = listOf("pinnedChatsList", "mutedChats", "archivedNames", "forcedUnread", "pinnedContacts", "archivedContacts")

    /** Every set by the iPhone's name, as a copy carries it (iOS seedCard: sealed lists of words). */
    fun carried(): Map<String, List<String>> = synchronized(lock) {
        ensure()
        mapOf("pinnedChatsList" to pinned.toList(), "mutedChats" to muted.toList(), "archivedNames" to archived.toList(),
            "forcedUnread" to forcedUnread.toList(), "pinnedContacts" to contactPins.toList(), "archivedContacts" to contactArchive.toList())
    }

    /**
     * A COPY LAID (iOS layCard 884-891 under SeedScope.unionKeys 6303-6306; readVaultLight and takeStored, MontanaChatStore.swift
     * 2062-2065, 2134-2136): each set takes what it lacks and what stands here stays — a copy adds a pin, a mute or an archive and
     * never lifts one. Laid off the screen's thread, so the screens are told on theirs.
     */
    fun lay(sets: Map<String, List<String>>) {
        synchronized(lock) {
            ensure()
            fun add(into: MutableCollection<String>, name: String) { sets[name]?.forEach { if (it.isNotEmpty() && it !in into) into.add(it) } }
            add(pinned, "pinnedChatsList"); add(muted, "mutedChats"); add(archived, "archivedNames"); add(forcedUnread, "forcedUnread")
            add(contactPins, "pinnedContacts"); add(contactArchive, "archivedContacts")
            save()
        }
        val ls = synchronized(listeners) { listeners.toList() }
        MainThread.post { ls.forEach { it() } }
    }
}
