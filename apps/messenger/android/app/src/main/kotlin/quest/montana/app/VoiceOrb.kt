package quest.montana.app

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.Switch
import org.json.JSONObject
import kotlin.math.cos
import kotlin.math.pow

/*
 * THE VOICE ORB (iOS MTVoiceBuble.swift + MTVoiceOrb.metal at 2155, atom 9b1fba189aa1): the liquid ball of a voice, the
 * same shader, the same seed, the same motion. At 2155 the orb lives only in Settings → Appearance → Voice message style
 * (MontanaSettings.swift:1097-1105, MontanaVoiceOrbStyleView): the hold that recorded over it (MontanaVoiceRecordHold) is
 * defined but drawn nowhere since 22a52020 (28.09, «one recording strip»), and the feed's voice is the wave -- as here.
 * The shader is the seed's own style 9 (glsSiriFluid under the glass, orbGlassLiquidAnim and fs_main), carried line by
 * line from Metal into the platform's own AGSL (RuntimeShader, Android 13); the particle ribbon (style 24) is not the
 * seed's and is not carried.
 */

/** iOS orbThinkingUniformSeed: the Uniforms struct of MTVoiceOrb.metal as floats; the colours from index 40, a float4 each. */
private val orbThinkingSeed = floatArrayOf(
    1f, 1f, 0f, 0.36f, 0.72f, 0.36f, 3.2f, 0.5f,
    2.2f, 0.12f, 0.56f, 0.2f, 0.18f, 0.18f, 2f, 9f,
    0.005f, 0f, 0f, 1f, 1f, 0f, 2f, 0.42f,
    0.77f, 0.23f, 65f, 0f, 0f, 1f, 0.22f, 0.25f,
    0.72f, 5f, 0.42f, 1.25f, 0.55f, 0.3f, 1.2f, 0.7f,
    1f, 0.84705883f, 0.41960785f, 1f, 0.50980395f, 0.95686275f, 1f, 1f,
    1f, 0.48235294f, 0.8352941f, 1f, 0.5568628f, 0.42352942f, 1f, 1f,
    1f, 1f, 1f, 1f, 1f, 1f, 1f, 1f,
    0.60784316f, 0.95686275f, 1f, 1f, 0.77254903f, 0.6627451f, 1f, 1f,
    0.91764706f, 0.95686275f, 1f, 1f, 0.8627451f, 0.91764706f, 1f, 1f,
    0.011764706f, 0.015686275f, 0.03529412f, 1f, 0.58431375f, 0.42352942f, 1f, 1f,
    0.96862745f, 0.9843137f, 1f, 1f, 0.9372549f, 0.9647059f, 0.99215686f, 1f,
    0.8784314f, 0.93333334f, 0.9764706f, 1f, 0.83137256f, 0.9019608f, 0.96862745f, 1f,
    0.73333335f, 0.8352941f, 0.9529412f, 1f, 0.6509804f, 0.78039217f, 0.9411765f, 1f,
    0.5294118f, 0.6901961f, 0.92156863f, 1f, 0.43529412f, 0.61960787f, 0.9098039f, 1f,
    0.43529412f, 0.61960787f, 0.9098039f, 1f, 0.43529412f, 0.61960787f, 0.9098039f, 1f,
    0.43529412f, 0.61960787f, 0.9098039f, 1f, 0.43529412f, 0.61960787f, 0.9098039f, 1f,
)

/**
 * THE SHADER (MTVoiceOrb.metal fs_main → orbGlassLiquidAnim → glsSiriFluid, style 9): the uniforms are the seed's own by
 * name; what style 9 never reads (the palette, the metal, the ribbon) is left out, and the style's own constants are
 * written in: glsContourStrength 0.09, glsContourWave's three-wave branch, glsRefractionNormal = the contour's normal,
 * emissionOnly = no glass. The colours ride as plain floats, unconverted, as the Metal pipeline writes them (bgra8Unorm).
 */
private const val ORB_AGSL = """
uniform float2 uSize;
uniform float uTime;
uniform float uSpeed;
uniform float uRadius;
uniform float uZoom;
uniform float uWarp;
uniform float uRidge;
uniform float uShade;
uniform float uSheen;
uniform float uGloss;
uniform float uShellMidA;
uniform float uShellEdgeA;
uniform float uExposure;
uniform float uSoft;
uniform float uGlow;
uniform float uGlass;
uniform float uGlassOp;
uniform float uContour;
uniform float4 uA;
uniform float4 uB;
uniform float4 uC;
uniform float4 uD;
uniform float4 uHi;
uniform float4 uShellIn;
uniform float4 uShellMid;
uniform float4 uShellEdge;
uniform float4 uSheenC;
uniform float4 uSpec;
uniform float4 uCanvas;
uniform float4 uGlowC;

float edgeD(float soft) { return soft - 0.005; }

float3 edgeGlow(float3 col, float2 uv, float rad) {
    if (uGlow <= 0.0) { return col; }
    float r = length(uv);
    float outside = smoothstep(rad - max(uSoft, 0.0005), rad + max(uSoft, 0.0005), r);
    return col + uGlowC.rgb * (uGlow * exp(-max(r - rad, 0.0) * 11.0) * outside);
}

float3 over(float3 dst, float3 src, float a) {
    float k = clamp(a, 0.0, 1.0);
    return src * k + dst * (1.0 - k);
}

float refractionProfile(float t) {
    float d = clamp(t, 0.0, 1.0);
    return 1.0 - sqrt(max(1.0 - (1.0 - d) * (1.0 - d), 0.0));
}

float lobe(float2 n, float2 dir, float cut, float power) {
    return pow(clamp((dot(n, dir) - cut) / max(1.0 - cut, 0.001), 0.0, 1.0), power);
}

float2 contourWave(float a, float t) {
    float w = sin(a * 3.0 + t * 0.62) * 0.52 + sin(a * 5.0 - t * 0.41 + 1.7) * 0.31 + sin(a * 2.0 + t * 0.23 + 3.1) * 0.17;
    float s = cos(a * 3.0 + t * 0.62) * 1.56 + cos(a * 5.0 - t * 0.41 + 1.7) * 1.55 + cos(a * 2.0 + t * 0.23 + 3.1) * 0.34;
    return float2(w, s);
}

float contourScale(float2 uv, float t) {
    if (uContour <= 0.0) { return 1.0; }
    return 1.0 + clamp(uContour, 0.0, 1.0) * 0.09 * contourWave(atan(uv.y, uv.x), t).x;
}

float2 contourNormal(float2 uv, float rad, float t) {
    float d = length(uv);
    if (d <= 0.0001) { return float2(0.0); }
    float2 radial = uv / d;
    float slope = clamp(uContour, 0.0, 1.0) * 0.09 * contourWave(atan(uv.y, uv.x), t).y;
    float2 tangent = float2(-radial.y, radial.x);
    return normalize(radial - tangent * (rad * slope / d));
}

float2 siriBand(float2 q, float drift, float phase, float amp, float mainY, float env, float soft) {
    float y = amp * env * sin(q.x + drift + phase);
    float dl = abs(q.y - y);
    float line = 0.018 / (sqrt(dl * dl + soft * soft) + 0.026);
    float bd = max(0.0, max(q.y - max(mainY, y), min(mainY, y) - q.y));
    return float2(line, 0.018 / (bd + 0.075));
}

float3 siri(float2 p, float t) {
    float2 q = p / (0.74 + uZoom * 0.34);
    float eb = cos(1.5707964 * min(abs(0.9 * q.x), 1.0));
    float env = eb * eb;
    float low = 0.5 + 0.5 * cos(t * 0.37);
    float mid = 0.5 + 0.5 * sin(t * 0.51 + 1.2);
    float high = 0.5 + 0.5 * cos(t * 0.73 + 2.1);
    float drift = t * 2.4;
    float mainAmp = 0.25 + uRidge * 0.075 + low * 0.018;
    float bandAmp = mainAmp + mid * 0.025 + high * 0.018;
    float mainY = mainAmp * env * sin(q.x * 1.1 + drift);
    float sep = 1.85 + uWarp * 0.2 + mid * 0.28;
    float soft = 0.035 + (1.0 - uRidge) * 0.018 + mid * 0.006;
    float2 b0 = siriBand(q, drift, -sep, bandAmp, mainY, env, soft);
    float2 b1 = siriBand(q, drift, -sep * 0.34, bandAmp, mainY, env, soft);
    float2 b2 = siriBand(q, drift, sep * 0.34, bandAmp, mainY, env, soft);
    float2 b3 = siriBand(q, drift, sep, bandAmp, mainY, env, soft);
    float w0 = b0.x + b0.y;
    float w1 = b1.x + b1.y;
    float w2 = b2.x + b2.y;
    float w3 = b3.x + b3.y;
    float total = w0 + w1 + w2 + w3;
    float d0 = w0 * w0;
    float d1 = w1 * w1;
    float d2 = w2 * w2;
    float d3 = w3 * w3;
    float3 spectral = (uA.rgb * d0 + uC.rgb * d1 + uB.rgb * d2 + uD.rgb * d3) / max(d0 + d1 + d2 + d3, 0.0001);
    float energy = (1.0 - exp(-total * 0.58)) * env;
    float md = abs(q.y - mainY);
    float core = exp(-md * md / 0.0028) * env;
    float fill = uGlass > 0.5 ? 1.0 : 0.0;
    float3 color = mix(uD.rgb, uB.rgb, smoothstep(-0.7, 0.7, q.y)) * 0.018 * fill;
    color += spectral * energy * 1.14;
    color += uHi.rgb * core * (0.18 + 0.1 * low);
    color *= mix(smoothstep(0.08, 0.25, energy + core * 0.12), 1.0, fill);
    color = color / (1.0 + color * 0.18);
    if (uGlass > 0.5) {
        color = mix(color, uHi.rgb, uShade * 0.22 * smoothstep(0.15, 1.15, dot(p, float2(-0.32, 0.78))));
    }
    color *= 1.0 - uShade * 0.34 * smoothstep(-0.1, 1.2, dot(p, float2(0.45, -0.62)));
    color *= 1.0 - uShade * 0.22 * smoothstep(0.72, 1.08, length(p));
    return clamp(color, 0.0, 1.0);
}

half4 main(float2 xy) {
    float2 fc = float2(xy.x, uSize.y - xy.y);
    float m = max(min(uSize.x, uSize.y), 1.0);
    float2 uv = (2.0 * fc - uSize) / m;
    float rad = max(uRadius, 0.05);
    float t = uTime * uSpeed;
    bool emissionOnly = uGlass <= 0.5;
    float cRad = rad * contourScale(uv, t);
    float4 orb = float4(0.0);
    if (length(uv) > cRad * (1.01 + edgeD(uSoft))) {
        float3 halo = clamp(edgeGlow(float3(0.0), uv, cRad), 0.0, 1.0);
        orb = float4(halo, max(halo.r, max(halo.g, halo.b)));
    } else {
        float2 p = uv / cRad;
        float pd = length(p);
        float clearFa = 1.0 - smoothstep(0.995, 1.04, pd);
        float2 normal = contourNormal(uv, rad, t);
        float edgeDepth = max(1.0 - pd, 0.0);
        float rw = 0.015 + 0.95 * clamp(uShellMidA, 0.0, 1.0);
        float prof = pow(refractionProfile(edgeDepth / max(rw, 0.001)), 0.68);
        float2 rp = p - normal * (1.6 * clamp(uGlassOp, 0.0, 1.0) * prof);
        float3 fcol = float3(0.0);
        if (clearFa > 0.0) {
            if (uGlass > 0.5) {
                float split = 0.14 * clamp(uGloss, 0.0, 2.0) * clamp(uGlassOp, 0.0, 1.0) * prof;
                fcol = float3(siri(rp - normal * split, t).r, siri(rp, t).g, siri(rp + normal * split, t).b);
            } else {
                fcol = siri(p, t);
            }
        }
        float lum = dot(fcol, float3(0.213, 0.715, 0.072));
        float3 sat = clamp(lum + (fcol - lum) * 1.22, 0.0, 1.0);
        float3 col = over(uCanvas.rgb, sat, 0.99 * clearFa);
        if (emissionOnly) {
            col = sat * smoothstep(0.025, 0.16, max(sat.r, max(sat.g, sat.b)));
        }
        if (uGlass > 0.5) {
            float sw = 0.026 + 0.055 * clamp(uShellEdgeA, 0.0, 1.0);
            float rim = pow((1.0 - smoothstep(0.0, sw, edgeDepth)) * clearFa, 1.8);
            col = over(col, uShellIn.rgb, rim * uGlassOp * 0.45);
            float cool = lobe(normal, normalize(float2(0.84, 0.54)), -0.32, 1.8);
            float warm = lobe(normal, normalize(float2(-0.62, -0.78)), -0.28, 2.0);
            float disp = rim * clamp(uGloss, 0.0, 2.0) * (0.8 + 0.8 * uShellEdgeA);
            col = over(col, uShellMid.rgb, disp * cool);
            col = over(col, uShellEdge.rgb, disp * warm);
            col *= 1.0 - rim * (0.015 + 0.15 * uShellEdgeA) * (0.15 + 0.85 * max(dot(normal, float2(0.45, -0.89)), 0.0));
            float key = rim * lobe(normal, normalize(float2(-0.68, 0.73)), 0.2, 2.8) * clamp(uSheen, 0.0, 2.0) * 1.4;
            float fillL = rim * lobe(normal, normalize(float2(0.74, -0.67)), 0.4, 3.6) * clamp(uSheen, 0.0, 2.0);
            col = over(col, uSheenC.rgb, key);
            col = over(col, uSpec.rgb, fillL);
        }
        float ballA = 1.0 - smoothstep(0.99 - edgeD(uSoft), 1.01 + edgeD(uSoft), pd);
        col = clamp(col * max(uExposure, 0.0), 0.0, 1.0) * ballA;
        float3 fin = clamp(edgeGlow(col, uv, cRad), 0.0, 1.0);
        float emA = max(fin.r, max(fin.g, fin.b));
        orb = float4(fin, emissionOnly ? emA : clamp(max(ballA, emA), 0.0, 1.0));
    }
    float2 q = (2.0 * fc - uSize) / uSize;
    float start = min(mix(cRad, 1.0, 0.5), 1.0 - 2.0 / m);
    float fit = 1.0 - smoothstep(start, 1.0, max(abs(q.x), abs(q.y)));
    return half4(orb * fit);
}
"""

/** ONE SIDE'S STYLE of the voice orb (iOS MontanaVoiceOrbSide): its colour, its motion and its size in the feed. */
data class OrbSide(val hue: Double, val speed: Double, val liquid: Double, val zoom: Double, val exposure: Double,
                   val glass: Double, val fringe: Double, val sheen: Double, val size: Double) {
    fun json(): String = JSONObject().put("hue", hue).put("speed", speed).put("liquid", liquid).put("zoom", zoom)
        .put("exposure", exposure).put("glass", glass).put("fringe", fringe).put("sheen", sheen).put("size", size).toString()
    companion object {
        /** iOS .montana(mine:): the sender keeps the orb's own colours, the peer's is gold (42°). */
        fun montana(mine: Boolean) = OrbSide(if (mine) -1.0 else 42.0, 0.36, 3.2, 0.36, 2.0, 1.0, 0.42, 0.56, 136.0)
        fun of(s: String): OrbSide? = runCatching {
            val o = JSONObject(s)
            OrbSide(o.getDouble("hue"), o.getDouble("speed"), o.getDouble("liquid"), o.getDouble("zoom"), o.getDouble("exposure"),
                o.getDouble("glass"), o.getDouble("fringe"), o.getDouble("sheen"), o.getDouble("size"))
        }.getOrNull()
    }
}

/**
 * THE VOICE ORB'S STYLE (iOS MontanaVoiceOrbStyle): one owner of both sides and of the look, under the iOS keys
 * «voiceOrb.side.mine» / «voiceOrb.side.theirs» (the side as JSON, as iOS encodes it) and «voiceOrb.look».
 */
object VoiceOrbStyle {
    private val listeners = linkedSetOf<() -> Unit>()
    fun listen(f: () -> Unit) { listeners.add(f) }
    fun unlisten(f: () -> Unit) { listeners.remove(f) }
    private fun changed() = listeners.toList().forEach { it() }

    private fun key(mine: Boolean) = "voiceOrb.side." + if (mine) "mine" else "theirs"
    fun side(mine: Boolean): OrbSide = OrbSide.of(Prefs.str(key(mine), "")) ?: OrbSide.montana(mine)
    fun set(mine: Boolean, v: OrbSide) { Prefs.setStr(key(mine), v.json()); changed() }

    /** THE LOOK of a voice message (iOS look): «orb» or «bars» -- the histogram of a music track. */
    var look: String
        get() = Prefs.str("voiceOrb.look", "orb")
        set(v) { Prefs.setStr("voiceOrb.look", v); changed() }
    val histogram: Boolean get() = look == "bars"

    fun reset() { Prefs.remove(key(true), key(false), "voiceOrb.look"); changed() }

    /** The seed for one side (iOS seed(mine:)): the thinking seed with the person's motion and colour on it. */
    fun seed(mine: Boolean): FloatArray {
        val v = side(mine)
        val s = orbThinkingSeed.copyOf()
        s[3] = v.speed.toFloat(); s[6] = v.liquid.toFloat(); s[5] = v.zoom.toFloat(); s[14] = v.exposure.toFloat()
        s[20] = v.glass.toFloat(); s[23] = v.fringe.toFloat(); s[10] = v.sheen.toFloat()
        return if (v.hue < 0) s else tinted(s, v.hue.toFloat())
    }

    /**
     * A TINTED ORB (iOS orbTinted): every colour of the seed keeps its saturation and its light and takes a hue in a band
     * of ±14° around the chosen one, spread by where it stood on the wheel. Gold = 42°.
     */
    private fun tinted(seed: FloatArray, centre: Float): FloatArray {
        val s = seed.copyOf()
        var i = 40
        val hsv = FloatArray(3)
        while (i + 3 < s.size) {
            rgbToHsv(s[i], s[i + 1], s[i + 2], hsv)
            if (hsv[1] > 0.12f) {
                var deg = (centre + 14 * cos(hsv[0] * Math.PI / 90).toFloat()) % 360f
                if (deg < 0) deg += 360f
                hsvToRgb(deg / 360f, hsv[1], hsv[2], s, i)
            }
            i += 4
        }
        return s
    }
    private fun rgbToHsv(r: Float, g: Float, b: Float, out: FloatArray) {
        val mx = maxOf(r, g, b); val mn = minOf(r, g, b); val d = mx - mn
        var h = 0f
        if (d > 0.0001f) {
            h = when (mx) { r -> 60 * (((g - b) / d) % 6); g -> 60 * ((b - r) / d + 2); else -> 60 * ((r - g) / d + 4) }
            if (h < 0) h += 360f
        }
        out[0] = h; out[1] = if (mx > 0) d / mx else 0f; out[2] = mx
    }
    private fun hsvToRgb(h: Float, s: Float, v: Float, out: FloatArray, at: Int) {
        val i = (h * 6).toInt() % 6; val f = h * 6 - (h * 6).toInt()
        val p = v * (1 - s); val q = v * (1 - f * s); val t = v * (1 - (1 - f) * s)
        val (r, g, b) = when (i) { 0 -> Triple(v, t, p); 1 -> Triple(q, v, p); 2 -> Triple(p, v, t); 3 -> Triple(p, q, v); 4 -> Triple(t, p, v); else -> Triple(v, p, q) }
        out[at] = r; out[at + 1] = g; out[at + 2] = b
    }
}

/**
 * THE ORB'S SURFACE (iOS LiquidOrbView + LiquidOrbRenderer): it draws only while it is on screen and asked to move -- a
 * still orb shows one frame and rests; a new seed glides in over 0.65 s (smoothstep; colours mixed in linear light, as
 * orbMixSrgb). `rimRadius` is LiquidOrbView.fullRim: the ball on its frame, room left for the two-pixel feather.
 * Below Android 13 the platform has no runtime shader: the ball is the seed's own canvas with its first colour's glow.
 */
class VoiceOrbView(c: Context, private val mine: Boolean, private val fps: Int = 60, animating: Boolean = true,
                   private val rimRadius: Float = FULL_RIM) : View(c) {
    companion object { const val FULL_RIM = 0.96f; private const val SETTLE = 0.65 }

    var animating = animating
        set(v) { field = v; invalidate() }

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val shader: android.graphics.RuntimeShader? =
        if (Build.VERSION.SDK_INT >= 33) runCatching { android.graphics.RuntimeShader(ORB_AGSL) }
            .onFailure { android.util.Log.w("Montana", "voice_orb shader refused: $it") }.getOrNull() else null
    private var from = VoiceOrbStyle.seed(mine)
    private var target = from
    private val shown = from.copyOf()
    private var glideAt = 0L
    private var gliding = false
    private var motionPhase = 0.0
    private var lastFrame = 0L
    private val restyle: () -> Unit = { setSeed(VoiceOrbStyle.seed(mine)) }

    override fun onAttachedToWindow() { super.onAttachedToWindow(); VoiceOrbStyle.listen(restyle); restyle() }
    override fun onDetachedFromWindow() { VoiceOrbStyle.unlisten(restyle); super.onDetachedFromWindow() }

    /** iOS setState: from what is shown now to the new seed. */
    private fun setSeed(next: FloatArray) {
        if (next.contentEquals(target)) return
        from = sample(SystemClock.uptimeMillis()).copyOf()
        target = next
        glideAt = SystemClock.uptimeMillis(); gliding = true
        invalidate()
    }

    private fun lin(v: Float) = if (v <= 0.04045f) v / 12.92f else ((v + 0.055) / 1.055).pow(2.4).toFloat()
    private fun srgb(v: Float) = if (v <= 0.0031308f) v * 12.92f else (1.055 * v.toDouble().pow(1 / 2.4) - 0.055).toFloat()

    /** iOS sampleTransition: numbers straight, colours through linear light. */
    private fun sample(now: Long): FloatArray {
        if (!gliding) return target.copyInto(shown)
        val raw = ((now - glideAt) / 1000.0 / SETTLE).coerceIn(0.0, 1.0)
        val k = (raw * raw * (3 - 2 * raw)).toFloat()
        for (i in 3 until shown.size) {
            val colour = i >= 40 && (i - 40) % 4 < 3
            shown[i] = if (colour) srgb(lin(from[i]) + (lin(target[i]) - lin(from[i])) * k) else from[i] + (target[i] - from[i]) * k
        }
        if (raw >= 1.0) gliding = false
        return shown
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat(); val h = height.toFloat()
        if (w < 2 || h < 2) return
        val now = SystemClock.uptimeMillis()
        val u = sample(now)
        val dt = if (lastFrame == 0L) 0.0 else ((now - lastFrame) / 1000.0).coerceIn(0.0, 0.1)
        lastFrame = now
        if (animating) motionPhase += dt * maxOf(u[3], 0f)
        val sh = shader
        if (sh != null && canvas.isHardwareAccelerated) {
            sh.setFloatUniform("uSize", w, h)
            sh.setFloatUniform("uTime", (motionPhase / maxOf(u[3], 0.001f)).toFloat())
            sh.setFloatUniform("uSpeed", u[3])
            sh.setFloatUniform("uRadius", rimRadius)
            sh.setFloatUniform("uZoom", u[5]); sh.setFloatUniform("uWarp", u[6]); sh.setFloatUniform("uRidge", u[7])
            sh.setFloatUniform("uShade", u[9]); sh.setFloatUniform("uSheen", u[10]); sh.setFloatUniform("uGloss", u[11])
            sh.setFloatUniform("uShellMidA", u[12]); sh.setFloatUniform("uShellEdgeA", u[13]); sh.setFloatUniform("uExposure", u[14])
            sh.setFloatUniform("uSoft", u[16]); sh.setFloatUniform("uGlow", u[17]); sh.setFloatUniform("uGlass", u[19])
            sh.setFloatUniform("uGlassOp", u[20]); sh.setFloatUniform("uContour", u[21])
            listOf("uA", "uB", "uC", "uD", "uHi", "uShellIn", "uShellMid", "uShellEdge", "uSheenC", "uSpec", "uCanvas", "uGlowC")
                .forEachIndexed { n, name -> val i = 40 + 4 * n; sh.setFloatUniform(name, u[i], u[i + 1], u[i + 2], u[i + 3]) }
            paint.shader = sh
            canvas.drawRect(0f, 0f, w, h, paint)
        } else {
            val r = minOf(w, h) / 2 * rimRadius
            fun col(i: Int, a: Float = 1f) = Color.argb((a * 255).toInt(), (u[i] * 255).toInt().coerceIn(0, 255), (u[i + 1] * 255).toInt().coerceIn(0, 255), (u[i + 2] * 255).toInt().coerceIn(0, 255))
            paint.shader = RadialGradient(w / 2, h / 2, r, intArrayOf(col(40, 0.55f), col(80)), floatArrayOf(0f, 1f), Shader.TileMode.CLAMP)
            canvas.drawCircle(w / 2, h / 2, r, paint)
        }
        if ((animating || gliding) && isAttachedToWindow) postInvalidateDelayed((1000L / fps).coerceAtLeast(1))
    }
}

/**
 * THE STYLE PAGE OF THE VOICE ORB (iOS MontanaVoiceOrbStyleView, Settings → Appearance → Voice message style): the look
 * first -- the orb or the histogram --, both orbs at the top (a tap chooses the side, the chosen one wears the accent's
 * ring), every knob of the seed below for that side; then «Reset to Montana». iOS takes the colour from the system's
 * colour picker and keeps only its hue; Android has no picker of its own, so the hue is chosen on its own slider.
 */
class VoiceOrbStylePage(private val act: MainActivity, private val onClose: () -> Unit) {
    val view: View
    private var editingMine = true
    private val heads = LinearLayout(act).apply { orientation = LinearLayout.VERTICAL }
    private val knobs = LinearLayout(act).apply { orientation = LinearLayout.VERTICAL }

    init {
        val c: Context = act
        val list = c.vstack(Gravity.NO_GRAVITY) {
            setPadding(dp(16), 0, dp(16), dp(24))
            addView(knobs, lp())
            addView(View(c), lp(MATCH, dp(20)))
            addView(c.plate {
                addView(c.text(c.getString(R.string.reset_montana), 16f, Color.WHITE).apply {
                    setPadding(dp(16), dp(13), dp(16), dp(13)); pressable { VoiceOrbStyle.reset(); fill() }
                }, lp())
            }, lp())
        }
        view = FrameLayout(c).apply {
            setBackgroundColor(Color.BLACK)
            addView(CrestGround(c), FrameLayout.LayoutParams(MATCH, MATCH))
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(c.topBar(c.getString(R.string.vo_style), onBack = onClose))
                addView(segmented(c, listOf(R.string.vo_orb to "orb", R.string.vo_histogram to "bars"), VoiceOrbStyle.look) {
                    VoiceOrbStyle.look = it; fill()
                }, lp().apply { setMargins(dp(16), dp(12), dp(16), 0) })
                addView(heads, lp())
                addView(ScrollView(c).apply { addView(list) }, lp(MATCH, 0, 1f))
            }, FrameLayout.LayoutParams(MATCH, MATCH))
        }
        fill()
    }

    private fun fill() {
        val c: Context = act
        heads.removeAllViews(); knobs.removeAllViews()
        if (VoiceOrbStyle.histogram) {
            heads.addView(c.text(c.getString(R.string.vo_histogram_note), 12f, MT.gray, center = true).apply {
                setPadding(dp(24), dp(14), dp(24), dp(14))
            }, lp())
            return
        }
        heads.addView(c.hstack {
            gravity = Gravity.CENTER
            setPadding(0, dp(14), 0, 0)
            addView(orb(mine = false, R.string.vo_theirs))
            gap(28)
            addView(orb(mine = true, R.string.vo_mine))
        }, lp())
        heads.addView(c.text(c.getString(R.string.vo_tap_hint), 11f, MT.gray, center = true).apply { setPadding(0, dp(8), 0, dp(8)) }, lp())
        val side = VoiceOrbStyle.side(editingMine)
        fun put(v: OrbSide) = VoiceOrbStyle.set(editingMine, v)
        knobs.addView(header(if (editingMine) R.string.vo_mine else R.string.vo_theirs))
        knobs.addView(c.plate {
            addView(c.hstack {
                setPadding(dp(16), dp(8), dp(16), dp(8))
                val sw = Switch(c).apply {
                    isChecked = side.hue < 0
                    thumbTintList = ColorStateList.valueOf(Color.WHITE)
                    trackTintList = ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()), intArrayOf(MT.green, Color.rgb(57, 57, 61)))
                    contentDescription = c.getString(R.string.vo_own_colours)
                    setOnCheckedChangeListener { _, on -> put(VoiceOrbStyle.side(editingMine).copy(hue = if (on) -1.0 else 42.0)); fill() }
                }
                addView(c.text(c.getString(R.string.vo_own_colours), 16f), lp(0, WRAP, 1f))
                addView(sw)
            }, lp())
            if (side.hue >= 0) {
                divider()
                addView(hueRow(side.hue) { h -> put(VoiceOrbStyle.side(editingMine).copy(hue = h)) }, lp())
            }
            divider()
            addView(knob(R.string.vo_size, side.size, 100.0, 200.0) { put(VoiceOrbStyle.side(editingMine).copy(size = it)) }, lp())
        }, lp())
        knobs.addView(header(R.string.vo_motion))
        knobs.addView(c.plate {
            addView(knob(R.string.vo_speed, side.speed, 0.05, 1.5) { put(VoiceOrbStyle.side(editingMine).copy(speed = it)) }, lp())
            addView(knob(R.string.vo_liquid, side.liquid, 0.0, 6.0) { put(VoiceOrbStyle.side(editingMine).copy(liquid = it)) }, lp())
            addView(knob(R.string.vo_zoom, side.zoom, 0.1, 1.0) { put(VoiceOrbStyle.side(editingMine).copy(zoom = it)) }, lp())
            addView(knob(R.string.vo_exposure, side.exposure, 0.5, 4.0) { put(VoiceOrbStyle.side(editingMine).copy(exposure = it)) }, lp())
            addView(knob(R.string.vo_glass, side.glass, 0.0, 1.0) { put(VoiceOrbStyle.side(editingMine).copy(glass = it)) }, lp())
            addView(knob(R.string.vo_fringe, side.fringe, 0.0, 1.5) { put(VoiceOrbStyle.side(editingMine).copy(fringe = it)) }, lp())
            addView(knob(R.string.vo_sheen, side.sheen, 0.0, 1.0) { put(VoiceOrbStyle.side(editingMine).copy(sheen = it)) }, lp())
        }, lp())
    }

    /** One of the two orbs at the top (iOS orb(mine:)): 120 points, 30 frames a second, the chosen one ringed. */
    private fun orb(mine: Boolean, word: Int): View {
        val c: Context = act
        val chosen = editingMine == mine
        return c.vstack {
            addView(FrameLayout(c).apply {
                setPadding(dp(6), dp(6), dp(6), dp(6))
                if (chosen) foreground = GradientDrawable().apply { shape = GradientDrawable.OVAL; setStroke(dp(2.5f), Color.WHITE) }
                addView(VoiceOrbView(c, mine, fps = 30), FrameLayout.LayoutParams(dp(120), dp(120)))
            }, lp(WRAP, WRAP))
            addView(c.text(c.getString(word), 12f, if (chosen) Color.WHITE else MT.gray), lp(WRAP, WRAP).apply { topMargin = dp(0) })
            contentDescription = c.getString(word)
            pressable { if (editingMine != mine) { editingMine = mine; fill() } }
        }
    }

    private fun header(word: Int) = act.text(act.getString(word), 13f, MT.gray).apply { setPadding(act.dp(16), act.dp(20), act.dp(16), act.dp(6)) }

    /** A slider over one number of the side (iOS slider(_:_:_:)): the caption above, the platform's SeekBar in white. */
    private fun knob(word: Int, value: Double, lo: Double, hi: Double, onChange: (Double) -> Unit): View {
        val c: Context = act
        return c.vstack(Gravity.NO_GRAVITY) {
            setPadding(dp(16), dp(10), dp(16), dp(6))
            addView(c.text(c.getString(word), 12f, MT.gray))
            addView(SeekBar(c).apply {
                max = 1000
                progress = (((value.coerceIn(lo, hi) - lo) / (hi - lo)) * 1000).toInt()
                progressTintList = ColorStateList.valueOf(Color.WHITE); thumbTintList = ColorStateList.valueOf(Color.WHITE)
                contentDescription = c.getString(word)
                setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(s: SeekBar, p: Int, fromUser: Boolean) { if (fromUser) onChange(lo + (hi - lo) * p / 1000.0) }
                    override fun onStartTrackingTouch(s: SeekBar) {}
                    override fun onStopTrackingTouch(s: SeekBar) {}
                })
            }, lp())
        }
    }

    /** «Colour»: the words and the swatch at full saturation and light (iOS hueColor), the hue's slider on the wheel's own band under them. */
    private fun hueRow(hue: Double, onChange: (Double) -> Unit): View {
        val c: Context = act
        fun tone(h: Double) = Color.HSVToColor(floatArrayOf(h.toFloat().coerceIn(0f, 360f), 0.85f, 1f))
        val chip = View(c).apply { background = c.rounded(tone(hue), 5) }
        return c.vstack(Gravity.NO_GRAVITY) {
            setPadding(dp(16), dp(12), dp(16), dp(8))
            addView(c.hstack {
                addView(c.text(c.getString(R.string.colour), 16f), lp(0, WRAP, 1f))
                addView(chip, lp(dp(30), dp(22)))
            }, lp())
            addView(SeekBar(c).apply {
                max = 360; progress = hue.toInt().coerceIn(0, 360)
                progressDrawable = GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT,
                    IntArray(7) { tone(it * 60.0) }).apply { cornerRadius = dp(3).toFloat(); setSize(0, dp(6)) }
                thumbTintList = ColorStateList.valueOf(Color.WHITE)
                contentDescription = c.getString(R.string.hue)
                setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(s: SeekBar, p: Int, fromUser: Boolean) {
                        if (fromUser) { chip.background = c.rounded(tone(p.toDouble()), 5); onChange(p.toDouble()) }
                    }
                    override fun onStartTrackingTouch(s: SeekBar) {}
                    override fun onStopTrackingTouch(s: SeekBar) {}
                })
            }, lp().apply { topMargin = dp(8) })
        }
    }
}
