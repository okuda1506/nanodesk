import CoreGraphics
import Foundation
import RealityKit
import simd

enum ReflectionEnvironment {
    private static let width = 512
    private static let height = 256

    @MainActor
    static func load() async throws -> EnvironmentResource {
        let data = await Task.detached(priority: .userInitiated) { makePixels() }.value
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
                bytesPerRow: width * 16, space: space,
                bitmapInfo: [.floatComponents, .byteOrder32Little,
                             CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)],
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else {
            throw DeviceSceneError.reflectionImage
        }
        return try await EnvironmentResource(equirectangular: image, withName: "NanoDesk Reflectance")
    }

    private static func makePixels() -> Data {
        // Broad neutral sources create smooth reflections in polished metal.
        // The only consumer is RealityKit's IBL. The map is never a skybox.
        let upper = simd_normalize(SIMD3<Float>(-0.7, 0.5, 0.6))
        let opposite = simd_normalize(SIMD3<Float>(0.8, 0.2, 0.5))
        let rear = simd_normalize(SIMD3<Float>(0, 0.4, -1))
        var pixels = [SIMD4<Float>]()
        pixels.reserveCapacity(width * height)
        for row in 0..<height {
            let latitude = (0.5 - (Float(row) + 0.5) / Float(height)) * .pi
            let vertical = sin(latitude)
            let radius = cos(latitude)
            for column in 0..<width {
                let azimuth = ((Float(column) + 0.5) / Float(width) - 0.5) * 2 * .pi
                let direction = SIMD3(radius * cos(azimuth), vertical, radius * sin(azimuth))
                let sky = 0.12 + 0.12 * (vertical + 1) / 2
                let energy = sky
                    + 0.78 * lobe(direction, upper)
                    + 0.48 * lobe(direction, opposite)
                    + 0.32 * lobe(direction, rear)
                pixels.append(SIMD4(energy, energy * 0.994, energy * 0.988, 1))
            }
        }
        return pixels.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func lobe(_ direction: SIMD3<Float>, _ axis: SIMD3<Float>) -> Float {
        let cosine = max(0, simd_dot(direction, axis))
        return cosine * cosine * cosine
    }
}
