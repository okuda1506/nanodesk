import Foundation

enum LandscapeSide { case left, right }

struct DeviceOrientation {
    // Imaginary x, y, z followed by real w, matching simd_quatf on macOS.
    private(set) var quaternion = SIMD4<Float>(0, 0, 0, 1)
    static let radiansPerPoint: Float = 0.009

    mutating func drag(horizontal: Float, vertical: Float) {
        guard horizontal.isFinite, vertical.isFinite else { return }
        let yaw = halfAngle(horizontal)
        let pitch = halfAngle(-vertical)
        let aroundUp = SIMD4<Float>(0, sin(yaw), 0, cos(yaw))
        let aroundRight = SIMD4<Float>(sin(pitch), 0, 0, cos(pitch))
        let next = multiply(multiply(aroundUp, aroundRight), quaternion)
        quaternion = next / sqrt(next.x * next.x + next.y * next.y + next.z * next.z + next.w * next.w)
    }

    mutating func roll(by radians: Float) {
        guard radians.isFinite else { return }
        let spin = SIMD4<Float>(0, 0, sin(radians / 2), cos(radians / 2))
        let next = multiply(spin, quaternion)
        quaternion = next / sqrt((next * next).sum())
    }

    func landscape(keeping side: LandscapeSide?) -> LandscapeSide? {
        // Screen-right in device coordinates gives the horizontal component of its up axis.
        let upX = worldToDevice(SIMD3(1, 0, 0)).y
        let upY = worldToDevice(SIMD3(0, 1, 0)).y
        guard worldToDevice(SIMD3(0, 0, 1)).z > 0.45 else { return side }
        let angle = atan2(-upX, upY) * 180 / .pi
        let threshold: Float = side == nil ? 68 : 53
        guard abs(angle) >= threshold, abs(angle) <= 180 - threshold else { return nil }
        return angle > 0 ? .left : .right
    }

    func worldToDevice(_ world: SIMD3<Float>) -> SIMD3<Float> {
        let inverse = -SIMD3(quaternion.x, quaternion.y, quaternion.z)
        let tangent = 2 * cross(inverse, world)
        return world + quaternion.w * tangent + cross(inverse, tangent)
    }

    private func halfAngle(_ points: Float) -> Float {
        (points * Self.radiansPerPoint).truncatingRemainder(dividingBy: 2 * .pi) / 2
    }

    private func multiply(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> SIMD4<Float> {
        let u = SIMD3(a.x, a.y, a.z)
        let v = SIMD3(b.x, b.y, b.z)
        let xyz = a.w * v + b.w * u + cross(u, v)
        let real = a.w * b.w - (u.x * v.x + u.y * v.y + u.z * v.z)
        return SIMD4(xyz.x, xyz.y, xyz.z, real)
    }

    private func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
}
