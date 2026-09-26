import Foundation
import Metal
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// Linear-space RGBA colour for UI drawing. Construct from sRGB hex values.
struct Color: Equatable {
    var r: Float, g: Float, b: Float, a: Float

    init(linear r: Float, _ g: Float, _ b: Float, _ a: Float = 1) { self.r = r; self.g = g; self.b = b; self.a = a }

    init(hex: UInt32, alpha: Float = 1) {
        func lin(_ v: UInt32) -> Float {
            let c = Float(v) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        r = lin((hex >> 16) & 0xFF); g = lin((hex >> 8) & 0xFF); b = lin(hex & 0xFF); a = alpha
    }

    func alpha(_ a: Float) -> Color { Color(linear: r, g, b, a) }
    func mix(_ o: Color, _ t: Float) -> Color {
        Color(linear: r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t, a + (o.a - a) * t)
    }
    func scaled(_ k: Float) -> Color { Color(linear: r * k, g * k, b * k, a) }
    var simd: SIMD4<Float> { SIMD4(r, g, b, a) }

    static let white = Color(linear: 1, 1, 1, 1)
    static let black = Color(linear: 0, 0, 0, 1)
    static let clear = Color(linear: 0, 0, 0, 0)
}

struct Rect: Equatable {
    var x: Float, y: Float, w: Float, h: Float

    init(_ x: Float, _ y: Float, _ w: Float, _ h: Float) { self.x = x; self.y = y; self.w = w; self.h = h }

    var minX: Float { x }
    var minY: Float { y }
    var maxX: Float { x + w }
    var maxY: Float { y + h }
    var midX: Float { x + w / 2 }
    var midY: Float { y + h / 2 }
    var center: SIMD2<Float> { SIMD2(midX, midY) }

    func contains(_ p: SIMD2<Float>) -> Bool { p.x >= x && p.x < x + w && p.y >= y && p.y < y + h }
    func inset(_ d: Float) -> Rect { Rect(x + d, y + d, w - 2 * d, h - 2 * d) }
    func inset(dx: Float, dy: Float) -> Rect { Rect(x + dx, y + dy, w - 2 * dx, h - 2 * dy) }
    func offset(_ dx: Float, _ dy: Float) -> Rect { Rect(x + dx, y + dy, w, h) }
    func scaled(_ s: Float) -> Rect { Rect(midX - w * s / 2, midY - h * s / 2, w * s, h * s) }
    func intersection(_ o: Rect) -> Rect {
        let nx = max(x, o.x), ny = max(y, o.y)
        return Rect(nx, ny, max(0, min(maxX, o.maxX) - nx), max(0, min(maxY, o.maxY) - ny))
    }
    static func centered(w: Float, h: Float, in r: Rect) -> Rect { Rect(r.midX - w / 2, r.midY - h / 2, w, h) }
}

enum TextAlign { case left, center, right }

struct UIVertex {
    var pos: SIMD2<Float>
    var uv: SIMD2<Float>
    var color: SIMD4<Float>
    var rect: SIMD4<Float>
    var params: SIMD4<Float>
}

/// Batched 2D renderer for menus, HUD and inventory. Geometry is specified in
/// points; SDF shading keeps edges and text crisp at any Retina scale.
final class UIRenderer {
    private struct Command {
        var start: Int
        var count: Int
        var image: MTLTexture?
        var clip: Rect?
    }

    let renderer: Renderer
    let font: FontAtlas
    let pipeline: MTLRenderPipelineState
    private var vertices: [UIVertex] = []
    private var commands: [Command] = []
    private var buffers: [MTLBuffer?] = [nil, nil, nil]
    private var bufferCursor = 0
    private var clipStack: [Rect] = []
    private var currentImage: MTLTexture?
    private(set) var size = SIMD2<Float>(1, 1)
    private(set) var scale: Float = 2

    /// Global alpha multiplier (screen transitions).
    var opacity: Float = 1

    init(renderer: Renderer) throws {
        self.renderer = renderer
        font = try FontAtlas(device: renderer.device)

        let vd = MTLVertexDescriptor()
        let formats: [(MTLVertexFormat, Int)] = [(.float2, 0), (.float2, 8), (.float4, 16), (.float4, 32), (.float4, 48)]
        for (i, (f, o)) in formats.enumerated() {
            vd.attributes[i].format = f
            vd.attributes[i].offset = o
            vd.attributes[i].bufferIndex = 0
        }
        vd.layouts[0].stride = MemoryLayout<UIVertex>.stride

        let d = MTLRenderPipelineDescriptor()
        d.label = "UI"
        guard let vf = renderer.library.makeFunction(name: "ui_vertex"), let ff = renderer.library.makeFunction(name: "ui_fragment") else {
            throw Renderer.RendererError.resource("UI shader functions missing")
        }
        d.vertexFunction = vf
        d.fragmentFunction = ff
        d.vertexDescriptor = vd
        d.colorAttachments[0].pixelFormat = renderer.colorFormat
        d.colorAttachments[0].isBlendingEnabled = true
        d.colorAttachments[0].sourceRGBBlendFactor = .one
        d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        d.colorAttachments[0].sourceAlphaBlendFactor = .one
        d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        d.depthAttachmentPixelFormat = renderer.depthFormat
        pipeline = try renderer.device.makeRenderPipelineState(descriptor: d)
        vertices.reserveCapacity(16_384)
        precondition(MemoryLayout<UIVertex>.stride == 64, "UIVertex layout must be 64 bytes")
    }

    func begin(size: SIMD2<Float>, scale: Float) {
        self.size = size
        self.scale = scale
        vertices.removeAll(keepingCapacity: true)
        commands.removeAll(keepingCapacity: true)
        clipStack.removeAll()
        currentImage = nil
        opacity = 1
    }

    // MARK: Batching

    private func ensureCommand() {
        let clip = clipStack.last
        if let last = commands.last, last.image === currentImage, last.clip == clip { return }
        commands.append(Command(start: vertices.count, count: 0, image: currentImage, clip: clip))
    }

    @inline(__always) private func quad(_ p0: SIMD2<Float>, _ p1: SIMD2<Float>, _ p2: SIMD2<Float>, _ p3: SIMD2<Float>,
                                        uv: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>),
                                        color: Color, color2: Color? = nil,
                                        rect: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)? = nil,
                                        params: SIMD4<Float>) {
        ensureCommand()
        var top = color.simd, bottom = (color2 ?? color).simd
        top.w *= opacity; bottom.w *= opacity
        let r = rect ?? (.zero, .zero, .zero, .zero)
        vertices.append(UIVertex(pos: p0, uv: uv.0, color: top, rect: r.0, params: params))
        vertices.append(UIVertex(pos: p1, uv: uv.1, color: top, rect: r.1, params: params))
        vertices.append(UIVertex(pos: p2, uv: uv.2, color: bottom, rect: r.2, params: params))
        vertices.append(UIVertex(pos: p3, uv: uv.3, color: bottom, rect: r.3, params: params))
        commands[commands.count - 1].count += 1
    }

    func pushClip(_ r: Rect) {
        let clip = clipStack.last.map { $0.intersection(r) } ?? r
        clipStack.append(clip)
    }
    func popClip() { _ = clipStack.popLast() }

    // MARK: Shapes

    /// Filled rounded rectangle with optional vertical gradient and blur (soft shadows).
    func fill(_ r: Rect, _ color: Color, radius: Float = 0, bottom: Color? = nil, blur: Float = 0) {
        guard color.a > 0 || (bottom?.a ?? 0) > 0 else { return }
        currentImageReset()
        let e = blur * 2 + 1
        let hw = r.w / 2, hh = r.h / 2
        let c = r.center
        let rad = min(radius, min(hw, hh))
        let p0 = SIMD2<Float>(r.x - e, r.y - e), p1 = SIMD2<Float>(r.maxX + e, r.y - e)
        let p2 = SIMD2<Float>(r.maxX + e, r.maxY + e), p3 = SIMD2<Float>(r.x - e, r.maxY + e)
        let rect = (SIMD4(p0.x - c.x, p0.y - c.y, hw, hh), SIMD4(p1.x - c.x, p1.y - c.y, hw, hh),
                    SIMD4(p2.x - c.x, p2.y - c.y, hw, hh), SIMD4(p3.x - c.x, p3.y - c.y, hw, hh))
        quad(p0, p1, p2, p3, uv: (.zero, .zero, .zero, .zero), color: color, color2: bottom, rect: rect,
             params: SIMD4(rad, blur, 0, 0))
    }

    func stroke(_ r: Rect, _ color: Color, radius: Float = 0, width: Float = 1, bottom: Color? = nil) {
        currentImageReset()
        let e: Float = 2
        let hw = r.w / 2, hh = r.h / 2
        let c = r.center
        let p0 = SIMD2<Float>(r.x - e, r.y - e), p1 = SIMD2<Float>(r.maxX + e, r.y - e)
        let p2 = SIMD2<Float>(r.maxX + e, r.maxY + e), p3 = SIMD2<Float>(r.x - e, r.maxY + e)
        let rect = (SIMD4(p0.x - c.x, p0.y - c.y, hw, hh), SIMD4(p1.x - c.x, p1.y - c.y, hw, hh),
                    SIMD4(p2.x - c.x, p2.y - c.y, hw, hh), SIMD4(p3.x - c.x, p3.y - c.y, hw, hh))
        quad(p0, p1, p2, p3, uv: (.zero, .zero, .zero, .zero), color: color, color2: bottom, rect: rect,
             params: SIMD4(min(radius, min(hw, hh)), width, 1, 0))
    }

    func shadow(_ r: Rect, radius: Float, blur: Float, color: Color = Color(linear: 0, 0, 0, 0.45), offset: Float = 4) {
        fill(r.offset(0, offset), color, radius: radius, blur: blur)
    }

    func circle(center: SIMD2<Float>, radius: Float, _ color: Color, ring: Float = 0) {
        currentImageReset()
        let e = radius + 2
        let p0 = center + SIMD2(-e, -e), p1 = center + SIMD2(e, -e), p2 = center + SIMD2(e, e), p3 = center + SIMD2(-e, e)
        let rect = (SIMD4(-e, -e, radius, 0), SIMD4(e, -e, radius, 0), SIMD4(e, e, radius, 0), SIMD4(-e, e, radius, 0))
        quad(p0, p1, p2, p3, uv: (.zero, .zero, .zero, .zero), color: color, rect: rect, params: SIMD4(0, ring, 6, 0))
    }

    func line(from a: SIMD2<Float>, to b: SIMD2<Float>, width: Float, _ color: Color) {
        currentImageReset()
        let d = b - a
        let len = simd_length(d)
        guard len > 0 else { return }
        let n = SIMD2(-d.y, d.x) / len * (width / 2)
        let hw = len / 2, hh = width / 2
        let rect = (SIMD4(-hw, -hh, hw, hh), SIMD4(hw, -hh, hw, hh), SIMD4(hw, hh, hw, hh), SIMD4(-hw, hh, hw, hh))
        quad(a - n, b - n, b + n, a + n, uv: (.zero, .zero, .zero, .zero), color: color, rect: rect, params: SIMD4(0, 0, 0, 0))
    }

    private func currentImageReset() {
        // Shape draws don't sample the image slot, so they can join any batch.
    }

    // MARK: Text

    /// Draws a single line. `y` is the top of the line box. Returns the advance width.
    @discardableResult
    func text(_ string: String, x: Float, y: Float, size: Float, color: Color, face: FontFace = .body,
              align: TextAlign = .left, tracking: Float = 0, shadow: Color? = nil, shadowOffset: Float = 1.5,
              maxWidth: Float? = nil) -> Float {
        var s = string
        var width = font.measure(s, size: size, face: face, tracking: tracking)
        if let maxWidth, width > maxWidth {
            while !s.isEmpty && font.measure(s + "…", size: size, face: face, tracking: tracking) > maxWidth { s.removeLast() }
            s += "…"
            width = font.measure(s, size: size, face: face, tracking: tracking)
        }
        var penX: Float
        switch align {
        case .left: penX = x
        case .center: penX = x - width / 2
        case .right: penX = x - width
        }
        let baseline = y + font.ascent[face.rawValue] * size
        if let shadow {
            emitGlyphs(s, penX: penX + shadowOffset * 0.6, baseline: baseline + shadowOffset, size: size, color: shadow, face: face,
                       tracking: tracking, softness: 0.08)
        }
        emitGlyphs(s, penX: penX, baseline: baseline, size: size, color: color, face: face, tracking: tracking, softness: 0)
        return width
    }

    /// Text vertically centred on `rect` using the cap height.
    @discardableResult
    func text(_ string: String, in rect: Rect, size: Float, color: Color, face: FontFace = .body, align: TextAlign = .center,
              tracking: Float = 0, shadow: Color? = nil, padding: Float = 0) -> Float {
        let cap = font.capHeight[face.rawValue] * size
        let baseline = rect.midY + cap / 2
        let top = baseline - font.ascent[face.rawValue] * size
        let x: Float
        switch align {
        case .left: x = rect.x + padding
        case .center: x = rect.midX
        case .right: x = rect.maxX - padding
        }
        return text(string, x: x, y: top, size: size, color: color, face: face, align: align, tracking: tracking,
                    shadow: shadow, maxWidth: rect.w - padding * 2)
    }

    /// Outlined display text (logo-style titles).
    func outlinedText(_ string: String, x: Float, y: Float, size: Float, fill: Color, fillBottom: Color? = nil,
                      outline: Color, outlineWidth: Float, face: FontFace = .display, align: TextAlign = .center, tracking: Float = 0) {
        let width = font.measure(string, size: size, face: face, tracking: tracking)
        let penX: Float = align == .center ? x - width / 2 : (align == .right ? x - width : x)
        let baseline = y + font.ascent[face.rawValue] * size
        let dilation = outlineWidth / (size / Float(FontAtlas.sourceSize)) / (2 * FontAtlas.spread)
        emitGlyphs(string, penX: penX, baseline: baseline + outlineWidth * 0.8, size: size, color: outline.scaled(0.6), face: face,
                   tracking: tracking, softness: 0.02, dilation: dilation)
        emitGlyphs(string, penX: penX, baseline: baseline, size: size, color: outline, face: face, tracking: tracking,
                   softness: 0, dilation: dilation)
        emitGlyphs(string, penX: penX, baseline: baseline, size: size, color: fill, colorBottom: fillBottom, face: face,
                   tracking: tracking, softness: 0)
    }

    private func emitGlyphs(_ s: String, penX: Float, baseline: Float, size: Float, color: Color, colorBottom: Color? = nil,
                            face: FontFace, tracking: Float, softness: Float, dilation: Float = 0) {
        var pen = penX
        for scalar in s.unicodeScalars {
            guard let g = font.glyph(scalar.value, face) else { continue }
            if g.size.x > 0 {
                let x0 = pen + g.offset.x * size, y0 = baseline + g.offset.y * size
                let x1 = x0 + g.size.x * size, y1 = y0 + g.size.y * size
                let uv = (SIMD2(g.uvMin.x, g.uvMin.y), SIMD2(g.uvMax.x, g.uvMin.y), SIMD2(g.uvMax.x, g.uvMax.y), SIMD2(g.uvMin.x, g.uvMax.y))
                quad(SIMD2(x0, y0), SIMD2(x1, y0), SIMD2(x1, y1), SIMD2(x0, y1), uv: uv, color: color, color2: colorBottom,
                     params: SIMD4(softness, dilation, 2, 0))
            }
            pen += (g.advance + tracking) * size
        }
    }

    // MARK: Images and icons

    func image(_ texture: MTLTexture, _ r: Rect, tint: Color = .white, uv: Rect = Rect(0, 0, 1, 1)) {
        if currentImage !== texture {
            currentImage = texture
        }
        let uvs = (SIMD2(uv.x, uv.y), SIMD2(uv.maxX, uv.y), SIMD2(uv.maxX, uv.maxY), SIMD2(uv.x, uv.maxY))
        quad(SIMD2(r.x, r.y), SIMD2(r.maxX, r.y), SIMD2(r.maxX, r.maxY), SIMD2(r.x, r.maxY), uv: uvs, color: tint,
             params: SIMD4(0, 0, 3, 0))
    }

    /// Isometric 3D block icon (or a flat sprite for plant-like blocks).
    func blockIcon(_ id: BlockID, _ r: Rect, alpha: Float = 1) {
        let reg = renderer.blockRegistry
        guard let info = reg[id] else { return }
        let layers = reg.faceLayers
        if info.shape == .cross || info.shape == .torch || info.shape == .wallTorch {
            let layer = Float(layers[Int(id) * 6])
            let inset = r.inset(r.w * 0.06)
            quad(SIMD2(inset.x, inset.y), SIMD2(inset.maxX, inset.y), SIMD2(inset.maxX, inset.maxY), SIMD2(inset.x, inset.maxY),
                 uv: (SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)), color: Color(linear: 1, 1, 1, alpha),
                 params: SIMD4(1, 0, 4, layer))
            return
        }
        let s = min(r.w / 1.732, r.h / 2) * 0.92
        let cx = r.midX, cy = r.midY
        let hx = s * 0.866, hy = s * 0.5
        let t0 = SIMD2<Float>(cx, cy - s), t1 = SIMD2<Float>(cx + hx, cy - hy)
        let t2 = SIMD2<Float>(cx, cy), t3 = SIMD2<Float>(cx - hx, cy - hy)
        let l2 = SIMD2<Float>(cx, cy + s), l3 = SIMD2<Float>(cx - hx, cy + hy), r2 = SIMD2<Float>(cx + hx, cy + hy)
        let topLayer = Float(layers[Int(id) * 6 + 2])
        let sideL = Float(layers[Int(id) * 6 + 4]), sideR = Float(layers[Int(id) * 6 + 0])
        let cut: Float = info.layer == .cutout ? 1 : 0
        let uvs = (SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
        quad(t0, t1, t2, t3, uv: uvs, color: Color(linear: 1, 1, 1, alpha), params: SIMD4(cut, 0, 4, topLayer))
        quad(t3, t2, l2, l3, uv: uvs, color: Color(linear: 0.66, 0.66, 0.7, alpha), params: SIMD4(cut, 0, 4, sideL))
        quad(t2, t1, r2, l2, uv: uvs, color: Color(linear: 0.46, 0.46, 0.5, alpha), params: SIMD4(cut, 0, 4, sideR))
    }

    func itemIcon(_ item: ItemInfo, _ r: Rect, alpha: Float = 1) {
        if let block = item.block, item.texture == nil {
            blockIcon(block, r, alpha: alpha)
        } else if let tex = item.texture {
            let layer = Float(renderer.itemTextures.layer(tex))
            let inset = r.inset(r.w * 0.04)
            quad(SIMD2(inset.x, inset.y), SIMD2(inset.maxX, inset.y), SIMD2(inset.maxX, inset.maxY), SIMD2(inset.x, inset.maxY),
                 uv: (SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)), color: Color(linear: 1, 1, 1, alpha),
                 params: SIMD4(0, 0, 5, layer))
        }
    }

    // MARK: Encoding

    func encode(_ enc: MTLRenderCommandEncoder, drawableSize: SIMD2<Float>) {
        guard !vertices.isEmpty else { return }
        let byteCount = vertices.count * MemoryLayout<UIVertex>.stride
        bufferCursor = (bufferCursor + 1) % buffers.count
        if (buffers[bufferCursor]?.length ?? 0) < byteCount {
            let capacity = max(byteCount, 1 << 20) * 2
            buffers[bufferCursor] = renderer.device.makeBuffer(length: capacity, options: .storageModeShared)
            buffers[bufferCursor]?.label = "UI Vertices"
        }
        guard let buffer = buffers[bufferCursor] else { return }
        vertices.withUnsafeBytes { buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: byteCount) }

        var uniforms = SIMD4<Float>(size.x, size.y, scale, scale)
        enc.pushDebugGroup("UI")
        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(renderer.depthDisabled)
        enc.setCullMode(.none)
        enc.setVertexBuffer(buffer, offset: 0, index: 0)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
        enc.setFragmentTexture(font.texture, index: 0)
        enc.setFragmentTexture(renderer.blockTextures.texture, index: 2)
        enc.setFragmentTexture(renderer.itemTextures.texture, index: 3)
        enc.setFragmentSamplerState(renderer.linearSampler, index: 0)
        enc.setFragmentSamplerState(renderer.nearestSampler, index: 1)

        let fullScissor = MTLScissorRect(x: 0, y: 0, width: Int(drawableSize.x), height: Int(drawableSize.y))
        for cmd in commands where cmd.count > 0 {
            enc.setFragmentTexture(cmd.image ?? font.texture, index: 1)
            if let clip = cmd.clip {
                let x = max(0, Int((clip.x * scale).rounded(.down))), y = max(0, Int((clip.y * scale).rounded(.down)))
                let w = min(Int(drawableSize.x) - x, Int((clip.w * scale).rounded(.up)))
                let h = min(Int(drawableSize.y) - y, Int((clip.h * scale).rounded(.up)))
                guard w > 0, h > 0 else { continue }
                enc.setScissorRect(MTLScissorRect(x: x, y: y, width: w, height: h))
            } else {
                enc.setScissorRect(fullScissor)
            }
            enc.drawIndexedPrimitives(type: .triangle, indexCount: cmd.count * 6, indexType: .uint32, indexBuffer: renderer.quadIndices,
                                      indexBufferOffset: cmd.start / 4 * 6 * 4)
        }
        enc.setScissorRect(fullScissor)
        enc.popDebugGroup()
    }
}
