package quest.montana.app

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File

// ─────────────────────────── the camera beside the photos (iOS MTGalleryPick's camera tile → CameraPicker) ───────────────────────────

/**
 * THE CAMERA'S OWN DOOR (the platform's ContentProvider, no library): the system camera is handed one address to write its
 * picture or its film into — a file in this app's cache folder «capture» — and the app reads it back from the same address.
 * Only names this app minted answer; nothing else of the app is reachable through it.
 */
class CaptureProvider : ContentProvider() {
    override fun onCreate() = true
    private fun fileOf(uri: Uri): File? {
        val c = context ?: return null
        val name = uri.lastPathSegment ?: return null
        if (!name.startsWith("cap-") || name.contains('/')) return null
        return File(Capture.dir(c), name)
    }
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        val f = fileOf(uri) ?: return null
        return if (mode.contains('w')) ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_WRITE_ONLY or ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_TRUNCATE)
               else ParcelFileDescriptor.open(f.takeIf { it.exists() } ?: return null, ParcelFileDescriptor.MODE_READ_ONLY)
    }
    override fun getType(uri: Uri): String? =
        uri.lastPathSegment?.substringAfterLast('.', "")?.let { MimeTypeMap.getSingleton().getMimeTypeFromExtension(it.lowercase()) }
    override fun query(uri: Uri, p: Array<out String>?, s: String?, a: Array<out String>?, o: String?): Cursor? {
        val f = fileOf(uri)?.takeIf { it.exists() } ?: return null
        return android.database.MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)).apply { addRow(arrayOf<Any>(f.name, f.length())) }
    }
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, s: String?, a: Array<out String>?) = 0
    override fun update(uri: Uri, v: ContentValues?, s: String?, a: Array<out String>?) = 0
}

object Capture {
    fun dir(c: android.content.Context) = File(c.cacheDir, "capture").apply { mkdirs() }

    /**
     * A PICTURE OR A FILM FROM THE SYSTEM CAMERA (iOS UIImagePickerController .camera): the camera app writes into the door's
     * address; back here the address is handed on as a picked file is. The camera permission comes first — an app that
     * declares the camera must hold it to call the system camera. A shot the person dropped answers null.
     */
    fun shoot(act: MainActivity, video: Boolean, done: (Uri?) -> Unit) {
        act.askCamera { granted ->
            if (!granted) { done(null); return@askCamera }
            dir(act).listFiles()?.forEach { it.delete() }   // one shot at a time: the last one's file has been read
            val name = "cap-" + System.currentTimeMillis() + if (video) ".mp4" else ".jpg"
            val uri = Uri.parse("content://${act.packageName}.capture/$name")
            val intent = Intent(if (video) MediaStore.ACTION_VIDEO_CAPTURE else MediaStore.ACTION_IMAGE_CAPTURE)
                .putExtra(MediaStore.EXTRA_OUTPUT, uri)
                .addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            act.captureWith(intent) { ok -> done(if (ok && File(dir(act), name).length() > 0) uri else null) }
        }
    }
}

/**
 * THE CAMERA OR THE PHOTOS (iOS MTGalleryPick: the camera's tile first, then «All photos»): the camera's picture, the camera's
 * film, or the system's own photo picker. The answer: false — a picture, true — a film, null — the picker.
 */
fun cameraOrPhotos(act: MainActivity, done: (Boolean?) -> Unit) {
    android.app.AlertDialog.Builder(act)
        .setItems(arrayOf(act.getString(R.string.cm_photo), act.getString(R.string.cm_video), act.getString(R.string.cm_all))) { _, which ->
            done(when (which) { 0 -> false; 1 -> true; else -> null })
        }
        .setNegativeButton(R.string.cancel, null).show()
}

/**
 * A CONTACT OF THE PHONE AS A LETTER (iOS ContactPicker → «👤 name» and the number under it): read once through the address
 * the picker granted; nothing of the phone's book is kept.
 */
fun contactLetter(c: android.content.Context, uri: Uri): String? = runCatching {
    c.contentResolver.query(uri, arrayOf(android.provider.ContactsContract.Contacts.DISPLAY_NAME, android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER), null, null, null)?.use { cur ->
        if (!cur.moveToFirst()) return@use null
        val name = cur.getString(0).orEmpty().trim()
        val phone = cur.getString(1).orEmpty().trim()
        "👤 " + name.ifEmpty { c.getString(R.string.contact) } + if (phone.isEmpty()) "" else "\n" + phone   // USER-DATA: the contact
    }
}.getOrNull()
