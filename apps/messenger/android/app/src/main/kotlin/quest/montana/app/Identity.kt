package quest.montana.app

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The device-only vault (iOS: E2EKeychain.setDeviceOnly — AfterFirstUnlockThisDeviceOnly, not
 * synchronized, not in backups). A value is sealed with AES-256-GCM under a key that lives in the
 * Android Keystore and cannot be exported; the sealed bytes sit in app-private preferences that
 * the manifest keeps out of every system backup and device transfer.
 */
object DeviceVault {
    private const val KEY_ALIAS = "mt.device.vault"
    private const val PREFS = "mt.vault"
    private lateinit var prefs: SharedPreferences

    fun init(ctx: Context) { prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE) }

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return gen.generateKey()
    }

    /** Writes and reads back: true only when the value is really in storage. */
    fun set(name: String, value: ByteArray): Boolean = try {
        val c = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val sealed = c.iv + c.doFinal(value)
        prefs.edit().putString(name, Base64.encodeToString(sealed, Base64.NO_WRAP)).commit()
                && get(name)?.contentEquals(value) == true
    } catch (e: Exception) {
        Log.e("Montana", "vault write refused: ${e.javaClass.simpleName}")
        false
    }

    fun get(name: String): ByteArray? = try {
        prefs.getString(name, null)?.let { s ->
            val sealed = Base64.decode(s, Base64.NO_WRAP)
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, sealed, 0, 12))
            c.doFinal(sealed, 12, sealed.size - 12)
        }
    } catch (e: Exception) {
        Log.e("Montana", "vault read refused: ${e.javaClass.simpleName}")
        null
    }

    fun delete(name: String) { prefs.edit().remove(name).commit() }
    /** Whether a value is stored at all, opened or not: a store that would not open is not an empty one (Groups). */
    fun has(name: String): Boolean = prefs.contains(name)

    /** Bytes sealed under the device key for a file of their own (iv ‖ ciphertext ‖ tag); null when the key refuses. */
    fun seal(value: ByteArray): ByteArray? = try {
        Cipher.getInstance("AES/GCM/NoPadding").run { init(Cipher.ENCRYPT_MODE, key()); iv + doFinal(value) }
    } catch (e: Exception) { null }

    fun unseal(sealed: ByteArray): ByteArray? = try {
        Cipher.getInstance("AES/GCM/NoPadding").run {
            init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, sealed, 0, 12))
            doFinal(sealed, 12, sealed.size - 12)
        }
    } catch (e: Exception) { null }
}

/** What a seed opens (iOS MontanaSeedKeys.Keys): the words and the ML-DSA-65 signing keys. */
class SeedKeys(val mnemonic: String, val pubkey: ByteArray, val seckey: ByteArray) {
    companion object {
        /** 24 words → keys, through the core; null for words the core refuses. */
        fun from(mnemonic: String): SeedKeys? {
            val b = MtBindings.nativeSeedKeys(mnemonic) ?: return null
            if (b.size < MtBindings.PUBKEY + MtBindings.SECKEY) return null
            val pk = b.copyOfRange(0, MtBindings.PUBKEY)
            val sk = b.copyOfRange(MtBindings.PUBKEY, MtBindings.PUBKEY + MtBindings.SECKEY)
            b.fill(0)
            return SeedKeys(mnemonic, pk, sk)
        }

        /** The root is drawn by the core, never by the app (iOS MontanaSeedKeys.generate). */
        fun generate(): SeedKeys? = MtBindings.nativeGenerateMnemonic()?.let { from(it) }
    }
}

/**
 * SINGLE SOURCE OF TRUTH of the active identity (iOS MontanaSeed): the words, in one
 * representation, in the device vault. Everything else is derived from them on use.
 */
object MontanaSeed {
    private const val MN = "mt_active_mnemonic"
    private const val TWIN = "mt.twin.ref"

    val mnemonic: String?
        get() = DeviceVault.get(MN)?.toString(Charsets.UTF_8)?.takeIf { it.isNotEmpty() }

    val hasSeed: Boolean get() = mnemonic != null

    /** The seed must land in storage; false means no identity was created. */
    fun enter(keys: SeedKeys): Boolean {
        clear()
        val stored = DeviceVault.set(MN, keys.mnemonic.toByteArray(Charsets.UTF_8))
        Log.i("Montana", "seed write: words=${keys.mnemonic.split(' ').size} stored=$stored (value not logged)")
        return stored
    }

    fun clear() {
        DeviceVault.delete(MN)
        DeviceVault.delete(TWIN)
        NodeIdentity.forget()   // a machine's value outliving the person would join the two for anyone listening (iOS MontanaOverlayKey.forget)
        NodeKem.forget()
        Channels.forget()
    }

    /**
     * The person's own reference (iOS MontanaSeed.twin): the owner branch of the seed,
     * `mt_mldsa_seed_for_role(master, "mt-owner-key")`, filed under the first sixteen bytes of
     * its SHA-256 in hex (MTPipeBook.reference). Never leaves the device.
     */
    val twin: String?
        get() {
            DeviceVault.get(TWIN)?.toString(Charsets.UTF_8)?.takeIf { it.isNotEmpty() }?.let { return it }
            val m = mnemonic ?: return null
            val master = MtBindings.nativeMnemonicToMasterSeed(m) ?: return null
            val owner = MtBindings.nativeRoleSeed(master, "mt-owner-key")
            master.fill(0)
            owner ?: return null
            val ref = MessageDigest.getInstance("SHA-256").digest(owner).copyOfRange(0, 16)
                .joinToString("") { "%02x".format(it) }
            owner.fill(0)
            DeviceVault.set(TWIN, ref.toByteArray(Charsets.UTF_8))
            return ref
        }
}

/**
 * The call sign of a person who has claimed no name (iOS MontanaCallsign): a row of
 * callsigns.tsv picked by a fold of the reference, read in the device's language.
 */
object Callsign {
    private class Row(val en: String, val ru: String, val zh: String, val emoji: String)
    @Volatile private var rows: List<Row> = emptyList()

    private fun table(ctx: Context): List<Row> {
        if (rows.isNotEmpty()) return rows
        val text = ctx.resources.openRawResource(R.raw.callsigns).bufferedReader(Charsets.UTF_8).readText()
        rows = text.split('\n').filter { it.isNotEmpty() && !it.startsWith("#") }.mapNotNull { line ->
            val f = line.split('\t')
            if (f.size < 5) null else Row(f[1], f[2], f[4], if (f.size >= 6) f[5] else "")
        }
        return rows
    }

    private fun named(r: Row, lang: String): String {
        val word = when { lang.startsWith("ru") -> r.ru; lang.startsWith("zh") -> r.zh; else -> r.en }
        return if (r.emoji.isEmpty()) word else r.emoji + " " + word
    }

    private fun lang(ctx: Context) = ctx.resources.configuration.locales[0].language.lowercase()

    fun all(ctx: Context): List<String> = table(ctx).map { named(it, lang(ctx)) }

    /** The same fold as iOS: sum = sum*31 + byte over the first 8 UTF-8 bytes, UInt32 wrapping. */
    fun of(ctx: Context, reference: String): String {
        val t = table(ctx)
        if (t.isEmpty() || reference.isEmpty()) return ""
        var sum = 0
        for (b in reference.toByteArray(Charsets.UTF_8).take(8)) sum = sum * 31 + (b.toInt() and 0xff)
        val idx = (sum.toUInt() % t.size.toUInt()).toInt()
        return named(t[idx], lang(ctx))
    }
}

/** Settings of the person that are not secrets (iOS UserDefaults / @AppStorage). */
object Prefs {
    private lateinit var p: SharedPreferences
    fun init(ctx: Context) { p = ctx.getSharedPreferences("mt.defaults", Context.MODE_PRIVATE) }

    const val TERMS_VERSION = 1
    var termsAccepted: Boolean
        get() = p.getInt("termsAcceptedVersion", 0) >= TERMS_VERSION
        set(v) { p.edit().putInt("termsAcceptedVersion", if (v) TERMS_VERSION else 0).apply() }

    var userName: String
        get() = p.getString("userName", "") ?: ""
        set(v) { p.edit().putString("userName", v).apply() }

    /** The notifications question was asked once (iOS MontanaNotifyGate.asked, "mt.notify.asked"). */
    var notifyAsked: Boolean
        get() = p.getBoolean("mt.notify.asked", false)
        set(v) { p.edit().putBoolean("mt.notify.asked", v).apply() }

    /** The appearance's own settings, under the iOS UserDefaults keys (bubbleStyle, cbMineFill1, noteQuality…). */
    fun str(key: String, def: String): String = p.getString(key, def) ?: def
    fun setStr(key: String, v: String) { p.edit().putString(key, v).apply() }
    fun dbl(key: String, def: Double): Double = if (p.contains(key)) p.getFloat(key, def.toFloat()).toDouble() else def
    fun setDbl(key: String, v: Double) { p.edit().putFloat(key, v.toFloat()).apply() }
    fun bool(key: String, def: Boolean): Boolean = p.getBoolean(key, def)
    fun setBool(key: String, v: Boolean) { p.edit().putBoolean(key, v).apply() }
    fun remove(vararg keys: String) { p.edit().apply { keys.forEach { remove(it) } }.apply() }

    fun forgetPerson() { p.edit().clear().commit() }
}
