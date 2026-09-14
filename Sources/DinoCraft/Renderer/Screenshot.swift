import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import DinoCraftCore
@testable import DinoCraftGame

enum Screenshot {
    /// Copies `texture` into a CPU-readable texture inside `commandBuffer` and
    /// writes a PNG once the GPU finishes. Must be called before `present`.
    static func capture(_ texture: MTLTexture, commandBuffer: MTLCommandBuffer, device: MTLDevice, to url: URL,
                        completion: (@Sendable (Bool) -> Void)? = nil) {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: texture.width,
                                                            height: texture.height, mipmapped: false)
        desc.storageMode = .shared
        desc.usage = [.shaderRead]
        guard let staging = device.makeTexture(descriptor: desc), let blit = commandBuffer.makeBlitCommandEncoder() else {
            Log.error("Screenshot: could not allocate staging texture", category: "Renderer")
            completion?(false)
            return
        }
        blit.copy(from: texture, to: staging)
        blit.endEncoding()
        commandBuffer.addCompletedHandler { _ in
            let w = staging.width, h = staging.height
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            staging.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            // Force opaque alpha (the swapchain alpha channel is not meaningful).
            for i in stride(from: 3, to: bytes.count, by: 4) { bytes[i] = 255 }
            let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
                      let image = ctx.makeImage(),
                      let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
                CGImageDestinationAddImage(dest, image, nil)
                return CGImageDestinationFinalize(dest)
            }
            if ok { Log.info("Saved screenshot \(url.lastPathComponent)", category: "Renderer") }
            else { Log.error("Failed to write screenshot to \(url.path)", category: "Renderer") }
            completion?(ok)
        }
    }

    static func nextURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        return GamePaths.screenshots.appendingPathComponent("DinoCraft_\(f.string(from: Date())).png")
    }
}
