import AppKit
@preconcurrency import AVFoundation

@MainActor
final class VideoCamera {
    private let queue = DispatchQueue(label: "jp.nanodesk.camera", qos: .userInitiated)
    private let visits = DispatchGroup()
    private var capture: CameraCapture?
    private var generation = UUID()
    private var permission: Task<Void, Never>?
    private(set) var frame: CGImage?
    private(set) var hasAudio = false
    private(set) var finder: CameraViewfinder
    var changed: (() -> Void)?
    var saveError: ((String) -> Void)?

    init() {
        let duration = UserDefaults.standard.object(forKey: "CameraIrisDuration") as? Double ?? 0.8
        finder = CameraViewfinder(openingDuration: duration)
    }

    var isOpening: Bool {
        if case .opening = finder.phase { return true }
        return false
    }

    func aperture(at time: TimeInterval) -> Double { finder.aperture(at: time) }

    func handle(_ action: MusicSession.CameraAction) {
        switch action {
        case .open: open()
        case .close: close()
        case .center:
            switch finder.pressCenter() {
            case .start: capture?.record()
            case .stop: capture?.stopRecording()
            case nil: return
            }
            changed?()
        }
    }

    private func open() {
        guard capture == nil else { return }
        finder.open()
        let visit = UUID()
        generation = visit
        let capture = CameraCapture(queue: queue) { [weak self] event in self?.receive(event, visit: visit) }
        self.capture = capture
        visits.enter()
        changed?()
        permission = Task {
            let video = await AVCaptureDevice.requestAccess(for: .video)
            guard !Task.isCancelled else { return }
            guard video else {
                finder.fail("カメラへのアクセスが許可されていません。システム設定の「プライバシーとセキュリティ」で許可してください。")
                changed?()
                return
            }
            let audio = await AVCaptureDevice.requestAccess(for: .audio)
            guard !Task.isCancelled else { return }
            capture.start(microphone: audio)
        }
    }

    private func receive(_ event: CameraCapture.Event, visit: UUID) {
        let errorText = "動画を保存できませんでした。ムービーフォルダの空き容量とアクセス権を確認してください。"
        guard visit == generation else {
            if case .saveFailure = event { saveError?(errorText) }
            return
        }
        switch event {
        case .frame(let image, let audio):
            frame = image
            hasAudio = audio
            finder.receivedFrame(at: ProcessInfo.processInfo.systemUptime)
        case .recording: finder.recordingStarted(at: ProcessInfo.processInfo.systemUptime)
        case .saved: finder.saved()
        case .saveFailure:
            close()
            finder.fail(errorText)
        case .failure(let message): finder.fail(message)
        }
        changed?()
    }

    func close() {
        guard let capture else { return }
        generation = UUID()
        permission?.cancel()
        permission = nil
        self.capture = nil
        frame = nil
        finder.close()
        let visits = self.visits
        capture.close { visits.leave() }
    }

    func finishBeforeQuit(_ done: @escaping @MainActor @Sendable () -> Void) -> Bool {
        close()
        guard visits.wait(timeout: .now()) == .timedOut else { return false }
        visits.notify(queue: .main) { done() }
        return true
    }
}
