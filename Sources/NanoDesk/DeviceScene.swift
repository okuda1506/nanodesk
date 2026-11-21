import CoreGraphics
import Foundation
import Metal
import RealityKit
import simd

enum DeviceSceneError: LocalizedError {
    case modelMissing
    case namedPartsMissing([String])
    case unexpectedBounds
    case reflectionImage
    case metalUnavailable

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "The app bundle is missing NanoModel.usdz."
        case .namedPartsMissing(let names):
            return "NanoModel.usdz is missing expected entities: " + names.joined(separator: ", ")
        case .unexpectedBounds:
            return "NanoModel.usdz did not load at the expected meter scale."
        case .reflectionImage:
            return "The metal reflection environment could not be created."
        case .metalUnavailable:
            return "NanoDesk requires a Metal device to render the model."
        }
    }
}

@MainActor
final class DeviceScene {
    private static let cameraDistance: Float = 0.25
    private static let verticalFOV: Float = 26
    private static let lightExposure: Float = 0

    private let renderer: RealityRenderer
    private let pivot: Entity
    private let deviceHitTest: DeviceHitTest
    private var orientation = DeviceOrientation()

    private init(renderer: RealityRenderer, pivot: Entity, deviceHitTest: DeviceHitTest) {
        self.renderer = renderer
        self.pivot = pivot
        self.deviceHitTest = deviceHitTest
    }

    static func load(from bundle: Bundle = .main) async throws -> DeviceScene {
        guard let url = bundle.url(forResource: "NanoModel", withExtension: "usdz") else {
            throw DeviceSceneError.modelMissing
        }
        let device = try await Entity(contentsOf: url)
        let required = ["ScreenSurface", "WheelRing", "CenterButton",
                        "MenuButton", "PreviousButton", "NextButton", "PlayPauseButton"]
        let missing = required.filter { device.findEntity(named: $0) == nil }
        guard missing.isEmpty else { throw DeviceSceneError.namedPartsMissing(missing) }
        guard let wheel = device.findEntity(named: "WheelRing") else {
            throw DeviceSceneError.namedPartsMissing(["WheelRing"])
        }
        // A USD importer can represent the default prim with the asset root's
        // name. Keep Body addressable in either root representation.
        if device.name != "Body", device.findEntity(named: "Body") == nil {
            device.name = "Body"
        }

        let pivot = Entity()
        pivot.name = "DevicePivot"
        let centered = Entity()
        centered.name = "ModelPlacement"
        pivot.addChild(centered)
        centered.addChild(device)
        let bounds = device.visualBounds(relativeTo: pivot)
        let expected = SIMD3<Float>(0.0387, 0.0907, 0.0062)
        guard simd_length(bounds.extents - expected) < 0.001 else {
            throw DeviceSceneError.unexpectedBounds
        }
        centered.position = -bounds.center
        let box = device.visualBounds(relativeTo: pivot)
        let wheelBounds = wheel.visualBounds(relativeTo: pivot)
        let hitTest = DeviceHitTest(
            minimum: box.min, maximum: box.max,
            wheelCenter: SIMD3(wheelBounds.center.x, wheelBounds.center.y, wheelBounds.max.z),
            wheelRadius: min(wheelBounds.extents.x, wheelBounds.extents.y) / 2
        )

        let camera = Entity()
        camera.name = "DesktopCamera"
        camera.position = SIMD3(0, 0, cameraDistance)
        camera.components.set(PerspectiveCameraComponent(
            near: 0.02, far: 2, fieldOfViewInDegrees: verticalFOV, fieldOfViewOrientation: .vertical
        ))

        let environment = try await ReflectionEnvironment.load()
        let renderer = try RealityRenderer()
        renderer.entities.append(contentsOf: [pivot, camera])
        renderer.activeCamera = camera
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 0))
        renderer.cameraSettings.isToneMappingEnabled = true
        renderer.cameraSettings.antialiasing = .multisample4X
        renderer.extendedDynamicRangeOutput = false
        renderer.lighting.resource = environment
        renderer.lighting.intensityExponent = lightExposure
        return DeviceScene(renderer: renderer, pivot: pivot, deviceHitTest: hitTest)
    }

    func drag(by delta: CGPoint) {
        orientation.drag(horizontal: Float(delta.x), vertical: Float(delta.y))
        pivot.orientation = simd_quatf(vector: orientation.quaternion)
    }

    func resetOrientation() {
        orientation = DeviceOrientation()
        pivot.orientation = simd_quatf(vector: orientation.quaternion)
    }

    func hit(at point: CGPoint, in bounds: CGRect) -> DeviceHit {
        guard bounds.contains(point), bounds.width > 0, bounds.height > 0 else { return .outside }
        let halfView = tan(Self.verticalFOV * .pi / 360)
        let x = Float((point.x - bounds.midX) / (bounds.height / 2)) * halfView
        let y = Float((point.y - bounds.midY) / (bounds.height / 2)) * halfView
        return deviceHitTest.hit(
            origin: orientation.worldToDevice(SIMD3(0, 0, Self.cameraDistance)),
            direction: orientation.worldToDevice(SIMD3(x, y, -1))
        )
    }

    func render(into texture: any MTLTexture, completed: @escaping @Sendable () -> Void) throws {
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in completed() })
    }
}
