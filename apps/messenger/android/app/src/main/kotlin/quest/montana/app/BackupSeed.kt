package quest.montana.app

import android.app.backup.BackupAgent
import android.app.backup.BackupDataInput
import android.app.backup.BackupDataOutput
import android.app.backup.BackupManager
import android.content.Context
import android.os.ParcelFileDescriptor
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.UUID

/**
 * THE SEED OF THE BACKUP — the Android twin of iOS MontanaAppleID (the author's word 28.09: «sign in by the
 * account, on every device of the account»). The platform's own carrier is the system backup — the Google Account's
 * on most phones (sealed end to end under a key the screen lock opens, Android 9+, much as the iCloud Keychain is),
 * Seedvault on GrapheneOS. The words ride there ONLY when the system says the copy is sealed on the device, or when
 * they go phone to phone directly; a new phone finds them at install, before a word is typed, and the first screen
 * offers «Continue from your backup».
 *
 * What stays as it was: the ACTIVE seed lives device-only in the vault (Identity.kt) and nothing here writes over it.
 * A carried seed is a second reading of the same words, opened only by the person's tap.
 *
 * ONE RECORD PER INSTALLATION, as on iOS: every installation writes a record of its own, named by a name drawn once
 * here and never carried; «Forget this device» withdraws this installation's record alone.
 */
object MontanaBackupID {
    private const val SWITCH = "mt.backup.signin"       // the person's switch, standing by default (iOS mt.apple.signin)
    private const val RECORD = "mt.backup.signin.id"    // this installation's record name, this device's own
    private const val CARRIED = "mt.backup.carried"     // what the account brought to this phone, sealed in the vault
    const val KEY_PREFIX = "seed."

    class Carried(val words: String, val at: Long, val devices: Int)

    private fun prefs(c: Context) = c.getSharedPreferences("mt.backup", Context.MODE_PRIVATE)

    fun on(c: Context) = prefs(c).getBoolean(SWITCH, true)

    /** The switch on the Privacy page (iOS MontanaAppleID.set(on:)): the system is told, and the agent writes or leaves out the words. */
    fun setOn(c: Context, v: Boolean) { prefs(c).edit().putBoolean(SWITCH, v).commit(); publish(c) }

    /** The name of this installation's record: drawn once, never in a copy, so a reinstall writes a new one. */
    fun ownRecord(c: Context): String {
        val p = prefs(c)
        p.getString(RECORD, null)?.let { return KEY_PREFIX + it }
        val id = UUID.randomUUID().toString()
        p.edit().putString(RECORD, id).commit()
        return KEY_PREFIX + id
    }

    /** The seed changed or left: the system is told, and the agent writes what stands now. */
    fun publish(c: Context) = BackupManager(c).dataChanged()

    /** «Forget this device»: this installation's name leaves, so its record leaves the copy at the next backup. */
    fun withdrawOwn(c: Context) {
        prefs(c).edit().remove(RECORD).commit()
        publish(c)
    }

    /** The seeds the account brought to this phone, each once, the newest first. */
    fun held(): List<Carried> {
        val raw = DeviceVault.get(CARRIED)?.toString(Charsets.UTF_8) ?: return emptyList()
        return runCatching {
            val a = JSONArray(raw)
            (0 until a.length()).map { a.getJSONObject(it) }
                .map { Carried(it.getString("w"), it.optLong("t"), it.optInt("n", 1)) }
                .sortedByDescending { it.at }
        }.getOrDefault(emptyList())
    }

    /** Records arriving from the account (the agent's restore): kept sealed, each seed once, counting its devices. */
    internal fun keep(records: List<Pair<String, Long>>) {
        val by = LinkedHashMap<String, Carried>()
        for (c in held()) by[c.words] = c
        for ((w, t) in records) {
            val was = by[w]
            by[w] = if (was == null) Carried(w, t, 1) else Carried(w, maxOf(was.at, t), was.devices + 1)
        }
        val a = JSONArray()
        by.values.forEach { a.put(JSONObject().put("w", it.words).put("t", it.at).put("n", it.devices)) }
        DeviceVault.set(CARRIED, a.toString().toByteArray(Charsets.UTF_8))
    }
}

/**
 * The system's backup agent: it hands the account this installation's record, and takes the account's records
 * back at install. Only the words, only sealed end to end (or phone to phone); nothing else of the app is copied.
 */
class SeedBackupAgent : BackupAgent() {
    override fun onCreate() {
        DeviceVault.init(this)
        Prefs.init(this)
    }

    override fun onBackup(oldState: ParcelFileDescriptor?, data: BackupDataOutput, newState: ParcelFileDescriptor) {
        val sealed = (data.transportFlags and FLAG_CLIENT_SIDE_ENCRYPTION_ENABLED) != 0 ||
                     (data.transportFlags and FLAG_DEVICE_TO_DEVICE_TRANSFER) != 0
        val before = readState(oldState)
        val now = HashMap<String, ByteArray>()
        val words = MontanaSeed.mnemonic
        if (sealed && words != null && MontanaBackupID.on(this)) {
            now[MontanaBackupID.ownRecord(this)] =
                JSONObject().put("w", words).put("t", System.currentTimeMillis()).toString().toByteArray(Charsets.UTF_8)
        }
        for ((k, v) in now) { data.writeEntityHeader(k, v.size); data.writeEntityData(v, v.size) }
        for (k in before - now.keys) data.writeEntityHeader(k, -1)   // a record withdrawn leaves the copy
        writeState(newState, now.keys)
        Log.i("Montana", "backup_id backup sealed=$sealed records=${now.size} withdrawn=${(before - now.keys).size}")
    }

    override fun onRestore(data: BackupDataInput, appVersionCode: Int, newState: ParcelFileDescriptor) {
        val got = ArrayList<Pair<String, Long>>()
        while (data.readNextHeader()) {
            val key = data.key
            val buf = ByteArray(data.dataSize)
            data.readEntityData(buf, 0, buf.size)
            if (!key.startsWith(MontanaBackupID.KEY_PREFIX)) continue
            runCatching { JSONObject(String(buf, Charsets.UTF_8)) }.getOrNull()?.let { o ->
                val w = o.optString("w")
                if (w.split(' ').size == 24) got += w to o.optLong("t")
            }
            buf.fill(0)
        }
        if (got.isNotEmpty()) MontanaBackupID.keep(got)
        writeState(newState, emptySet())   // the restored records are the other devices'; this one has written none yet
        Log.i("Montana", "backup_id restore records=${got.size}")
    }

    private fun readState(fd: ParcelFileDescriptor?): Set<String> = runCatching {
        // the state files are the system's: read and written, never closed here
        val i = DataInputStream(FileInputStream(fd!!.fileDescriptor))
        (0 until i.readInt()).map { i.readUTF() }.toSet()
    }.getOrDefault(emptySet())

    private fun writeState(fd: ParcelFileDescriptor, keys: Set<String>) {
        val o = DataOutputStream(FileOutputStream(fd.fileDescriptor))
        o.writeInt(keys.size); keys.forEach { o.writeUTF(it) }; o.flush()
    }
}
