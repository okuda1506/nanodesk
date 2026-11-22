import Foundation

struct CameraViewfinder {
    enum Phase: Equatable {
        case closed, waiting, opening(TimeInterval), ready, starting, recording(TimeInterval), saving, failed(String)
    }

    private(set) var phase: Phase = .closed
    private let openingDuration: TimeInterval

    init(openingDuration: TimeInterval = 0.8) {
        self.openingDuration = openingDuration.isFinite && openingDuration > 0 ? openingDuration : 0.8
    }

    mutating func open() { phase = .waiting }
    mutating func close() { phase = .closed }
    mutating func fail(_ message: String) { phase = .failed(message) }

    mutating func receivedFrame(at time: TimeInterval) {
        if phase == .waiting { phase = .opening(time) }
    }

    mutating func aperture(at time: TimeInterval) -> Double {
        switch phase {
        case .opening(let start):
            let t = min(1, max(0, (time - start) / openingDuration))
            if t >= 1 { phase = .ready }
            return t * t * (3 - 2 * t)
        case .closed, .waiting, .failed: return 0
        default: return 1
        }
    }

    enum RecordCommand { case start, stop }
    mutating func pressCenter() -> RecordCommand? {
        switch phase {
        case .ready:
            phase = .starting
            return .start
        case .recording:
            phase = .saving
            return .stop
        default: return nil
        }
    }

    mutating func recordingStarted(at time: TimeInterval) {
        if phase == .starting { phase = .recording(time) }
    }

    mutating func saved() {
        if phase == .saving { phase = .ready }
    }
}
