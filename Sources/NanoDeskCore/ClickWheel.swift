import Foundation

enum WheelButton: Equatable {
    case select, menu, previous, next, playPause

    static func at(_ point: SIMD2<Float>) -> Self {
        let r2 = point.x * point.x + point.y * point.y
        if r2 <= 0.49 * 0.49 { return .select }
        if abs(point.x) > abs(point.y) { return point.x < 0 ? .previous : .next }
        return point.y < 0 ? .playPause : .menu
    }
}

struct ClickWheelGesture {
    private let button: WheelButton
    private var lastAngle: Float?
    private var remainder: Float = 0
    private var dragged = false
    private static let step: Float = .pi / 12

    init(start: SIMD2<Float>) {
        button = .at(start)
        if button != .select { lastAngle = atan2(start.y, start.x) }
    }

    mutating func move(to point: SIMD2<Float>?, distance: CGFloat) -> Int {
        if distance >= 3 || point == nil { dragged = true }
        guard dragged, button != .select else { return 0 }
        guard let point, WheelButton.at(point) != .select else {
            lastAngle = nil
            remainder = 0
            return 0
        }
        let angle = atan2(point.y, point.x)
        defer { lastAngle = angle }
        guard let lastAngle else { return 0 }
        let delta = angle - lastAngle
        // Shortest arc across ±π. Clockwise is down for local +Y up.
        remainder -= atan2(sin(delta), cos(delta))
        let steps = Int(remainder / Self.step)
        remainder -= Float(steps) * Self.step
        return steps
    }

    func release(at point: SIMD2<Float>, distance: CGFloat) -> WheelButton? {
        guard !dragged, distance < 3, WheelButton.at(point) == button else { return nil }
        return button
    }
}
