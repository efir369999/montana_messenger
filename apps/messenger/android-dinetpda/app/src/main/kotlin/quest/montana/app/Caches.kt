package quest.montana.app

/**
 * ONE OWNER OF EVERY PICTURE CACHE (iOS MontanaCaches, MontanaApp.swift:1280-1307 at 2155; atom 542558a36f0e): a cache of pictures is
 * named here as it is born and emptied only by the person's Clear in Data and Storage (the author 03.10: a cache let go at the door
 * brought a photo back black on return). Each stays bounded by its own size meanwhile.
 */
object Caches {
    private val drops = ArrayList<Pair<String, () -> Unit>>()
    fun <T : android.util.LruCache<*, *>> kept(name: String, cache: T): T { register(name) { cache.evictAll() }; return cache }
    @Synchronized fun register(name: String, drop: () -> Unit) { drops.add(name to drop) }
    /** Every cache emptied; the number of them, for the diary. */
    fun dropAll(): Int {
        val all = synchronized(this) { drops.toList() }
        for ((_, d) in all) d()
        return all.size
    }
}
