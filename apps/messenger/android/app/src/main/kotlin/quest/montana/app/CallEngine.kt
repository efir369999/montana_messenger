package quest.montana.app

import android.content.Context
import android.util.Log
import org.webrtc.DefaultVideoDecoderFactory
import org.webrtc.DefaultVideoEncoderFactory
import org.webrtc.EglBase
import org.webrtc.PeerConnectionFactory

/**
 * THE CALL ENGINE (iOS MontanaCall's factory over webrtc-sdk, MontanaCall.swift 787-791): one factory for the app's life, born
 * when the app stands, as iOS makes it in the call machine's init at launch. Here it is made off the main thread, so the
 * engine's twelve megabytes never stand between the person and the first screen. The call itself is mapped in docs/calls.md.
 */
object CallEngine {
    // iOS RTCInitFieldTrialDictionary: the first pair that works is taken at once, not after a dampening wait
    private const val TRIALS = "WebRTC-IceFieldTrials/initial_select_dampening:0/"
    private val gate = Any()
    @Volatile var factory: PeerConnectionFactory? = null
        private set
    @Volatile var egl: EglBase? = null
        private set

    fun warm(c: Context) {
        if (factory != null) return
        val app = c.applicationContext
        Thread {
            synchronized(gate) {
                if (factory != null) return@Thread
                val t0 = System.currentTimeMillis()
                runCatching {
                    PeerConnectionFactory.initialize(
                        PeerConnectionFactory.InitializationOptions.builder(app).setFieldTrials(TRIALS).createInitializationOptions())
                    // iOS RTCDefaultVideoEncoderFactory / RTCDefaultVideoDecoderFactory: the phone's own codecs first
                    val e = EglBase.create()
                    factory = PeerConnectionFactory.builder()
                        .setVideoEncoderFactory(DefaultVideoEncoderFactory(e.eglBaseContext, true, true))
                        .setVideoDecoderFactory(DefaultVideoDecoderFactory(e.eglBaseContext))
                        .createPeerConnectionFactory()
                    egl = e
                    Log.d("Montana", "call engine: ready in " + (System.currentTimeMillis() - t0) + " ms")
                }.onFailure { Log.e("Montana", "call engine: " + it.javaClass.simpleName + " " + it.message) }
            }
        }.start()
    }
}
