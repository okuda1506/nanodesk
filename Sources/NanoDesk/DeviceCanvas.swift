import AppKit
import Metal
import QuartzCore

@MainActor
protocol DeviceInput: AnyObject {
    func pointerDown(_ event: NSEvent, at point: CGPoint)
    func pointerDragged(_ event: NSEvent, to point: CGPoint)
    func pointerUp()
    func zoom(by factor: Double)
}

@MainActor
final class DeviceCanvas: NSView {
    weak var input: (any DeviceInput)?
    var onRenderError: ((any Error) -> Void)?

    private let scene: DeviceScene
    private let outputLayer = CAMetalLayer()
    private var pendingDrawable: (any CAMetalDrawable)?
    private var needsFrame = false
    private var hasPresentedFrame = false
    private var renderFailed = false

    init(scene: DeviceScene) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw DeviceSceneError.metalUnavailable }
        self.scene = scene
        super.init(frame: .zero)

        outputLayer.device = device
        outputLayer.pixelFormat = .bgra8Unorm_srgb
        outputLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        outputLayer.framebufferOnly = false
        outputLayer.isOpaque = false
        outputLayer.backgroundColor = CGColor(gray: 0, alpha: 0)
        layer = outputLayer
        wantsLayer = true

        let pinch = NSMagnificationGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delaysPrimaryMouseButtonEvents = false
        pinch.delaysMagnificationEvents = false
        addGestureRecognizer(pinch)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("NanoDesk uses a programmatic window.") }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        requestFrame()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        requestFrame()
    }

    override func layout() {
        super.layout()
        requestFrame()
    }

    func requestFrame() {
        needsFrame = true
        drawIfNeeded()
    }

    private func drawIfNeeded() {
        guard needsFrame, !renderFailed, let window, window.isVisible,
              !hasPresentedFrame || window.occlusionState.contains(.visible),
              pendingDrawable == nil, !bounds.isEmpty else { return }

        let backing = convertToBacking(bounds.size)
        let pixelSize = CGSize(width: backing.width.rounded(), height: backing.height.rounded())
        guard pixelSize.width >= 1, pixelSize.height >= 1 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outputLayer.frame = bounds
        outputLayer.contentsScale = window.backingScaleFactor
        if outputLayer.drawableSize != pixelSize {
            outputLayer.drawableSize = pixelSize
        }
        CATransaction.commit()

        guard let drawable = outputLayer.nextDrawable() else { return }
        needsFrame = false
        pendingDrawable = drawable
        do {
            try scene.render(into: drawable.texture) { [weak self] in
                Task { @MainActor in self?.finishFrame() }
            }
        } catch {
            pendingDrawable = nil
            renderFailed = true
            onRenderError?(error)
        }
    }

    private func finishFrame() {
        pendingDrawable?.present()
        pendingDrawable = nil
        hasPresentedFrame = true
        drawIfNeeded()
    }

    override func mouseDown(with event: NSEvent) {
        input?.pointerDown(event, at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        input?.pointerDragged(event, to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        input?.pointerUp()
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else { return }
        let rate = event.hasPreciseScrollingDeltas ? 0.008 : 0.07
        input?.zoom(by: exp(Double(event.scrollingDeltaY) * rate))
    }

    @objc private func handlePinch(_ gesture: NSMagnificationGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed || gesture.state == .ended else { return }
        let factor = 1 + Double(gesture.magnification)
        // The recognizer accumulates magnification. Rebase it after each step
        // so zoom(by:) receives an incremental factor instead of a total.
        gesture.magnification = 0
        guard factor != 1 else { return }
        input?.zoom(by: factor)
    }
}
