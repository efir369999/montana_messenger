package quest.montana.app

import android.app.backup.BackupAgent
import android.app.backup.BackupDataInput
import android.app.backup.BackupDataOutput
import android.app.backup.BackupManager
import android.content.Context
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.FileInputStream
import java.io.FileOutputStream

/**
 * NO DOOR BY THE ACCOUNT (iOS e69c9b6d, P-168, the author's word 10.10: «restore by the Apple account -- eradicate it
 * wholly, everywhere»; Montana Identity.md:343, item 17: the words stay out of backups and of every path that leaves the
 * device). The seed is opened by its 24 words alone: the switch «Identity in Google Account» and the door «Continue from
 * your backup» are gone, and the system backup carries nothing of Montana.
 *
 * What is kept is the withdrawal: a build before wrote this installation's record of the words into the Google Account's
 * backup, and only this installation's agent can take it out. So the agent stays, writes nothing, and withdraws at the
 * next backup every record it once wrote (iOS MontanaAppleID.withdrawOwn).
 */
object MontanaBackupID {
    private const val RETIRED = "mt.backup.retired"     // NOT-UI: this installation has dropped the old switch and asked the withdrawal
    private const val CARRIED = "mt.backup.carried"     // what the account brought to this phone, sealed in the vault (retired)
    const val KEY_PREFIX = "seed."

    private fun prefs(c: Context) = c.getSharedPreferences("mt.backup", Context.MODE_PRIVATE)

    /** At launch, once (iOS MTRetired): the old switch and its record name leave, the carried words leave the vault,
     *  and the system is told, so the agent withdraws what it wrote. */
    fun retire(c: Context) {
        val p = prefs(c)
        if (p.getBoolean(RETIRED, false)) return
        p.edit().clear().putBoolean(RETIRED, true).commit()
        DeviceVault.delete(CARRIED)
        withdraw(c)
        Log.i("Montana", "backup_id retired")
    }

    /** «Forget this device», or the retirement: the agent runs again and withdraws every record it once wrote. */
    fun withdraw(c: Context) = BackupManager(c).dataChanged()
}

/**
 * The system's backup agent: it writes nothing, takes nothing back at install, and withdraws every record this
 * installation wrote before (the names its state file keeps).
 */
class SeedBackupAgent : BackupAgent() {
    override fun onBackup(oldState: ParcelFileDescriptor?, data: BackupDataOutput, newState: ParcelFileDescriptor) {
        val before = readState(oldState)
        for (k in before) data.writeEntityHeader(k, -1)   // a record withdrawn leaves the copy
        writeState(newState, emptySet())
        Log.i("Montana", "backup_id backup records=0 withdrawn=${before.size}")
    }

    override fun onRestore(data: BackupDataInput, appVersionCode: Int, newState: ParcelFileDescriptor) {
        // the account's old records are other devices' words: none is read into this phone
        var n = 0
        while (data.readNextHeader()) { data.skipEntityData(); n++ }
        writeState(newState, emptySet())
        Log.i("Montana", "backup_id restore skipped=$n")
    }

    private fun readState(fd: ParcelFileDescriptor?): Set<String> = runCatching {
        // the state files are the system's: read and written, never closed here
        val i = DataInputStream(FileInputStream(fd!!.fileDescriptor))
        (0 until i.readInt()).map { i.readUTF() }.filter { it.startsWith(MontanaBackupID.KEY_PREFIX) }.toSet()
    }.getOrDefault(emptySet())

    private fun writeState(fd: ParcelFileDescriptor, keys: Set<String>) {
        val o = DataOutputStream(FileOutputStream(fd.fileDescriptor))
        o.writeInt(keys.size); keys.forEach { o.writeUTF(it) }; o.flush()
    }
}
