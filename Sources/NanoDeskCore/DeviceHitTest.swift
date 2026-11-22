import Foundation

enum DeviceHit: Equatable {
    case outside, housing, wheel, holdSwitch
}

struct DeviceHitTest {
    let minimum: SIMD3<Float>
    let maximum: SIMD3<Float>
    let wheelCenter: SIMD3<Float>
    let wheelRadius: Float

    // Footprint of the switch well on the device's X/Z top face, in meters.
    var holdSlot: CGRect = .null

    func hit(origin: SIMD3<Float>, direction: SIMD3<Float>) -> DeviceHit {
        var near: Float = 0
        var far: Float = .infinity
        for axis in 0..<3 {
            if abs(direction[axis]) < 0.000001 {
                if origin[axis] < minimum[axis] || origin[axis] > maximum[axis] { return .outside }
                continue
            }
            let a = (minimum[axis] - origin[axis]) / direction[axis]
            let b = (maximum[axis] - origin[axis]) / direction[axis]
            near = max(near, min(a, b))
            far = min(far, max(a, b))
            if near > far { return .outside }
        }

        if direction.y < -0.000001 {
            let top = (maximum.y - origin.y) / direction.y
            if top >= near, top <= far {
                let point = origin + direction * top
                if holdSlot.contains(CGPoint(x: CGFloat(point.x), y: CGFloat(point.z))) {
                    let radius = holdSlot.height / 2
                    let dx = max(0, abs(CGFloat(point.x) - holdSlot.midX) - (holdSlot.width / 2 - radius))
                    let dz = CGFloat(point.z) - holdSlot.midY
                    if dx * dx + dz * dz <= radius * radius { return .holdSwitch }
                }
            }
        }
        return wheelPoint(origin: origin, direction: direction, near: near, far: far) == nil ? .housing : .wheel
    }

    func wheelPoint(origin: SIMD3<Float>, direction: SIMD3<Float>) -> SIMD2<Float>? {
        guard hit(origin: origin, direction: direction) == .wheel else { return nil }
        return wheelPoint(origin: origin, direction: direction, near: 0, far: .infinity)
    }

    private func wheelPoint(origin: SIMD3<Float>, direction: SIMD3<Float>, near: Float, far: Float) -> SIMD2<Float>? {
        let length = sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
        guard direction.z < -0.45 * length else { return nil }
        let wheelPlane = (wheelCenter.z - origin.z) / direction.z
        guard wheelPlane >= near, wheelPlane <= far else { return nil }
        let offset = origin + direction * wheelPlane - wheelCenter
        guard wheelRadius > 0 else { return nil }
        let point = SIMD2(offset.x, offset.y) / wheelRadius
        return point.x * point.x + point.y * point.y <= 1 ? point : nil
    }
}
