import Testing
@testable import NanoDeskCore

struct CameraViewfinderTests {
    @Test func irisWaitsForAFrameAndRepeatedPressesCannotStartDuplicateRecordings() {
        var camera = CameraViewfinder(openingDuration: 1)
        camera.open()
        #expect(camera.aperture(at: 8) == 0)
        #expect(camera.pressCenter() == nil)
        camera.receivedFrame(at: 10)
        camera.receivedFrame(at: 10.25)
        #expect(camera.aperture(at: 10.5) == 0.5)
        #expect(camera.pressCenter() == nil)
        #expect(camera.aperture(at: 11) == 1)
        #expect(camera.phase == .ready)
        #expect(camera.pressCenter() == .start)
        #expect(camera.pressCenter() == nil)
        camera.recordingStarted(at: 12)
        #expect(camera.pressCenter() == .stop)
        #expect(camera.pressCenter() == nil)
        camera.saved()
        #expect(camera.phase == .ready)
    }

    @Test func failureAndExitRejectLateFramesAndRecordingCallbacks() {
        var camera = CameraViewfinder()
        camera.open()
        camera.fail("カメラが見つかりません。")
        camera.receivedFrame(at: 1)
        #expect(camera.aperture(at: 2) == 0 && camera.pressCenter() == nil)
        camera.close()
        camera.saved()
        camera.recordingStarted(at: 3)
        camera.receivedFrame(at: 4)
        #expect(camera.phase == .closed)
        camera.open()
        #expect(camera.phase == .waiting)
    }
}
