package quest.montana.app

import android.app.Activity
import android.app.KeyguardManager
import android.content.ContextWrapper
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.view.View
import android.view.WindowManager

/**
 * THE OWNER'S WORD (iOS LAContext .deviceOwnerAuthentication): the phone's own lock is asked, a finger, a face or the code,
 * before a secret is shown. The answer is one of three: the owner confirmed; the check did not pass; or the phone has no
 * lock at all. The last one is a refusal too (iOS SeedShowView: «an absent check is a failed check»): a phone anyone can
 * pick up cannot protect the words, so nothing is shown and the person is told why.
 */
enum class OwnerWord { CONFIRMED, FAILED, NO_LOCK }

object OwnerCheck {
    /** Answered by MainActivity.onActivityResult on the road of Android 8–9 (the system's code screen). */
    internal var pending: ((OwnerWord) -> Unit)? = null

    fun ask(act: MainActivity, reason: String, done: (OwnerWord) -> Unit) {
        val km = act.getSystemService(KeyguardManager::class.java)
        if (km == null || !km.isDeviceSecure) { done(OwnerWord.NO_LOCK); return }
        if (Build.VERSION.SDK_INT >= 29) {
            val b = BiometricPrompt.Builder(act).setTitle(reason)
            if (Build.VERSION.SDK_INT >= 30) {
                b.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL)
            } else {
                @Suppress("DEPRECATION") b.setDeviceCredentialAllowed(true)
            }
            // a system that refuses the sheet itself is a check that did not pass, never a fall of the app
            runCatching {
                b.build().authenticate(CancellationSignal(), act.mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) = done(OwnerWord.CONFIRMED)
                    // one finger that does not match is not the end: the sheet stays and asks again; only its closing answers
                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) = done(OwnerWord.FAILED)
                })
            }.onFailure { done(OwnerWord.FAILED) }
        } else {
            @Suppress("DEPRECATION") val intent = km.createConfirmDeviceCredentialIntent(reason, null)
            if (intent == null) { done(OwnerWord.NO_LOCK); return }
            pending = done
            act.confirmOwner(intent)
        }
    }
}

/**
 * A PAGE THAT KEEPS ITS SECRET: while it stands on the screen the window carries FLAG_SECURE, so a screenshot, a recording
 * and the list of recent apps get black instead of the words. Pages can stand on each other, so the flag is counted: it
 * leaves the window only when the last secret page does.
 */
private var secretPages = 0

private fun View.activity(): Activity? {
    var c = context
    while (c is ContextWrapper) { if (c is Activity) return c; c = c.baseContext }
    return null
}

fun View.keepsSecret(): View = apply {
    addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) {
            if (secretPages++ == 0) v.activity()?.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        override fun onViewDetachedFromWindow(v: View) {
            if (--secretPages == 0) v.activity()?.window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    })
}
