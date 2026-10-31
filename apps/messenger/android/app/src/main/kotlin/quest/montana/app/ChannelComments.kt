package quest.montana.app

import org.json.JSONArray
import org.json.JSONObject

/**
 * THE COMMENTS OF A CHANNEL'S POSTS ON THIS PHONE (iOS MTChannelComments, the reference's discussion under a post): each post's
 * comments by their one names, in the order of their moments; the channel's carrier brings them (Groups.comment, commented). The
 * person's own content, as letters are: kept sealed in the device vault and forgotten with the seed.
 */
object ChannelComments {
    class Comment(val id: String, val seat: String, val name: String, val text: String, val at: Long, val mine: Boolean) {
        fun json(): JSONObject = JSONObject().put("id", id).put("s", seat).put("n", name).put("tx", text).put("at", at).put("o", mine)
        companion object {
            fun of(o: JSONObject) = Comment(o.getString("id"), o.optString("s"), o.optString("n"), o.getString("tx"), o.getLong("at"), o.optBoolean("o"))
        }
    }

    private const val KEY = "channels.comments"
    /** [I-14]: the comments a post keeps, and the posts a channel keeps comments for. */
    private const val PER_POST = 500
    private const val POSTS_KEPT = 300
    private val lock = Any()
    private var loaded = false
    private val book = mutableMapOf<String, MutableMap<String, MutableList<Comment>>>()
    private val listeners = mutableListOf<() -> Unit>()

    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }
    private fun changed() { val ls = synchronized(listeners) { listeners.toList() }; MainThread.post { ls.forEach { it() } } }

    private fun ensure() {
        if (loaded) return
        loaded = true
        book.clear()
        val raw = DeviceVault.get(KEY) ?: return
        runCatching {
            val o = JSONObject(String(raw, Charsets.UTF_8))
            o.keys().forEach { key ->
                val page = o.getJSONObject(key)
                val posts = mutableMapOf<String, MutableList<Comment>>()
                page.keys().forEach { post ->
                    val a = page.getJSONArray(post)
                    posts[post] = MutableList(a.length()) { Comment.of(a.getJSONObject(it)) }
                }
                book[key] = posts
            }
        }.onFailure { book.clear() }
    }
    private fun save() {
        val o = JSONObject()
        book.forEach { (key, posts) ->
            val page = JSONObject()
            posts.forEach { (post, list) -> page.put(post, JSONArray().apply { list.forEach { put(it.json()) } }) }
            o.put(key, page)
        }
        DeviceVault.set(KEY, o.toString().toByteArray(Charsets.UTF_8))
    }

    fun comments(post: String, key: String): List<Comment> = synchronized(lock) { ensure(); book[key]?.get(post)?.toList() ?: emptyList() }
    fun count(post: String, key: String): Int = synchronized(lock) { ensure(); book[key]?.get(post)?.size ?: 0 }
    fun has(id: String, post: String, key: String): Boolean = synchronized(lock) { ensure(); book[key]?.get(post)?.any { it.id == id } == true }

    /** A comment comes: kept once by its name, in the order of its moment. False when it was here already. */
    fun put(c: Comment, post: String, key: String): Boolean {
        synchronized(lock) {
            ensure()
            val page = book.getOrPut(key) { mutableMapOf() }
            val list = page.getOrPut(post) { mutableListOf() }
            if (list.any { it.id == c.id }) return false
            list.add(c)
            list.sortBy { it.at }
            if (PER_POST < list.size) repeat(list.size - PER_POST) { list.removeAt(0) }
            if (POSTS_KEPT < page.size) page.keys.sorted().take(page.size - POSTS_KEPT).forEach { page.remove(it) }   // a post's name begins with its birth
            save()
        }
        changed()
        return true
    }

    /** The person leaves: another person's comments are not this one's (iOS montanaSeedForgotten). */
    fun wipe() = synchronized(lock) { book.clear(); loaded = false; DeviceVault.delete(KEY) }
}
