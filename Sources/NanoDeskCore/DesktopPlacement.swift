import Foundation

struct DesktopPlacement: Codable {
    var center: CGPoint?
    var scale: Double = 1
    var alwaysOnTop = true
    var clickThrough = false

    static let defaultSide: CGFloat = 480
    static let scaleRange = 0.55...1.8
    private static let margin: CGFloat = 24

    static func validScale(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return max(scaleRange.lowerBound, min(value, scaleRange.upperBound))
    }

    func frame(in visibleFrames: [CGRect], preferred: CGRect?) -> CGRect? {
        let screens = visibleFrames.filter { !$0.isEmpty && !$0.isInfinite && !$0.isNull }
        guard let fallback = preferred.flatMap({ screens.contains($0) ? $0 : nil }) ?? screens.first else {
            return nil
        }

        let scale = CGFloat(Self.validScale(scale))
        var screen = fallback
        var proposedCenter: CGPoint?
        if let center, center.x.isFinite, center.y.isFinite {
            let side = Self.defaultSide * scale
            let proposal = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
            // Retain an attached display if the device center lies on it. On a
            // display seam, use the largest visible intersection instead.
            if let containing = screens.first(where: { $0.contains(center) }) {
                screen = containing
                proposedCenter = center
            } else if let overlapping = screens.max(by: {
                Self.overlap($0, proposal) < Self.overlap($1, proposal)
            }), Self.overlap(overlapping, proposal) > 0 {
                screen = overlapping
                proposedCenter = center
            }
        }

        let side = min(Self.defaultSide * scale, screen.width, screen.height)
        let origin = proposedCenter.map { CGPoint(x: $0.x - side / 2, y: $0.y - side / 2) }
            ?? CGPoint(x: screen.maxX - side - Self.margin, y: screen.minY + Self.margin)
        return CGRect(
            x: max(screen.minX, min(origin.x, screen.maxX - side)),
            y: max(screen.minY, min(origin.y, screen.maxY - side)),
            width: side,
            height: side
        )
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
