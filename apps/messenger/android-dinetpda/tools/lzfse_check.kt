// THE KOTLIN SIDE OF tools/lzfse_check.sh: every <name>.ref (the reference CLI's stream of <name>.bin) and <name>.v1 (the same with its
// bvx2 headers laid as bvx1) must open to <name>.bin; every <name>.bin is encoded into <name>.kt for the reference to open and must
// open here too; every damaged <name>.cut must be refused or opened, never thrown; a bound must be kept.
import quest.montana.app.Lzfse
import java.io.File

fun main(args: Array<String>) {
    val dir = File(args[0])
    var ok = 0
    var bad = 0
    var refused = 0
    var rawIn = 0L
    var refOut = 0L
    var ktOut = 0L
    fun check(what: String, good: Boolean) { if (good) ok++ else { bad++; println("FAIL $what") } }
    for (f in dir.listFiles()!!.sortedBy { it.name }) {
        val name = f.name
        when {
            name.endsWith(".ref") || name.endsWith(".v1") -> {
                val plain = File(dir, name.substringBeforeLast('.') + ".bin").readBytes()
                val got = Lzfse.decode(f.readBytes())
                check("decode $name", got != null && got.contentEquals(plain))
                if (name.endsWith(".ref")) { rawIn += plain.size; refOut += f.length() }
            }
            name.endsWith(".bin") -> {
                val plain = f.readBytes()
                val enc = Lzfse.encode(plain)
                File(dir, name.removeSuffix(".bin") + ".kt").writeBytes(enc)
                ktOut += enc.size
                val back = Lzfse.decode(enc)
                check("self $name", back != null && back.contentEquals(plain))
                if (1000 < plain.size) check("bound $name", Lzfse.decode(enc, max = plain.size - 1) == null)
            }
            name.endsWith(".cut") -> {
                val got = try { Lzfse.decode(f.readBytes()) } catch (e: Throwable) { check("refuse $name threw " + e.javaClass.simpleName, false); continue }
                if (got == null) refused++
                ok++
            }
        }
    }
    println("kotlin: ok=$ok bad=$bad damaged_refused=$refused bytes=$rawIn reference=$refOut kotlin=$ktOut")
    if (bad != 0) System.exit(1)
}
