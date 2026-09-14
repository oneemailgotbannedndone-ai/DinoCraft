import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import DinoCraftCore

/// Paints the DinoCraft app icon and branding art with Core Graphics:
/// a prehistoric sunset, a volcano, a sauropod silhouette and a voxel grass
/// block rendered from DinoCraft's own textures.
enum IconPainter {
    static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    static func context(_ w: Int, _ h: Int) -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func savePNG(_ image: CGImage, _ url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "AssetForge", code: 3)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "AssetForge", code: 4) }
    }

    static func canvasImage(_ c: Canvas) -> CGImage {
        let ctx = context(c.size, c.size)
        for y in 0..<c.size {
            for x in 0..<c.size {
                let p = c[x, y]
                ctx.setFillColor(CGColor(srgbRed: p.r, green: p.g, blue: p.b, alpha: p.a))
                ctx.fill(CGRect(x: x, y: c.size - 1 - y, width: 1, height: 1))
            }
        }
        return ctx.makeImage()!
    }

    /// Draws a textured parallelogram face using an affine transform.
    static func face(_ ctx: CGContext, _ img: CGImage, origin: CGPoint, u: CGVector, v: CGVector, shade: CGFloat) {
        ctx.saveGState()
        ctx.concatenate(CGAffineTransform(a: u.dx, b: u.dy, c: v.dx, d: v.dy, tx: origin.x, ty: origin.y))
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1 - shade))
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        ctx.restoreGState()
    }

    static func sauropod(_ ctx: CGContext, x: CGFloat, y: CGFloat, s: CGFloat, color: CGColor) {
        ctx.saveGState()
        ctx.translateBy(x: x, y: y)
        ctx.scaleBy(x: s, y: s)
        ctx.setFillColor(color)
        let p = CGMutablePath()
        // Body + tail + neck as one flowing silhouette (units ~ 0...100)
        p.move(to: CGPoint(x: -60, y: 18))
        p.addCurve(to: CGPoint(x: -18, y: 34), control1: CGPoint(x: -45, y: 22), control2: CGPoint(x: -32, y: 34))
        p.addCurve(to: CGPoint(x: 22, y: 40), control1: CGPoint(x: -5, y: 44), control2: CGPoint(x: 12, y: 44))
        p.addCurve(to: CGPoint(x: 42, y: 92), control1: CGPoint(x: 34, y: 52), control2: CGPoint(x: 30, y: 80))
        p.addCurve(to: CGPoint(x: 58, y: 98), control1: CGPoint(x: 46, y: 98), control2: CGPoint(x: 52, y: 100))
        p.addCurve(to: CGPoint(x: 60, y: 92), control1: CGPoint(x: 63, y: 97), control2: CGPoint(x: 64, y: 94))
        p.addCurve(to: CGPoint(x: 48, y: 86), control1: CGPoint(x: 56, y: 90), control2: CGPoint(x: 50, y: 90))
        p.addCurve(to: CGPoint(x: 34, y: 30), control1: CGPoint(x: 42, y: 70), control2: CGPoint(x: 44, y: 40))
        p.addCurve(to: CGPoint(x: 26, y: 16), control1: CGPoint(x: 30, y: 24), control2: CGPoint(x: 28, y: 20))
        p.addLine(to: CGPoint(x: 26, y: 0)); p.addLine(to: CGPoint(x: 18, y: 0)); p.addLine(to: CGPoint(x: 16, y: 12))
        p.addLine(to: CGPoint(x: 8, y: 12)); p.addLine(to: CGPoint(x: 8, y: 0)); p.addLine(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: -2, y: 14)); p.addLine(to: CGPoint(x: -14, y: 14)); p.addLine(to: CGPoint(x: -14, y: 0))
        p.addLine(to: CGPoint(x: -22, y: 0)); p.addLine(to: CGPoint(x: -24, y: 16)); p.addLine(to: CGPoint(x: -30, y: 18))
        p.addCurve(to: CGPoint(x: -60, y: 18), control1: CGPoint(x: -40, y: 16), control2: CGPoint(x: -52, y: 14))
        p.closeSubpath()
        ctx.addPath(p)
        ctx.fillPath()
        ctx.restoreGState()
    }

    static func scene(size: Int, squircle: Bool) -> CGImage {
        let ctx = context(size, size)
        let S = CGFloat(size)
        let inset = squircle ? S * 0.098 : 0
        let rect = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
        if squircle {
            // Soft drop shadow like native macOS icons
            ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.01), blur: S * 0.02, color: rgb(0x000000, 0.35))
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil))
            ctx.setFillColor(rgb(0x2A1B40)); ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil))
            ctx.clip()
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // Sky gradient: twilight purple → magenta → amber horizon
        let sky = CGGradient(colorsSpace: space, colors: [rgb(0x2B1D52), rgb(0x8A3A7A), rgb(0xF0784A), rgb(0xFFC46A)] as CFArray,
                             locations: [0, 0.42, 0.75, 1])!
        ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY + rect.height * 0.35), options: [.drawsAfterEndLocation])
        // Sun
        let sunC = CGPoint(x: rect.midX + rect.width * 0.12, y: rect.minY + rect.height * 0.5)
        let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFF1B8, 1), rgb(0xFFB45A, 0.55), rgb(0xFF7A4A, 0)] as CFArray, locations: [0, 0.35, 1])!
        ctx.drawRadialGradient(glow, startCenter: sunC, startRadius: 0, endCenter: sunC, endRadius: rect.width * 0.42, options: [])
        ctx.setFillColor(rgb(0xFFF4C8)); ctx.fillEllipse(in: CGRect(x: sunC.x - rect.width * 0.13, y: sunC.y - rect.width * 0.13, width: rect.width * 0.26, height: rect.width * 0.26))
        // Stars
        var rng = SplitMix64(seed: 7)
        for _ in 0..<40 {
            let x = rect.minX + CGFloat(rng.nextDouble()) * rect.width, y = rect.minY + rect.height * (0.72 + CGFloat(rng.nextDouble()) * 0.28)
            ctx.setFillColor(rgb(0xFFFFFF, 0.3 + CGFloat(rng.nextDouble()) * 0.5))
            let r = S * 0.0025 * (1 + CGFloat(rng.nextDouble()))
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
        }
        // Volcano
        let volcano = CGMutablePath()
        volcano.move(to: CGPoint(x: rect.minX - S * 0.05, y: rect.minY + rect.height * 0.38))
        volcano.addLine(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.64))
        volcano.addLine(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.64))
        volcano.addLine(to: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.minY + rect.height * 0.36))
        volcano.closeSubpath()
        ctx.addPath(volcano); ctx.setFillColor(rgb(0x4A2A5C)); ctx.fillPath()
        ctx.setFillColor(rgb(0xFF8A3A, 0.9))
        ctx.fillEllipse(in: CGRect(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.625, width: rect.width * 0.1, height: rect.height * 0.03))
        // Smoke plume
        for k in 0..<5 {
            let r = rect.width * (0.04 + CGFloat(k) * 0.018)
            ctx.setFillColor(rgb(0x6A4A7A, 0.35 - CGFloat(k) * 0.05))
            ctx.fillEllipse(in: CGRect(x: rect.minX + rect.width * (0.24 + CGFloat(k) * 0.03) - r, y: rect.minY + rect.height * (0.68 + CGFloat(k) * 0.05) - r, width: r * 2, height: r * 2))
        }
        // Rolling jungle hills
        for (i, hex) in [UInt32(0x3A2458), 0x24203E].enumerated() {
            let hill = CGMutablePath()
            let base = rect.minY + rect.height * (0.4 - CGFloat(i) * 0.08)
            hill.move(to: CGPoint(x: rect.minX, y: rect.minY))
            hill.addLine(to: CGPoint(x: rect.minX, y: base))
            for k in 0...8 {
                let x = rect.minX + rect.width * CGFloat(k) / 8
                let y = base + CGFloat(sin(Double(k) * 1.7 + Double(i) * 2)) * rect.height * 0.03
                hill.addLine(to: CGPoint(x: x, y: y))
            }
            hill.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            hill.closeSubpath()
            ctx.addPath(hill); ctx.setFillColor(rgb(hex)); ctx.fillPath()
        }
        // Sauropod against the sun
        sauropod(ctx, x: rect.midX + rect.width * 0.1, y: rect.minY + rect.height * 0.33, s: rect.width / 260, color: rgb(0x1A1430))

        // Voxel grass block (isometric) in the foreground
        let top = canvasImage(TexturePainter.paintGrassTop())
        let side = canvasImage(TexturePainter.paintGrassSide())
        let edge = rect.width * 0.2
        let cx = rect.minX + rect.width * 0.3, cy = rect.minY + rect.height * 0.08
        let ux = CGVector(dx: edge * 0.866, dy: edge * 0.5), uz = CGVector(dx: -edge * 0.866, dy: edge * 0.5)
        let up = CGVector(dx: 0, dy: edge)
        face(ctx, side, origin: CGPoint(x: cx + uz.dx, y: cy + uz.dy), u: CGVector(dx: -uz.dx, dy: -uz.dy), v: up, shade: 0.72)
        face(ctx, side, origin: CGPoint(x: cx, y: cy), u: ux, v: up, shade: 0.9)
        face(ctx, top, origin: CGPoint(x: cx + uz.dx, y: cy + uz.dy + edge), u: ux, v: CGVector(dx: -uz.dx, dy: -uz.dy), shade: 1)

        // Vignette
        let vignette = CGGradient(colorsSpace: space, colors: [rgb(0x000000, 0), rgb(0x000000, 0.35)] as CFArray, locations: [0.6, 1])!
        ctx.drawRadialGradient(vignette, startCenter: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0,
                               endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width * 0.75, options: [.drawsAfterEndLocation])
        return ctx.makeImage()!
    }

    /// Circular Rich Presence badges: a pickaxe for Survival, a grass block for Creative.
    static func modeBadge(creative: Bool) -> CGImage {
        let size = 512
        let ctx = context(size, size)
        let S = CGFloat(size)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let circle = CGRect(x: 16, y: 16, width: S - 32, height: S - 32)
        ctx.addEllipse(in: circle)
        ctx.clip()
        let colors = creative ? [rgb(0x5FE0C8), rgb(0x1F7A6A)] : [rgb(0xFFC45A), rgb(0xC8561E)]
        let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
        ctx.resetClip()
        ctx.setStrokeColor(rgb(0xFFF4DC, 0.9))
        ctx.setLineWidth(18)
        ctx.strokeEllipse(in: circle.insetBy(dx: 9, dy: 9))
        if creative {
            let top = canvasImage(TexturePainter.paintGrassTop())
            let side = canvasImage(TexturePainter.paintGrassSide())
            let edge: CGFloat = 150
            let cx = S / 2, cy = S * 0.2
            let ux = CGVector(dx: edge * 0.866, dy: edge * 0.5), uz = CGVector(dx: -edge * 0.866, dy: edge * 0.5)
            let up = CGVector(dx: 0, dy: edge)
            face(ctx, side, origin: CGPoint(x: cx + uz.dx, y: cy + uz.dy), u: CGVector(dx: -uz.dx, dy: -uz.dy), v: up, shade: 0.72)
            face(ctx, side, origin: CGPoint(x: cx, y: cy), u: ux, v: up, shade: 0.9)
            face(ctx, top, origin: CGPoint(x: cx + uz.dx, y: cy + uz.dy + edge), u: ux, v: CGVector(dx: -uz.dx, dy: -uz.dy), shade: 1)
        } else {
            let pick = canvasImage(TexturePainter.paintItem("diamond_pickaxe"))
            ctx.interpolationQuality = .none
            ctx.draw(pick, in: CGRect(x: S * 0.2, y: S * 0.2, width: S * 0.6, height: S * 0.6))
        }
        return ctx.makeImage()!
    }

    static func resize(_ img: CGImage, to size: Int) -> CGImage {
        let ctx = context(size, size)
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()!
    }

    static func generate(resources: URL) throws {
        let art = resources.appendingPathComponent("Art")
        try FileManager.default.createDirectory(at: art, withIntermediateDirectories: true)
        let icon = scene(size: 1024, squircle: true)
        try savePNG(icon, art.appendingPathComponent("icon_1024.png"))
        try savePNG(scene(size: 1024, squircle: false), art.appendingPathComponent("discord_large.png"))
        try savePNG(modeBadge(creative: false), art.appendingPathComponent("discord_mode_survival.png"))
        try savePNG(modeBadge(creative: true), art.appendingPathComponent("discord_mode_creative.png"))

        let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("DinoCraft.iconset")
        try? FileManager.default.removeItem(at: iconset)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            try savePNG(resize(icon, to: base), iconset.appendingPathComponent("icon_\(base)x\(base).png"))
            try savePNG(resize(icon, to: base * 2), iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        proc.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "AssetForge", code: 5, userInfo: [NSLocalizedDescriptionKey: "iconutil failed (\(proc.terminationStatus))"])
        }
    }
}
