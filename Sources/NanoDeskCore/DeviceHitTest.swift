import Foundation

enum DeviceHit: Equatable {
    case outside, housing, wheel
}

struct DeviceHitTest {
    let minimum: SIMD3<Float>
    let maximum: SIMD3<Float>
    let wheelCenter: SIMD3<Float>
    let wheelRadius: Float

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

        let length = sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
        guard direction.z < -0.45 * length else { return .housing }
        let wheelPlane = (wheelCenter.z - origin.z) / direction.z
        guard wheelPlane >= near, wheelPlane <= far else { return .housing }
        let offset = origin + direction * wheelPlane - wheelCenter
        return offset.x * offset.x + offset.y * offset.y <= wheelRadius * wheelRadius ? .wheel : .housing
    }
}
