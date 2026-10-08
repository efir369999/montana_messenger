import Foundation
import MetalKit
import QuartzCore
import SwiftUI


private let orbIdleUniformSeed: [Float] = [
    1, 1, 0, 0.2460000067949295, 0.7200000286102295, 0.3384000062942505, 1.6640000343322754, 0.23999999463558197,
    1.9800000190734863, 0.11999999731779099, 0.5600000023841858, 0.20000000298023224, 0.18000000715255737, 0.18000000715255737, 1.3600000143051147, 9,
    0.004999999888241291, 0, 0, 1, 1, 0, 2, 0.41999998688697815,
    0.7699999809265137, 0.23000000417232513, 65, 0, 0, 1, 0.2199999988079071, 0.25,
    0.7200000286102295, 5, 0.41999998688697815, 1.25, 0.550000011920929, 0.30000001192092896, 1.2000000476837158, 0.699999988079071,
    0.7098039388656616, 0.6509804129600525, 0.45490196347236633, 1, 0.3686274588108063, 0.529411792755127, 0.5803921818733215, 1,
    0.6039215922355652, 0.3921568691730499, 0.5411764979362488, 1, 0.38823530077934265, 0.35686275362968445, 0.5411764979362488, 1,
    0.7137255072593689, 0.7686274647712708, 0.8235294222831726, 1, 1, 1, 1, 1,
    0.6078431606292725, 0.95686274766922, 1, 1, 0.772549033164978, 0.6627451181411743, 1, 1,
    0.9176470637321472, 0.95686274766922, 1, 1, 0.8627451062202454, 0.9176470637321472, 1, 1,
    0.0117647061124444, 0.01568627543747425, 0.03529411926865578, 1, 0.42352941632270813, 0.40784314274787903, 0.5607843399047852, 1,
    0.9686274528503418, 0.9843137264251709, 1, 1, 0.9372549057006836, 0.9647058844566345, 0.9921568632125854, 1,
    0.8784313797950745, 0.9333333373069763, 0.9764705896377563, 1, 0.8313725590705872, 0.9019607901573181, 0.9686274528503418, 1,
    0.7333333492279053, 0.8352941274642944, 0.9529411792755127, 1, 0.6509804129600525, 0.7803921699523926, 0.9411764740943909, 1,
    0.529411792755127, 0.6901960968971252, 0.9215686321258545, 1, 0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1,
    0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1, 0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1,
    0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1, 0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1,
]

private let orbThinkingUniformSeed: [Float] = [
    1, 1, 0, 0.36000001430511475, 0.7200000286102295, 0.36000001430511475, 3.200000047683716, 0.5,
    2.200000047683716, 0.11999999731779099, 0.5600000023841858, 0.20000000298023224, 0.18000000715255737, 0.18000000715255737, 2, 9,
    0.004999999888241291, 0, 0, 1, 1, 0, 2, 0.41999998688697815,
    0.7699999809265137, 0.23000000417232513, 65, 0, 0, 1, 0.2199999988079071, 0.25,
    0.7200000286102295, 5, 0.41999998688697815, 1.25, 0.550000011920929, 0.30000001192092896, 1.2000000476837158, 0.699999988079071,
    1, 0.8470588326454163, 0.41960784792900085, 1, 0.5098039507865906, 0.95686274766922, 1, 1,
    1, 0.48235294222831726, 0.8352941274642944, 1, 0.5568627715110779, 0.42352941632270813, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    0.6078431606292725, 0.95686274766922, 1, 1, 0.772549033164978, 0.6627451181411743, 1, 1,
    0.9176470637321472, 0.95686274766922, 1, 1, 0.8627451062202454, 0.9176470637321472, 1, 1,
    0.0117647061124444, 0.01568627543747425, 0.03529411926865578, 1, 0.5843137502670288, 0.42352941632270813, 1, 1,
    0.9686274528503418, 0.9843137264251709, 1, 1, 0.9372549057006836, 0.9647058844566345, 0.9921568632125854, 1,
    0.8784313797950745, 0.9333333373069763, 0.9764705896377563, 1, 0.8313725590705872, 0.9019607901573181, 0.9686274528503418, 1,
    0.7333333492279053, 0.8352941274642944, 0.9529411792755127, 1, 0.6509804129600525, 0.7803921699523926, 0.9411764740943909, 1,
    0.529411792755127, 0.6901960968971252, 0.9215686321258545, 1, 0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1,
    0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1, 0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1,
    0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1, 0.43529412150382996, 0.6196078658103943, 0.9098039269447327, 1,
]

private let orbActivationDuration: CFTimeInterval = 0.22
private let orbSettleDuration: CFTimeInterval = 0.65
private let orbRibbonStyleIndex: Float = 24
private let orbRibbonInstanceCount = 221184

public enum LiquidOrbState: Equatable, Sendable {
    case idle
    case thinking
    case styled([Float])   // a seed shaped by the person (the voice style screen, the author's word 14.09)
}

/// A TINTED ORB (the author's word 14.09): the same shader, the same seed, the same motion —
/// only the colour. Every colour of the seed keeps its saturation and its light and takes a
/// hue in a band around the chosen one, spread a little by where it stood on the wheel, so
/// the play of tones stays and the whole ball reads in that colour. Gold = 42°.
private func orbTinted(_ seed: [Float], hue centre: Float) -> [Float] {
    var s = seed
    var i = 40   // the first float4 colour of the uniforms (colorA); scalars stand before it
    while i + 3 < s.count {
        let (h, sat, v) = orbRgbToHsv(s[i], s[i + 1], s[i + 2])
        if sat > 0.12 {
            var deg = centre + 14 * cos(h * .pi / 90)   // ±14° around the centre
            deg = deg.truncatingRemainder(dividingBy: 360); if deg < 0 { deg += 360 }
            let (r, g, b) = orbHsvToRgb(deg / 360, sat, v)
            s[i] = r; s[i + 1] = g; s[i + 2] = b
        }
        i += 4
    }
    return s
}

/// ONE SIDE'S STYLE of the voice orb: its colour, its motion and its size in the feed.
public struct MontanaVoiceOrbSide: Codable, Equatable {
    public var hue: Double       // degrees; below zero = the orb's own colours
    public var speed: Double
    public var liquid: Double
    public var zoom: Double
    public var exposure: Double
    public var glass: Double
    public var fringe: Double
    public var sheen: Double
    public var size: Double      // the bubble's side in points (the author's word 14.09: 15 % under the first 160)
    public static func montana(mine: Bool) -> MontanaVoiceOrbSide {
        MontanaVoiceOrbSide(hue: mine ? -1 : 42, speed: 0.36, liquid: 3.2, zoom: 0.36, exposure: 2, glass: 1, fringe: 0.42, sheen: 0.56, size: 136)
    }
}

/// THE VOICE ORB'S STYLE (the author's word 14.09): everything the seed lets a person shape —
/// the colour, the motion and the size of each side's orb — kept here, one owner, read by
/// every orb of the tree and by the style screen. The sender's orb keeps the orb's own
/// colours, the peer's is gold, until the person says otherwise; every setting is per side.
public final class MontanaVoiceOrbStyle: ObservableObject {
    public static let shared = MontanaVoiceOrbStyle()
    private static func read(_ k: String, mine: Bool) -> MontanaVoiceOrbSide {
        if let d = UserDefaults.standard.data(forKey: "voiceOrb.side." + k),
           let v = try? JSONDecoder().decode(MontanaVoiceOrbSide.self, from: d) { return v }
        return .montana(mine: mine)
    }
    private static func write(_ k: String, _ v: MontanaVoiceOrbSide) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: "voiceOrb.side." + k) }
    }
    @Published public var mine: MontanaVoiceOrbSide = read("mine", mine: true) { didSet { Self.write("mine", mine) } }
    @Published public var theirs: MontanaVoiceOrbSide = read("theirs", mine: false) { didSet { Self.write("theirs", theirs) } }
    public func side(mine m: Bool) -> MontanaVoiceOrbSide { m ? mine : theirs }
    /// A copy laid under the style (23.09): both sides and the look are read from the store again.
    public func reread() {
        mine = Self.read("mine", mine: true)
        theirs = Self.read("theirs", mine: false)
        look = UserDefaults.standard.string(forKey: "voiceOrb.look") ?? "orb"
    }
    /// THE LOOK of a voice message in the feed (the author's word 17.09): the orb, or the histogram —
    /// the very plate a music track wears, its wave in the text bubble's colours. One knob, one owner.
    @Published public var look: String = UserDefaults.standard.string(forKey: "voiceOrb.look") ?? "orb" {
        didSet { UserDefaults.standard.set(look, forKey: "voiceOrb.look") }
    }
    public var histogram: Bool { look == "bars" }
    public func reset() { mine = .montana(mine: true); theirs = .montana(mine: false); look = "orb" }
    /// The seed for one side: the orb's thinking seed with the person's motion and colour on it.
    public func seed(mine m: Bool) -> [Float] {
        let v = side(mine: m)
        var s = orbThinkingUniformSeed
        s[3] = Float(v.speed); s[6] = Float(v.liquid); s[5] = Float(v.zoom); s[14] = Float(v.exposure)
        s[20] = Float(v.glass); s[23] = Float(v.fringe); s[10] = Float(v.sheen)
        return v.hue < 0 ? s : orbTinted(s, hue: Float(v.hue))
    }
    public func state(mine: Bool) -> LiquidOrbState { .styled(seed(mine: mine)) }
    public func bubbleSide(mine: Bool) -> CGFloat { CGFloat(side(mine: mine).size) }
}

private func orbRgbToHsv(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
    let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
    var h: Float = 0
    if d > 0.0001 {
        if mx == r { h = 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == g { h = 60 * ((b - r) / d + 2) }
        else { h = 60 * ((r - g) / d + 4) }
        if h < 0 { h += 360 }
    }
    return (h, mx > 0 ? d / mx : 0, mx)
}
private func orbHsvToRgb(_ h: Float, _ s: Float, _ v: Float) -> (Float, Float, Float) {
    let i = Int(h * 6) % 6, f = h * 6 - Float(Int(h * 6))
    let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
    switch i {
    case 0: return (v, t, p)
    case 1: return (q, v, p)
    case 2: return (p, v, t)
    case 3: return (p, q, v)
    case 4: return (t, p, v)
    default: return (v, p, q)
    }
}

private func orbUniformSeed(for state: LiquidOrbState) -> [Float] {
    switch state {
    case .idle: orbIdleUniformSeed
    case .thinking: orbThinkingUniformSeed
    case .styled(let seed): seed.count == orbThinkingUniformSeed.count ? seed : orbThinkingUniformSeed
    }
}

private func orbSrgbToLinear(_ value: Float) -> Float {
    value <= 0.04045
        ? value / 12.92
        : Float(pow(Double((value + 0.055) / 1.055), 2.4))
}

private func orbLinearToSrgb(_ value: Float) -> Float {
    value <= 0.0031308
        ? value * 12.92
        : 1.055 * Float(pow(Double(value), 1.0 / 2.4)) - 0.055
}

private func orbMixSrgb(_ from: Float, _ to: Float, _ progress: Float) -> Float {
    orbLinearToSrgb(
        orbSrgbToLinear(from) + (orbSrgbToLinear(to) - orbSrgbToLinear(from)) * progress
    )
}

private enum LiquidOrbError: Error {
    case metalUnavailable
    case shaderFunctionMissing(String)
    case commandQueueUnavailable
}

private final class LiquidOrbRenderer: NSObject, MTKViewDelegate {
    // The shader lives in MTVoiceOrb.metal and is compiled with the app: the phone never runs
    // a compiler. The pipelines are built once per process, ahead of the first orb, off the
    // main thread — a cell never waits for them.
    private static let libraryLock = NSLock()
    static let pixelFormat: MTLPixelFormat = .bgra8Unorm

    static func library(on device: MTLDevice) throws -> MTLLibrary {
        guard let lib = device.makeDefaultLibrary() else { throw LiquidOrbError.shaderFunctionMissing("default library") }
        return lib
    }

    /// Build the kit ahead of the first orb, off the main thread.
    static func warm() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }   // SILENT-OK: no Metal device — nothing to warm; the view that asks marks the diary
        _ = try? kit(on: device, pixelFormat: pixelFormat)   // SILENT-OK: a refusal is marked by the view that asks for the kit
    }

    /// The kit if it is already built — the only thing a cell may ask for on the main thread.
    static var readyKit: Kit? {
        libraryLock.lock(); defer { libraryLock.unlock() }
        return cachedKit
    }

    struct Kit {
        let pipeline: MTLRenderPipelineState
        let ribbonPipeline: MTLRenderPipelineState
        let ribbonCompositePipeline: MTLRenderPipelineState
    }
    private static var cachedKit: Kit?

    /// The three pipelines are built once per process as well: a feed of voice messages makes
    /// an orb per cell, and building pipelines on every cell birth would stutter the scroll.
    static func kit(on device: MTLDevice, pixelFormat: MTLPixelFormat) throws -> Kit {
        libraryLock.lock()
        let hit = cachedKit
        libraryLock.unlock()
        if let hit { return hit }
        let lib = try Self.library(on: device)
        guard let vertex = lib.makeFunction(name: "vs_main") else {
            throw LiquidOrbError.shaderFunctionMissing("vs_main")
        }
        guard let fragment = lib.makeFunction(name: "fs_main") else {
            throw LiquidOrbError.shaderFunctionMissing("fs_main")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        guard let ribbonVertex = lib.makeFunction(name: "ribbon_vs_main") else {
            throw LiquidOrbError.shaderFunctionMissing("ribbon_vs_main")
        }
        guard let ribbonFragment = lib.makeFunction(name: "ribbon_fs_main") else {
            throw LiquidOrbError.shaderFunctionMissing("ribbon_fs_main")
        }
        let ribbonDescriptor = MTLRenderPipelineDescriptor()
        ribbonDescriptor.vertexFunction = ribbonVertex
        ribbonDescriptor.fragmentFunction = ribbonFragment
        ribbonDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        ribbonDescriptor.colorAttachments[0].isBlendingEnabled = true
        ribbonDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        ribbonDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        ribbonDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        ribbonDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let ribbonPipeline = try device.makeRenderPipelineState(descriptor: ribbonDescriptor)
        guard let ribbonCompositeFragment = lib.makeFunction(
            name: "ribbon_composite_fs_main"
        ) else {
            throw LiquidOrbError.shaderFunctionMissing("ribbon_composite_fs_main")
        }
        let ribbonCompositeDescriptor = MTLRenderPipelineDescriptor()
        ribbonCompositeDescriptor.vertexFunction = vertex
        ribbonCompositeDescriptor.fragmentFunction = ribbonCompositeFragment
        ribbonCompositeDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        ribbonCompositeDescriptor.colorAttachments[0].isBlendingEnabled = true
        ribbonCompositeDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        ribbonCompositeDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        ribbonCompositeDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        ribbonCompositeDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let ribbonCompositePipeline = try device.makeRenderPipelineState(
            descriptor: ribbonCompositeDescriptor
        )
        let built = Kit(pipeline: pipeline, ribbonPipeline: ribbonPipeline,
                        ribbonCompositePipeline: ribbonCompositePipeline)
        libraryLock.lock(); cachedKit = built; libraryLock.unlock()
        return built
    }

    private let commandQueue: MTLCommandQueue
    private let rimRadius: Float?   // the rim's share of the frame, when the orb must fill it
    private let pipeline: MTLRenderPipelineState
    private let ribbonPipeline: MTLRenderPipelineState
    private let ribbonCompositePipeline: MTLRenderPipelineState
    private var ribbonTexture: MTLTexture?
    private var lastFrameAt = CACurrentMediaTime()
    private var motionPhase: CFTimeInterval = 0
    private let stateLock = NSLock()
    private var currentState: LiquidOrbState
    private var transitionTargetState: LiquidOrbState
    private var fromUniforms: [Float]
    private var targetUniforms: [Float]
    private var displayedUniforms: [Float]
    private var transitionStartedAt = CACurrentMediaTime()
    private var activeTransitionDuration: CFTimeInterval = 0

    init(view: MTKView, state: LiquidOrbState, kit: Kit, rimRadius: Float?) throws {
        let initialUniforms = orbUniformSeed(for: state)
        self.rimRadius = rimRadius
        currentState = state
        transitionTargetState = state
        fromUniforms = initialUniforms
        targetUniforms = initialUniforms
        displayedUniforms = initialUniforms

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw LiquidOrbError.metalUnavailable
        }
        view.device = device
        view.colorPixelFormat = LiquidOrbRenderer.pixelFormat
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        #if os(iOS)
        // Two pixels per point is all a soft gradient needs; three is nine-quarters more shading.
        view.contentScaleFactor = min(view.contentScaleFactor, 2)
        #endif
        #if os(iOS)
        view.isOpaque = false
        #elseif os(macOS)
        view.layer?.isOpaque = false
        #endif
        view.clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 0
        )

        pipeline = kit.pipeline
        ribbonPipeline = kit.ribbonPipeline
        ribbonCompositePipeline = kit.ribbonCompositePipeline
        guard let queue = device.makeCommandQueue() else {
            throw LiquidOrbError.commandQueueUnavailable
        }
        commandQueue = queue
        super.init()
    }

    func setState(_ state: LiquidOrbState) {
        let now = CACurrentMediaTime()
        stateLock.lock()
        defer { stateLock.unlock() }
        guard state != currentState else { return }

        let nextUniforms = orbUniformSeed(for: state)
        fromUniforms = sampleTransition(at: now)
        targetUniforms = nextUniforms
        transitionTargetState = state
        transitionStartedAt = now
        activeTransitionDuration = state == .thinking
            ? orbActivationDuration
            : orbSettleDuration
        currentState = state
    }

    private func sampleTransition(at now: CFTimeInterval) -> [Float] {
        let rawProgress = activeTransitionDuration == 0
            ? 1
            : min(1, max(0, (now - transitionStartedAt) / activeTransitionDuration))
        let easedProgress = transitionTargetState == .thinking
            ? 1 - pow(1 - rawProgress, 3)
            : rawProgress * rawProgress * (3 - 2 * rawProgress)
        let progress = Float(easedProgress)

        for index in 3..<displayedUniforms.count {
            let isColorComponent = index >= 40
                && (index - 40) % 4 < 3
            displayedUniforms[index] = isColorComponent
                ? orbMixSrgb(fromUniforms[index], targetUniforms[index], progress)
                : fromUniforms[index] + (targetUniforms[index] - fromUniforms[index]) * progress
        }
        return displayedUniforms
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        ribbonTexture = nil
    }

    private func ensureRibbonTexture(for view: MTKView) -> MTLTexture? {
        let width = max(1, Int(view.drawableSize.width))
        let height = max(1, Int(view.drawableSize.height))
        if let ribbonTexture,
           ribbonTexture.width == width,
           ribbonTexture.height == height {
            return ribbonTexture
        }
        guard let device = view.device else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: view.colorPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        ribbonTexture = device.makeTexture(descriptor: descriptor)
        return ribbonTexture
    }

    func draw(in view: MTKView) {
        guard
            view.drawableSize.width > 0,
            view.drawableSize.height > 0,
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        let now = CACurrentMediaTime()
        stateLock.lock()
        var uniforms = sampleTransition(at: now)
        stateLock.unlock()
        let frameDelta = min(0.1, max(0, now - lastFrameAt))
        lastFrameAt = now
        motionPhase += frameDelta * CFTimeInterval(max(uniforms[3], 0))
        uniforms[0] = Float(view.drawableSize.width)
        uniforms[1] = Float(view.drawableSize.height)
        if let rimRadius { uniforms[4] = rimRadius }
        uniforms[2] = Float(motionPhase / CFTimeInterval(max(uniforms[3], 0.001)))
        let isParticleRibbon = round(uniforms[15]) == orbRibbonStyleIndex
        if isParticleRibbon {
            guard let ribbonTexture = ensureRibbonTexture(for: view) else { return }
            let ribbonPass = MTLRenderPassDescriptor()
            ribbonPass.colorAttachments[0].texture = ribbonTexture
            ribbonPass.colorAttachments[0].loadAction = .clear
            ribbonPass.colorAttachments[0].storeAction = .store
            ribbonPass.colorAttachments[0].clearColor = MTLClearColor(
                red: 0, green: 0, blue: 0, alpha: 0
            )
            guard let ribbonEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: ribbonPass
            ) else { return }
            ribbonEncoder.setRenderPipelineState(ribbonPipeline)
            uniforms.withUnsafeBytes { bytes in
                ribbonEncoder.setVertexBytes(bytes.baseAddress!, length: bytes.count, index: 0)
                ribbonEncoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 0)
            }
            ribbonEncoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: orbRibbonInstanceCount
            )
            ribbonEncoder.endEncoding()
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        encoder.setRenderPipelineState(isParticleRibbon ? ribbonCompositePipeline : pipeline)
        uniforms.withUnsafeBytes { bytes in
            encoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 0)
        }
        if isParticleRibbon {
            encoder.setFragmentTexture(ribbonTexture, index: 0)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

/// The orb's surface: it draws only while it is on screen AND asked to move. A feed cell
/// that scrolled away keeps its view in the reuse pool — and used to keep drawing into
/// nothing; a still orb shows one frame and rests (the author's word 14.09).
private final class LiquidOrbMTKView: MTKView {
    var animating = true { didSet { settle() } }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        settle()
    }
    func settle() {
        let live = window != nil && delegate != nil
        isPaused = !live || !animating
        if live, !animating { draw() }   // one frame for a still orb
    }
    /// The still frame is asked for again whenever the size settles: a cell attaches its view
    /// at zero size, the one frame drew nothing, and the orb stayed blank for good (14.09: the
    /// voice bubbles «vanished» when the player closed and the feed re-laid its cells).
    override func layoutSubviews() {
        super.layoutSubviews()
        if !animating, window != nil, delegate != nil, bounds.width > 1, bounds.height > 1 { draw() }
    }
}

private final class LiquidOrbCoordinator {
    private var renderer: LiquidOrbRenderer?
    private var wanted: LiquidOrbState = .thinking

    func makeView(state: LiquidOrbState, framesPerSecond: Int, rimRadius: Float?, animating: Bool) -> MTKView {
        let view = LiquidOrbMTKView(frame: .zero, device: nil)
        view.isPaused = true
        view.animating = animating
        wanted = state
        if let kit = LiquidOrbRenderer.readyKit {
            attach(view, state: state, kit: kit, framesPerSecond: framesPerSecond, rimRadius: rimRadius)
            return view
        }
        // Not built yet: the cell shows nothing for a moment and never waits on the main thread.
        Task.detached(priority: .userInitiated) { [weak self, weak view] in
            LiquidOrbRenderer.warm()
            guard let kit = LiquidOrbRenderer.readyKit else {
                MontanaP2PTrace.mark("voice_orb", "kit refused — the orb stays empty")
                return
            }
            await MainActor.run {
                guard let self, let view else { return }   // SILENT-OK: the cell is gone; nothing to draw for
                self.attach(view, state: self.wanted, kit: kit, framesPerSecond: framesPerSecond, rimRadius: rimRadius)
            }
        }
        return view
    }

    private func attach(_ view: MTKView, state: LiquidOrbState, kit: LiquidOrbRenderer.Kit,
                        framesPerSecond: Int, rimRadius: Float?) {
        do {
            let renderer = try LiquidOrbRenderer(view: view, state: state, kit: kit, rimRadius: rimRadius)
            view.preferredFramesPerSecond = framesPerSecond
            self.renderer = renderer
            view.delegate = renderer
            (view as? LiquidOrbMTKView)?.settle()
        } catch {
            MontanaP2PTrace.mark("voice_orb", "metal unavailable: \(error)")
            view.isPaused = true
        }
    }

    func setState(_ state: LiquidOrbState, animating: Bool, on view: MTKView) {
        wanted = state
        renderer?.setState(state)
        if let v = view as? LiquidOrbMTKView, v.animating != animating { v.animating = animating }
    }
}

#if os(iOS)
private struct LiquidOrbSurface: UIViewRepresentable {
    let state: LiquidOrbState
    let framesPerSecond: Int
    let rimRadius: Float?
    let animating: Bool

    func makeCoordinator() -> LiquidOrbCoordinator { LiquidOrbCoordinator() }
    func makeUIView(context: Context) -> MTKView { context.coordinator.makeView(state: state, framesPerSecond: framesPerSecond, rimRadius: rimRadius, animating: animating) }
    func updateUIView(_ view: MTKView, context: Context) { context.coordinator.setState(state, animating: animating, on: view) }
}
#elseif os(macOS)
private struct LiquidOrbSurface: NSViewRepresentable {
    let state: LiquidOrbState
    let framesPerSecond: Int
    let rimRadius: Float?
    let animating: Bool

    func makeCoordinator() -> LiquidOrbCoordinator { LiquidOrbCoordinator() }
    func makeNSView(context: Context) -> MTKView { context.coordinator.makeView(state: state, framesPerSecond: framesPerSecond, rimRadius: rimRadius, animating: animating) }
    func updateNSView(_ view: MTKView, context: Context) { context.coordinator.setState(state, animating: animating, on: view) }
}
#endif

public struct LiquidOrbView: View {
    private let state: LiquidOrbState
    private let framesPerSecond: Int
    private let rimRadius: Float?
    private let animating: Bool

    /// `rimRadius` — the rim's share of the frame's half-side (the seed's own is 0.72); pass
    /// `LiquidOrbView.fullRim` when the ball must fill its frame. `animating` false — one frame, then rest.
    public init(state: LiquidOrbState = .thinking, framesPerSecond: Int = 60, rimRadius: Float? = nil, animating: Bool = true) {
        self.state = state
        self.framesPerSecond = framesPerSecond
        self.rimRadius = rimRadius
        self.animating = animating
    }

    /// The rim on the frame itself, with room for the shader's own two-pixel feather.
    public static let fullRim: Float = 0.96

    public var body: some View {
        LiquidOrbSurface(state: state, framesPerSecond: framesPerSecond, rimRadius: rimRadius, animating: animating)
    }
}

/// Warm the orb's shader before the first hold (called when a chat opens).
public enum MontanaVoiceOrb {
    public static func warm() {
        Task.detached(priority: .utility) { LiquidOrbRenderer.warm() }
    }
}

/// THE TAPE'S SECONDS UNDER ITS CIRCLE (the author's word 21.09, one row for the voice and the note): the
/// pulsing red dot and the time, drawn once; the circle's owner hangs it under the rim by `drop`.
struct MTTapeSeconds: View {
    let elapsed: Double      // the tape's own length
    let paused: Bool         // the tape stands: the dot stops pulsing
    @State private var pulse = false
    static let drop: CGFloat = 28   // from the circle's rim down to the row's centre
    static let row: CGFloat = 36    // the room the row takes under a circle (the note's stage counts it)
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.red).frame(width: 10, height: 10)
                .opacity(paused ? 1 : (pulse ? 0.2 : 1))
                .animation(paused ? .default : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            // USER-DATA: a duration.
            Text(verbatim: fmtDuration(elapsed))
                .font(.system(.title2, design: .monospaced)).foregroundColor(.white)
        }
        .onAppear { pulse = true }
    }
}

/// The voice's circle (the author's word 14.09, its place the crown's since 21.09): the liquid orb in
/// the middle of the VISIBLE part — keys up or down — and under it the pulsing red dot with the seconds.
/// Drawn by the crown (MTHoldOverlayView) at st.orb; the tape is read live.
struct MontanaVoiceRecordHold: View {
    @ObservedObject var voice: VoiceRecorder
    @ObservedObject private var style = MontanaVoiceOrbStyle.shared
    private static let orbSide: CGFloat = 160   // the ball itself, rim on the frame

    var body: some View {
        ZStack {
            LiquidOrbView(state: style.state(mine: true), rimRadius: LiquidOrbView.fullRim, animating: !voice.paused)   // my own voice
                .frame(width: Self.orbSide, height: Self.orbSide)
            MTTapeSeconds(elapsed: voice.elapsed, paused: voice.paused)
                .offset(y: Self.orbSide / 2 + MTTapeSeconds.drop)
        }
    }
}

/// The orb over a voice message in the feed (the author's word 14.09): the same animation on
/// both sides, born from the module rather than shipped as bytes — nothing new rides the wire,
/// every build sees the voice as before. Half the frame rate of the hold: a feed may hold several.
struct MontanaVoiceOrbBadge: View {
    var animating = false   // still until its voice plays (the author's word 14.09)
    var mine = false        // the sender keeps the orb's own colours, the peer's is gold (the author's word 14.09) — until the style screen says otherwise
    @ObservedObject private var style = MontanaVoiceOrbStyle.shared
    var body: some View {
        LiquidOrbView(state: style.state(mine: mine), framesPerSecond: 24, rimRadius: LiquidOrbView.fullRim, animating: animating)
    }
}

/// THE STYLE SCREEN OF THE VOICE ORB (Settings → Appearance → Voice message style, the author's
/// word 14.09): both orbs live at the top, every knob the seed offers below — the colour of each
/// side, the motion of the ball — the platform's own rows, sliders and colour picker.
struct MontanaVoiceOrbStyleView: View {
    @ObservedObject private var style = MontanaVoiceOrbStyle.shared
    @State private var editingMine = true   // the side a tap on an orb chooses; every knob below is that side's
    private var side: Binding<MontanaVoiceOrbSide> { editingMine ? $style.mine : $style.theirs }
    private func hueColor(_ h: Double) -> Color { Color(hue: max(0, h) / 360, saturation: 0.85, brightness: 1) }
    private var hueBinding: Binding<Color> {
        Binding(get: { hueColor(side.wrappedValue.hue) },
                set: { c in
                    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    if UIColor(c).getHue(&h, saturation: &s, brightness: &b, alpha: &a) { side.wrappedValue.hue = Double(h * 360) }
                })
    }
    private var ownColours: Binding<Bool> {
        Binding(get: { side.wrappedValue.hue < 0 }, set: { side.wrappedValue.hue = $0 ? -1 : 42 })
    }
    private func slider(_ title: LocalizedStringKey, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundColor(.gray)
            Slider(value: value, in: range)
        }
    }
    /// One of the two orbs at the top: a tap chooses it, the chosen one wears the gold ring.
    private func orb(mine: Bool, _ title: LocalizedStringKey) -> some View {
        let chosen = editingMine == mine
        return VStack(spacing: 6) {
            LiquidOrbView(state: style.state(mine: mine), framesPerSecond: 30, rimRadius: LiquidOrbView.fullRim)
                .frame(width: 120, height: 120)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: chosen ? 2.5 : 0).padding(-6))
                .animation(.easeOut(duration: 0.15), value: chosen)
            Text(title).font(.caption).foregroundColor(chosen ? .white : .gray)
        }
        .contentShape(Rectangle())
        .onTapGesture { editingMine = mine }
    }
    var body: some View {
        VStack(spacing: 0) {
            // THE LOOK FIRST (the author's word 17.09): the orb, or the histogram of a music track.
            Picker("Look", selection: $style.look) {
                Text("Orb").tag("orb")
                Text("Histogram").tag("bars")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.top, 12)
            if style.histogram {
                Text("The histogram wears the colours of the text bubble.")
                    .font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
                    .padding(.horizontal, 24).padding(.vertical, 14)
            } else {
            HStack(spacing: 28) {
                orb(mine: false, "Their voice")
                orb(mine: true, "Your voice")
            }
            .padding(.top, 14)
            Text("Tap an orb to edit that side").font(.caption2).foregroundColor(.gray).padding(.vertical, 8)
            }
            List {
                if !style.histogram {
                Section(editingMine ? "Your voice" : "Their voice") {
                    Toggle("Own colours", isOn: ownColours).foregroundColor(.white)
                    if side.wrappedValue.hue >= 0 {
                        ColorPicker("Colour", selection: hueBinding, supportsOpacity: false).foregroundColor(.white)
                    }
                    slider("Bubble size", side.size, 100...200)
                }.listRowBackground(MTGlassRowPlate())
                Section("Motion") {
                    slider("Speed", side.speed, 0.05...1.5)
                    slider("Liquid", side.liquid, 0.0...6.0)
                    slider("Zoom", side.zoom, 0.1...1.0)
                    slider("Exposure", side.exposure, 0.5...4.0)
                    slider("Glass", side.glass, 0.0...1.0)
                    slider("Colour fringe", side.fringe, 0.0...1.5)
                    slider("Sheen", side.sheen, 0.0...1.0)
                }.listRowBackground(MTGlassRowPlate())
                }
                Section {
                    Button { style.reset() } label: { Text("Reset to Montana").foregroundColor(.accentColor) }
                }.listRowBackground(MTGlassRowPlate())
            }
            .scrollContentBackground(.hidden)
        }
        .montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
        .navigationTitle("Voice message style").navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}
