import AppKit

private final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DesktopWindowController: NSWindowController, DeviceInput {
    private static let preferenceKey = "NanoDesk.DesktopPlacement.v1"
    private let scene: DeviceScene
    private let canvas: DeviceCanvas
    private let music: MusicSession
    private let screen: MusicScreenRenderer
    private var playbackPoll: Task<Void, Never>?
    private var screenUpdate: Task<Void, Never>?
    private var screenFrame: Task<Void, Never>?
    private var screenDirty = false
    private var placement: DesktopPlacement

    private enum Drag {
        case holdSwitch(start: CGPoint)
        case rotation(lastPoint: CGPoint)
        case roll(lastPoint: CGPoint)
        case move(mouseOrigin: CGPoint, windowOrigin: CGPoint, side: CGFloat)
        case wheel(start: CGPoint, gesture: ClickWheelGesture)
    }
    private var drag: Drag?

    init(scene: DeviceScene, onRenderError: @escaping (any Error) -> Void) throws {
        self.scene = scene
        let service = MusicAppBridge()
        self.music = MusicSession(service: service)
        self.screen = MusicScreenRenderer(service: service)
        let canvas = try DeviceCanvas(scene: scene)
        self.canvas = canvas
        var settings = UserDefaults.standard.data(forKey: Self.preferenceKey)
            .flatMap { try? JSONDecoder().decode(DesktopPlacement.self, from: $0) } ?? DesktopPlacement()
        settings.scale = DesktopPlacement.validScale(settings.scale)
        placement = settings
        let window = DesktopPanel(
            contentRect: CGRect(x: 0, y: 0, width: DesktopPlacement.defaultSide, height: DesktopPlacement.defaultSide),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isFloatingPanel = false
        window.becomesKeyOnlyIfNeeded = true
        window.isMovableByWindowBackground = false
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.colorSpace = .sRGB
        window.level = settings.alwaysOnTop ? .floating : .normal
        window.ignoresMouseEvents = settings.clickThrough
        window.contentView = canvas

        super.init(window: window)
        canvas.input = self
        canvas.onRenderError = onRenderError
        screen.artworkChanged = { [weak self] in self?.queueScreenUpdate() }
        music.orientDevice = { [weak self] side in
            guard let self else { return }
            self.scene.resetOrientation()
            if let side { self.scene.roll(by: side == .left ? .pi / 2 : -.pi / 2) }
            self.canvas.requestFrame()
        }
        music.changed = { [weak self] in self?.queueScreenUpdate() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(repositionForScreens),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(redrawOnReveal),
            name: NSWindow.didChangeOcclusionStateNotification, object: window
        )
        applyPlacement()
        queueScreenUpdate()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("NanoDesk uses a programmatic window.") }

    var visible: Bool { window?.isVisible == true }
    var alwaysOnTop: Bool { placement.alwaysOnTop }
    var clickThrough: Bool { placement.clickThrough }

    func show() {
        applyPlacement()
        window?.orderFrontRegardless()
        canvas.requestFrame()
        if music.covers.side != nil || screen.frameInterval != nil { queueScreenUpdate() }
        if playbackPoll == nil {
            playbackPoll = Task { [weak self] in
                var clockMinute = Calendar.current.component(.minute, from: .now)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled, let music = self?.music else { break }
                    await music.refreshPlayback()
                    let minute = Calendar.current.component(.minute, from: .now)
                    if (music.page == .playing || music.covers.side != nil) && minute != clockMinute { self?.queueScreenUpdate() }
                    clockMinute = minute
                }
            }
        }
    }

    func hide() {
        pointerUp(at: nil)
        playbackPoll?.cancel()
        playbackPoll = nil
        screenFrame?.cancel()
        screenFrame = nil
        screen.suspendCoverFlow()
        window?.orderOut(nil)
    }

    func resetOrientation() {
        pointerUp(at: nil)
        scene.resetOrientation()
        music.setLandscape(nil)
        canvas.requestFrame()
    }

    func resetPosition() {
        placement.center = nil
        applyPlacement()
    }

    func resetSize() {
        setScale(1)
    }

    func toggleAlwaysOnTop() {
        placement.alwaysOnTop.toggle()
        window?.level = placement.alwaysOnTop ? .floating : .normal
        save()
    }

    func toggleClickThrough() {
        pointerUp(at: nil)
        placement.clickThrough.toggle()
        window?.ignoresMouseEvents = placement.clickThrough
        save()
    }

    func roll(by radians: Float) {
        scene.roll(by: radians)
        updateOrientation()
    }

    private func updateOrientation() {
        music.setLandscape(scene.orientation.landscape(keeping: music.covers.side))
        canvas.requestFrame()
    }

    func zoom(by factor: Double) {
        guard factor > 0, factor.isFinite else { return }
        setScale(placement.scale * factor)
    }

    func pointerDown(_ event: NSEvent, at point: CGPoint) {
        drag = nil
        guard let window else { return }
        let hit = scene.hit(at: point, in: canvas.bounds)
        guard hit != .outside else { return }
        if event.modifierFlags.contains(.option) {
            drag = .move(mouseOrigin: NSEvent.mouseLocation, windowOrigin: window.frame.origin,
                         side: window.frame.width)
        } else if event.clickCount == 2 && hit == .housing {
            resetOrientation()
        } else if event.modifierFlags.contains(.command) {
            drag = .roll(lastPoint: point)
        } else if hit == .housing || event.modifierFlags.contains(.shift) {
            drag = .rotation(lastPoint: point)
        } else if hit == .holdSwitch {
            drag = .holdSwitch(start: point)
        } else if !music.isHeld, let wheel = scene.wheelPoint(at: point, in: canvas.bounds) {
            drag = .wheel(start: point, gesture: ClickWheelGesture(start: wheel))
        }
    }

    func pointerDragged(_ event: NSEvent, to point: CGPoint) {
        switch drag {
        case .holdSwitch(let start):
            let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
            if hypot(delta.x, delta.y) >= 3 {
                scene.drag(by: delta)
                drag = .rotation(lastPoint: point)
                updateOrientation()
            }
        case .rotation(let previous):
            scene.drag(by: CGPoint(x: point.x - previous.x, y: point.y - previous.y))
            drag = .rotation(lastPoint: point)
            updateOrientation()
        case .roll(let previous):
            roll(by: Float(previous.x - point.x) * DeviceOrientation.radiansPerPoint)
            drag = .roll(lastPoint: point)
        case .move(let mouseOrigin, let windowOrigin, let side):
            let mouse = NSEvent.mouseLocation
            let center = CGPoint(x: windowOrigin.x + mouse.x - mouseOrigin.x + side / 2,
                                 y: windowOrigin.y + mouse.y - mouseOrigin.y + side / 2)
            placement.center = center
            applyPlacement(persist: false)
        case .wheel(let start, var gesture):
            let offset = scene.wheelPoint(at: point, in: canvas.bounds)
            let steps = gesture.move(to: offset, distance: hypot(point.x - start.x, point.y - start.y))
            drag = .wheel(start: start, gesture: gesture)
            music.scroll(steps: steps, at: event.timestamp)
        case nil:
            break
        }
    }

    func pointerUp(at point: CGPoint?) {
        if case .holdSwitch(let start) = drag, let point,
           hypot(point.x - start.x, point.y - start.y) < 3,
           scene.hit(at: point, in: canvas.bounds) == .holdSwitch {
            music.toggleHold()
            scene.setHold(music.isHeld)
            canvas.requestFrame()
        }
        if case .wheel(let start, let gesture) = drag, let point,
           let offset = scene.wheelPoint(at: point, in: canvas.bounds),
           let button = gesture.release(at: offset, distance: hypot(point.x - start.x, point.y - start.y)) {
            Task { [music] in await music.press(button) }
        }
        if case .wheel = drag { music.covers.endWheel() }
        if case .move = drag { save() }
        drag = nil
    }

    private func queueScreenUpdate() {
        if music.covers.side != nil, window?.occlusionState.contains(.visible) != true { return }
        screenDirty = true
        guard screenUpdate == nil else { return }
        screenUpdate = Task { [weak self] in
            guard let self else { return }
            defer { screenUpdate = nil }
            var frameStart = ContinuousClock.now
            while screenDirty {
                frameStart = .now
                screenDirty = false
                do {
                    guard let image = screen.image(for: music) else { throw DeviceSceneError.screenUnavailable }
                    try await scene.updateScreen(with: image)
                    canvas.requestFrame()
                } catch {
                    canvas.onRenderError?(error)
                    return
                }
            }
            screenFrame?.cancel()
            screenFrame = nil
            if let interval = screen.frameInterval, window?.occlusionState.contains(.visible) == true {
                let deadline = frameStart.advanced(by: interval)
                screenFrame = Task { [weak self] in
                    do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
                    self?.queueScreenUpdate()
                }
            }
        }
    }

    private func setScale(_ value: Double) {
        placement.scale = DesktopPlacement.validScale(value)
        applyPlacement()
    }

    @objc private func repositionForScreens(_ notification: Notification) {
        pointerUp(at: nil)
        applyPlacement()
    }

    @objc private func redrawOnReveal(_ notification: Notification) {
        canvas.requestFrame()
        if window?.occlusionState.contains(.visible) == true {
            if music.covers.side != nil || screen.frameInterval != nil { queueScreenUpdate() }
        } else {
            screen.suspendCoverFlow()
        }
    }

    private func applyPlacement(persist: Bool = true) {
        guard let window, let frame = placement.frame(in: NSScreen.screens.map(\.visibleFrame),
                                                        preferred: NSScreen.main?.visibleFrame) else { return }
        window.setFrame(frame, display: true)
        if persist { save() }
    }

    private func save() {
        var saved = placement
        if let frame = window?.frame, !frame.isEmpty {
            saved.center = CGPoint(x: frame.midX, y: frame.midY)
        }
        placement = saved
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.preferenceKey)
        }
    }
}
