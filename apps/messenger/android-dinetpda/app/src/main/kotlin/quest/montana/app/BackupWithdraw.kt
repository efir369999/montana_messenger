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
 * THE SYSTEM BACKUP CARRIES NO WORDS (core/docs/Montana Identity.md:343, conformance item 17: the words stay out of backups
 * and out of every path that leaves the device; iOS MontanaAppleID: the account carries no seed). No file of the app is
 * copied (AndroidManifest.xml: fullBackupContent=false, every domain excluded), and this agent writes no record, reads
 * none and offers none: an identity opens by its 24 words alone.
 *
 * Builds before this one could write a record of the words into the system backup when the person turned that on in
 * Privacy. Such an installation still holds that build's switch or record name: at launch it asks the system for a
 * backup, and that backup withdraws every record the build before wrote, so the copy no longer holds the words. The
 * words on this device are not touched.
 */
object BackupWithdraw {
    // the names the builds before kept: the person's switch and this installation's record name
    private const val SWITCH = "mt.backup.signin"
    private const val RECORD = "mt.backup.signin.id"

    private fun prefs(c: Context) = c.getSharedPreferences("mt.backup", Context.MODE_PRIVATE)

    /** At launch: while a build before may have left a record in the copy, the system is asked for the backup that withdraws it. */
    fun atLaunch(c: Context) {
        val p = prefs(c)
        if (p.contains(SWITCH) || p.contains(RECORD)) BackupManager(c).dataChanged()
    }

    /** The copy holds no record of this installation: the old names leave, and no backup is asked for again. */
    internal fun settled(c: Context) { prefs(c).edit().remove(SWITCH).remove(RECORD).commit() }
}

/**
 * The system's backup agent: it writes nothing, takes nothing at install, and withdraws every record the last backup held,
 * the record of the words a build before wrote among them.
 */
class WithdrawBackupAgent : BackupAgent() {
    override fun onBackup(oldState: ParcelFileDescriptor?, data: BackupDataOutput, newState: ParcelFileDescriptor) {
        val before = readState(oldState)
        for (k in before) data.writeEntityHeader(k, -1)   // a record withdrawn leaves the copy
        writeState(newState, emptySet())
        if (before.isEmpty()) BackupWithdraw.settled(this)   // the last backup already held nothing: nothing is left to withdraw
        Log.i("Montana", "backup_id backup records=0 withdrawn=${before.size}")
    }

    override fun onRestore(data: BackupDataInput, appVersionCode: Int, newState: ParcelFileDescriptor) {
        var skipped = 0
        while (data.readNextHeader()) { data.skipEntityData(); skipped++ }   // a record a build before wrote is not read
        writeState(newState, emptySet())
        Log.i("Montana", "backup_id restore records=0 skipped=$skipped")
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
