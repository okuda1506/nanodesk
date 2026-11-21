import Foundation
import Testing
@testable import NanoDeskCore

struct DesktopInteractionTests {
    @Test func fullTurnsAndRearView() {
        let halfTurn = Float.pi / DeviceOrientation.radiansPerPoint
        let forward = SIMD3<Float>(0, 0, 1)
        var rotation = DeviceOrientation()
        rotation.drag(horizontal: halfTurn, vertical: 0)
        #expect(rotation.worldToDevice(forward).z < -0.9999)
        rotation.drag(horizontal: halfTurn, vertical: 0)
        #expect(rotation.worldToDevice(forward).z > 0.9999)
        rotation.drag(horizontal: 0, vertical: halfTurn)
        #expect(rotation.worldToDevice(forward).z < -0.9999)
        rotation.drag(horizontal: 0, vertical: halfTurn)
        #expect(rotation.worldToDevice(forward).z > 0.9999)
    }

    @Test func extendedDragKeepsAUnitQuaternion() {
        var rotation = DeviceOrientation()
        for _ in 0..<10_000 { rotation.drag(horizontal: 1.75, vertical: -2.1) }
        let (x, y, z, w) = (rotation.quaternion.x, rotation.quaternion.y,
                            rotation.quaternion.z, rotation.quaternion.w)
        #expect(abs(x * x + y * y + z * z + w * w - 1) < 0.00001)
        let before = rotation.quaternion
        rotation.drag(horizontal: .nan, vertical: 1)
        #expect(rotation.quaternion == before)
    }

    @Test func wheelIsReservedOnlyOnTheFront() {
        let hit = DeviceHitTest(minimum: [-0.02, -0.045, -0.003], maximum: [0.02, 0.045, 0.003],
                                wheelCenter: [0, -0.026, 0.0029], wheelRadius: 0.01355)
        #expect(hit.hit(origin: [0, -0.026, 0.25], direction: [0, 0, -1]) == .wheel)
        #expect(hit.hit(origin: [0, -0.026, -0.25], direction: [0, 0, 1]) == .housing)
        #expect(hit.hit(origin: [0.25, -0.026, 0], direction: [-1, 0, 0]) == .housing)
        #expect(hit.hit(origin: [0, 0.024, 0.25], direction: [0, 0, -1]) == .housing)
        #expect(hit.hit(origin: [0.10, 0, 0.25], direction: [0, 0, -1]) == .outside)
    }

    @Test func placementOnSecondaryDisplayAndAfterDisconnect() throws {
        let primary = CGRect(x: 0, y: 25, width: 1440, height: 820)
        let secondary = CGRect(x: -1024, y: 100, width: 1024, height: 720)
        let saved = DesktopPlacement(center: CGPoint(x: -960, y: 490), scale: 1.15)
        let dual = try #require(saved.frame(in: [primary, secondary], preferred: primary))
        #expect(secondary.contains(dual))
        let single = try #require(saved.frame(in: [primary], preferred: primary))
        #expect(primary.contains(single))
        #expect(single.midX > primary.midX)
    }

    @Test func oversizeWindowFitsAndPlacementRoundTrips() throws {
        let visible = CGRect(x: 0, y: 30, width: 960, height: 470)
        let placement = DesktopPlacement(center: CGPoint(x: 940, y: 490), scale: 10,
                                         alwaysOnTop: false, clickThrough: true)
        let data = try JSONEncoder().encode(placement)
        let saved = try JSONDecoder().decode(DesktopPlacement.self, from: data)
        #expect(saved.center == placement.center && saved.scale == placement.scale)
        #expect(!saved.alwaysOnTop && saved.clickThrough)
        let frame = try #require(saved.frame(in: [visible], preferred: visible))
        #expect(visible.contains(frame))
        #expect(frame.width == frame.height && frame.height == visible.height)
        #expect(DesktopPlacement.validScale(.infinity) == 1)
        #expect(saved.frame(in: [], preferred: nil) == nil)
    }
}
