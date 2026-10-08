//  MontanaAvatarMask.swift -- the avatar mask of a video call (checklist 36, stage 1.1).
//
//  THE FACE NEVER LEAVES THE PHONE WHILE THE MASK IS ON (the author's word 30.09: "as a mask -- an avatar in a video
//  call"). The call's camera frames are read here, in memory, by the platform's own face tracking; the source of the
//  call's video lane receives only the avatar's frames, drawn here by the platform's own 3D renderer. The one door is
//  the birth of what goes out: FrameCountingCapturerDelegate hands every camera frame to take(_:from:into:) first, and
//  a frame the mask takes never reaches the source -- nor the self-view, which shows what the peer sees. Nothing new
//  travels: the avatar rides the same lane under the same SFrame / DTLS-SRTP the camera did -- no new primitive, no
//  service of anyone else, no server.
//
//  Energy: the tracker and the renderer live only while the mask is on; turning it off lets the renderer go.

import Foundation
import AVFoundation
import CoreVideo
import Metal
import QuartzCore
import SceneKit
import UIKit
import Vision
import WebRTC

/// What the face does: the platform's blend-shape words in 0...1 and the head's turn in radians.
struct MTAvatarFace: Equatable {
    var eyeBlinkLeft: Float = 0
    var eyeBlinkRight: Float = 0
    var jawOpen: Float = 0
    var yaw: Float = 0
    var pitch: Float = 0
    var roll: Float = 0
    static let rest = MTAvatarFace()

    /// A step toward another face: the tracker's reading shivers from frame to frame, the look follows it softly.
    func eased(toward n: MTAvatarFace, by k: Float) -> MTAvatarFace {
        func e(_ a: Float, _ b: Float) -> Float { a + (b - a) * k }
        return MTAvatarFace(eyeBlinkLeft: e(eyeBlinkLeft, n.eyeBlinkLeft), eyeBlinkRight: e(eyeBlinkRight, n.eyeBlinkRight),
                            jawOpen: e(jawOpen, n.jawOpen), yaw: e(yaw, n.yaw), pitch: e(pitch, n.pitch), roll: e(roll, n.roll))
    }
}

/// THE TRACKER READS THE FRAME THE CALL'S CAMERA ALREADY MADE (stage 1.1): the platform's face landmarks (Vision), on
/// every phone and tablet of the floor, TrueDepth or not. One camera, one owner (MontanaCamera) -- a second capture
/// session is never born. The TrueDepth tracker (ARKit, 52 blend shapes) owns the camera itself and would fight the
/// call's raise machine for it; it is stage 1.2 of the checklist, with that hand-over designed first.
enum MTAvatarTracker {
    /// The raw ratios a reading was made of, kept for the diary (call_mask_raw): the four thresholds below are a first
    /// estimate, not a measure, and the diary of T1 and T3 is where they are measured.
    struct Raw { var eyeL: Float = 0; var eyeR: Float = 0; var mouth: Float = 0 }

    private static let eyeOpen: Float = 0.30     // an open eye's height over its width (first estimate)
    private static let eyeShut: Float = 0.12     // a closed eye's (first estimate)
    private static let mouthShut: Float = 0.04   // the inner lips' gap over the mouth's width, shut (first estimate)
    private static let mouthWide: Float = 0.45   // and wide open (first estimate)

    static func read(_ px: CVPixelBuffer, rotation: RTCVideoRotation) -> (face: MTAvatarFace, raw: Raw)? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: px, orientation: orientation(rotation), options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let seen = request.results?.first, let marks = seen.landmarks else { return nil }
        var raw = Raw()
        raw.eyeL = openness(marks.leftEye, empty: eyeOpen)
        raw.eyeR = openness(marks.rightEye, empty: eyeOpen)
        raw.mouth = mouthOpenness(inner: marks.innerLips, outer: marks.outerLips)
        var f = MTAvatarFace()
        f.eyeBlinkLeft = unit((eyeOpen - raw.eyeL) / (eyeOpen - eyeShut))
        f.eyeBlinkRight = unit((eyeOpen - raw.eyeR) / (eyeOpen - eyeShut))
        f.jawOpen = unit((raw.mouth - mouthShut) / (mouthWide - mouthShut))
        f.yaw = seen.yaw?.floatValue ?? 0
        f.pitch = seen.pitch?.floatValue ?? 0
        f.roll = seen.roll?.floatValue ?? 0
        return (f, raw)
    }

    /// The frame's rotation metadata as the image orientation Vision reads: the buffer turned by the angle the picture
    /// is shown at (MontanaCamera.updateRotation writes it).
    static func orientation(_ r: RTCVideoRotation) -> CGImagePropertyOrientation {
        switch r {
        case ._90: return .right
        case ._180: return .down
        case ._270: return .left
        default: return .up
        }
    }

    private static func unit(_ v: Float) -> Float { min(1, max(0, v)) }

    /// Height over width of a landmark region's bounds.
    private static func openness(_ region: VNFaceLandmarkRegion2D?, empty: Float) -> Float {
        guard let pts = region?.normalizedPoints, !pts.isEmpty else { return empty }
        let xs = pts.map { p in p.x }, ys = pts.map { p in p.y }
        let w = (xs.max() ?? 0) - (xs.min() ?? 0)
        let h = (ys.max() ?? 0) - (ys.min() ?? 0)
        guard w > 0.0001 else { return empty }
        return Float(h / w)
    }

    private static func mouthOpenness(inner: VNFaceLandmarkRegion2D?, outer: VNFaceLandmarkRegion2D?) -> Float {
        guard let i = inner?.normalizedPoints, let o = outer?.normalizedPoints, !i.isEmpty, !o.isEmpty else { return mouthShut }
        let gap = (i.map { p in p.y }.max() ?? 0) - (i.map { p in p.y }.min() ?? 0)
        let width = (o.map { p in p.x }.max() ?? 0) - (o.map { p in p.x }.min() ?? 0)
        guard width > 0.0001 else { return mouthShut }
        return Float(gap / width)
    }
}

/// THE LOOK HAS ONE OWNER (the author named the avatar, not its style). What stands here is the PROBE look -- the
/// simplest system objects: a sphere for the head, two small spheres for the eyes, a flattened one for the mouth -- and
/// it exists to prove the road from the face to the lane. It is not the final look: the look the author chooses
/// replaces this enum and nothing else (checklist 36, item 1.3).
enum MTAvatarLook {
    static let name = "probe-sphere"

    struct Rig {
        let head: SCNNode
        let eyeL: SCNNode
        let eyeR: SCNNode
        let mouth: SCNNode
    }

    static func build(into scene: SCNScene) -> Rig {
        let head = SCNNode(geometry: SCNSphere(radius: 1))
        head.geometry?.firstMaterial?.diffuse.contents = UIColor(white: 0.92, alpha: 1)
        let dark = UIColor(white: 0.08, alpha: 1)
        func part(_ r: CGFloat, _ x: Float, _ y: Float) -> SCNNode {
            let n = SCNNode(geometry: SCNSphere(radius: r))
            n.geometry?.firstMaterial?.diffuse.contents = dark
            n.position = SCNVector3(x, y, 0.93)
            head.addChildNode(n)
            return n
        }
        let eyeL = part(0.13, -0.35, 0.25)
        let eyeR = part(0.13, 0.35, 0.25)
        let mouth = part(0.22, 0, -0.38)
        scene.rootNode.addChildNode(head)
        let rig = Rig(head: head, eyeL: eyeL, eyeR: eyeR, mouth: mouth)
        pose(rig, .rest)
        return rig
    }

    static func pose(_ rig: Rig, _ f: MTAvatarFace) {
        rig.head.eulerAngles = SCNVector3(f.pitch, f.yaw, f.roll)
        rig.eyeL.scale = SCNVector3(1, max(0.08, 1 - f.eyeBlinkLeft), 0.6)
        rig.eyeR.scale = SCNVector3(1, max(0.08, 1 - f.eyeBlinkRight), 0.6)
        rig.mouth.scale = SCNVector3(1, 0.15 + 0.85 * f.jawOpen, 0.4)
    }
}

/// THE RENDERER: the platform's SceneKit drawing off screen through Metal into a pixel buffer the video lane takes as it
/// takes a camera's. Born when the mask turns on, let go when it turns off; used on the mask's queue only.
final class MTAvatarRenderer {
    private let device: MTLDevice
    private let commands: MTLCommandQueue
    private let renderer: SCNRenderer
    private let camera: SCNCamera
    private let rig: MTAvatarLook.Rig
    private let textures: CVMetalTextureCache
    private var pool: CVPixelBufferPool?
    private var depth: MTLTexture?
    private var width = 0
    private var height = 0
    private let born = CACurrentMediaTime()

    init?() {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else { return nil }
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, d, nil, &cache) == kCVReturnSuccess, let cache else { return nil }
        device = d
        commands = q
        textures = cache
        let scene = SCNScene()
        let r = SCNRenderer(device: d, options: nil)
        r.scene = scene
        r.autoenablesDefaultLighting = true
        let cam = SCNCamera()
        cam.fieldOfView = 40
        let eye = SCNNode()
        eye.camera = cam
        eye.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(eye)
        r.pointOfView = eye
        rig = MTAvatarLook.build(into: scene)
        renderer = r
        camera = cam
    }

    /// The renderer's own formats, named in the diary at the mask's birth: the texture below follows them, and whether
    /// they are what the buffer carries is read on the phone, not assumed.
    var formats: String {
        "color=\(renderer.colorPixelFormat.rawValue) depth=\(renderer.depthPixelFormat.rawValue) stencil=\(renderer.stencilPixelFormat.rawValue)"
    }

    func draw(_ f: MTAvatarFace, width w: Int, height h: Int) -> CVPixelBuffer? {
        guard let target = buffer(w, h) else { return nil }
        // The texture wears the renderer's own color format when it is one a BGRA buffer can carry.
        let own = renderer.colorPixelFormat
        let format: MTLPixelFormat = (own == .bgra8Unorm_srgb) ? .bgra8Unorm_srgb : .bgra8Unorm
        var cv: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textures, target, nil, format, w, h, 0, &cv) == kCVReturnSuccess,
              let cv, let color = CVMetalTextureGetTexture(cv) else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        if let z = depthTexture(w, h) {
            pass.depthAttachment.texture = z
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.storeAction = .dontCare
            pass.depthAttachment.clearDepth = 1
            if renderer.stencilPixelFormat != .invalid {
                pass.stencilAttachment.texture = z
                pass.stencilAttachment.loadAction = .clear
                pass.stencilAttachment.storeAction = .dontCare
            }
        }
        // The shorter side sees the whole head, portrait or landscape.
        camera.projectionDirection = min(w, h) == w ? .horizontal : .vertical
        MTAvatarLook.pose(rig, f)
        guard let cb = commands.makeCommandBuffer() else { return nil }
        renderer.render(atTime: CACurrentMediaTime() - born, viewport: CGRect(x: 0, y: 0, width: w, height: h),
                        commandBuffer: cb, passDescriptor: pass)
        cb.commit()
        cb.waitUntilCompleted()
        return target
    }

    private func buffer(_ w: Int, _ h: Int) -> CVPixelBuffer? {
        if pool == nil || width != w || height != h {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
            var p: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &p)
            pool = p
            width = w
            height = h
            depth = nil
        }
        guard let pool else { return nil }
        var px: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &px) == kCVReturnSuccess else { return nil }
        return px
    }

    private func depthTexture(_ w: Int, _ h: Int) -> MTLTexture? {
        let format = renderer.depthPixelFormat
        guard format != .invalid else { return nil }
        if let depth, depth.width == w, depth.height == h { return depth }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
        d.usage = .renderTarget
        d.storageMode = .private
        depth = device.makeTexture(descriptor: d)
        return depth
    }
}

/// THE MASK HAS ONE OWNER: whether it is on, the one door a camera frame passes, the renderer's life. The call screen's
/// mark asks it; the end of the call and the end of video put it out (MontanaCall). CallUIModel.masked is its mirror.
final class MTAvatarMask {
    static let shared = MTAvatarMask()

    /// The avatar needs no more pixels than a small screen: the frame's long side is held to this.
    private static let longSide = 960

    private let lock = NSLock()
    private var on = false
    private var busy = false
    private var renderer: MTAvatarRenderer?
    private var firstFrame = true
    private let queue = DispatchQueue(label: "montana.call.mask", qos: .userInitiated)
    // Read and written on the mask's queue only.
    private var face = MTAvatarFace.rest
    private var faceSeen = false
    private var drawn = 0

    var isOn: Bool {
        lock.lock()
        defer { lock.unlock() }
        return on
    }

    func toggle(why: String) { set(!isOn, why: why) }

    /// On: the renderer is born first -- a mask that cannot draw is refused and the camera goes on as it was. Off: the
    /// renderer is let go; the frame in flight on the queue finishes and is not sent.
    func set(_ want: Bool, why: String) {
        guard want != isOn else { return }
        let made: MTAvatarRenderer? = want ? MTAvatarRenderer() : nil
        if want, made == nil {
            MontanaP2PTrace.mark("call_mask", "refused why=no-renderer by=\(why)")
            return
        }
        lock.lock()
        on = want
        renderer = made
        firstFrame = true
        lock.unlock()
        MontanaP2PTrace.mark("call_mask", "\(want ? "on" : "off") by=\(why) look=\(MTAvatarLook.name) tracker=vision \(made?.formats ?? "")")
        DispatchQueue.main.async { CallUIModel.shared.masked = want }
    }

    /// THE ONE DOOR (FrameCountingCapturerDelegate: the camera's frame at its birth). Off: false, and the frame goes to
    /// the source as always. On: true -- the frame is the mask's; it is read here and never reaches the source. While
    /// the previous frame is still being drawn this one is dropped: the phone's own pace sets the avatar's rate.
    func take(_ frame: RTCVideoFrame, from capturer: RTCVideoCapturer, into sink: RTCVideoCapturerDelegate) -> Bool {
        let px = (frame.buffer as? RTCCVPixelBuffer)?.pixelBuffer
        lock.lock()
        let masked = on
        let r = renderer
        let go = masked && !busy && r != nil && px != nil
        if go { busy = true }
        lock.unlock()
        guard masked else { return false }
        guard go, let r, let px else { return true }
        let rotation = frame.rotation
        let ns = frame.timeStampNs
        queue.async { [weak self] in
            self?.draw(px, rotation: rotation, ns: ns, renderer: r, capturer: capturer, sink: sink)
        }
        return true
    }

    private func draw(_ px: CVPixelBuffer, rotation: RTCVideoRotation, ns: Int64, renderer r: MTAvatarRenderer,
                      capturer: RTCVideoCapturer, sink: RTCVideoCapturerDelegate) {
        let read = MTAvatarTracker.read(px, rotation: rotation)
        face = face.eased(toward: read?.face ?? .rest, by: read == nil ? 0.15 : 0.6)
        if (read != nil) != faceSeen {
            faceSeen = read != nil
            MontanaP2PTrace.markFolded("call_mask_face", faceSeen ? "seen" : "lost", window: 10)
        }
        drawn += 1
        if let raw = read?.raw, drawn % 30 == 1 {
            let words = String(format: "eye_l=%.2f eye_r=%.2f mouth=%.2f yaw=%.2f pitch=%.2f roll=%.2f",
                               raw.eyeL, raw.eyeR, raw.mouth, face.yaw, face.pitch, face.roll)
            MontanaP2PTrace.markFolded("call_mask_raw", words, window: 10)
        }
        let turned = rotation == ._90 || rotation == ._270
        var w = turned ? CVPixelBufferGetHeight(px) : CVPixelBufferGetWidth(px)
        var h = turned ? CVPixelBufferGetWidth(px) : CVPixelBufferGetHeight(px)
        let long = max(w, h)
        if long > Self.longSide {
            w = w * Self.longSide / long
            h = h * Self.longSide / long
        }
        w -= w % 2
        h -= h % 2
        let out = w > 0 && h > 0 ? r.draw(face, width: w, height: h) : nil
        lock.lock()
        busy = false
        let still = on
        let first = firstFrame && out != nil
        if still, out != nil { firstFrame = false }
        lock.unlock()
        guard still, let out else { return }
        sink.capturer(capturer, didCapture: RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: out), rotation: ._0, timeStampNs: ns))
        if first { MontanaP2PTrace.mark("call_mask", "first frame size=\(w)x\(h) face=\(read == nil ? 0 : 1)") }
    }
}
