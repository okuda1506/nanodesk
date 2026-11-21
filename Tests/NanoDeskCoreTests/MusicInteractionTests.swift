import Foundation
import Testing
@testable import NanoDeskCore

private actor MockMusic: MusicService {
    let library: [MusicTrack]
    var issue: MusicIssue?
    var current: MusicPlayback?
    var plays: [String] = []
    var cover: Data?
    var deniedTrack: String?

    init(_ library: [MusicTrack], issue: MusicIssue? = nil, cover: Data? = nil, deniedTrack: String? = nil) {
        self.library = library
        self.issue = issue
        self.cover = cover
        self.deniedTrack = deniedTrack
    }

    func tracks() async throws -> [MusicTrack] {
        if let issue { throw issue }
        return library
    }

    func play(_ id: String) async throws -> MusicPlayback {
        guard let track = library.first(where: { $0.id == id }), id != deniedTrack else {
            throw MusicIssue.cannotPlay
        }
        plays.append(id)
        let next = MusicPlayback(track: track, isPlaying: true, elapsed: 0, duration: 120)
        current = next
        return next
    }

    func snapshot() async throws -> MusicPlayback? { current }

    func togglePlayback() async throws -> MusicPlayback? {
        guard let current else { return nil }
        let next = MusicPlayback(track: current.track, isPlaying: !current.isPlaying,
                                 elapsed: current.elapsed, duration: current.duration)
        self.current = next
        return next
    }

    func artwork(for id: String) async throws -> Data? { cover }

    func restoreAccess() { issue = nil }

    func advance(to position: Double) {
        if let current {
            self.current = MusicPlayback(track: current.track, isPlaying: current.isPlaying,
                                         elapsed: position, duration: current.duration)
        }
    }
}

@MainActor
struct MusicInteractionTests {
    private let first = MusicTrack(id: "A", title: "第一曲", artist: "演奏者")
    private let second = MusicTrack(id: "B", title: "第二曲", artist: "演奏者")

    @Test func oneSongPlaysPausesAndHasNoNeighbors() async {
        let service = MockMusic([first], cover: Data([0, 1, 2]))
        let session = MusicSession(service: service)
        await openSongs(in: session)
        #expect(session.tracks == [first])
        await session.press(.select)
        #expect(session.page == .playing)
        #expect(session.playback?.track == first)
        #expect(session.playback?.isPlaying == true)
        #expect(session.artwork == Data([0, 1, 2]))
        await service.advance(to: 43)
        await session.refreshPlayback()
        #expect(session.playback?.elapsed == 43)
        await session.press(.playPause)
        #expect(session.playback?.isPlaying == false)
        await session.press(.playPause)
        #expect(session.playback?.isPlaying == true)
        await session.press(.next)
        await session.press(.previous)
        #expect(await service.plays == ["A"])
        await session.press(.menu)
        #expect(session.page == .songs)
        await session.press(.menu)
        #expect(session.page == .music)
        await session.press(.menu)
        #expect(session.page == .home)
    }

    @Test func scrollBoundsAndManualNeighborPlayback() async {
        let service = MockMusic([first, second, second])
        let session = MusicSession(service: service)
        await openSongs(in: session)
        #expect(session.tracks == [first, second])
        session.scroll(steps: 10)
        #expect(session.selection == 1)
        session.scroll(steps: -10)
        #expect(session.selection == 0)
        await session.press(.select)
        await session.press(.next)
        #expect(session.playback?.track == second)
        await session.press(.next)
        await session.press(.menu)
        #expect(session.selection == 1)
        await session.press(.select)
        await session.press(.previous)
        #expect(session.playback?.track == first)
        #expect(await service.plays == ["A", "B", "B", "A"])
    }

    @Test func emptyAndDeniedLibraryReportAReason() async {
        let empty = MusicSession(service: MockMusic([]))
        await openSongs(in: empty)
        #expect(empty.tracks.isEmpty && empty.notice == "ライブラリに曲がありません。")
        let denied = MusicSession(service: MockMusic([first], issue: .denied))
        await openSongs(in: denied)
        #expect(denied.tracks.isEmpty && denied.notice == MusicIssue.denied.message)
        await denied.press(.menu)
        #expect(denied.notice == nil && denied.page == .music)
    }

    @Test func centerRetriesAfterAutomationAccessIsRestored() async {
        let service = MockMusic([first], issue: .denied)
        let session = MusicSession(service: service)
        await openSongs(in: session)
        #expect(session.tracks.isEmpty)
        #expect(session.notice == MusicIssue.denied.message)

        await service.restoreAccess()
        await session.press(.select)
        #expect(session.page == .songs)
        #expect(session.tracks == [first])
        #expect(session.notice == nil)
        #expect(await service.plays.isEmpty)
    }

    @Test func failureStaysOnSongsAndDoesNotClaimPlayback() async {
        let session = MusicSession(service: MockMusic([first], deniedTrack: first.id))
        await openSongs(in: session)
        await session.press(.select)
        #expect(session.page == .songs)
        #expect(session.playback == nil)
        #expect(session.notice == MusicIssue.cannotPlay.message)
    }

    private func openSongs(in session: MusicSession) async {
        await session.press(.select)
        #expect(session.page == .music)
        await session.press(.select)
        #expect(session.page == .songs)
    }
}

struct ClickWheelTests {
    private func point(_ degrees: Float, radius: Float = 0.9) -> SIMD2<Float> {
        let angle = degrees * .pi / 180
        return radius * SIMD2(cos(angle), sin(angle))
    }

    @Test func clockwiseAndCounterclockwiseCrossTheSeam() {
        var clockwise = ClickWheelGesture(start: point(-169))
        #expect(clockwise.move(to: point(168), distance: 25) == 1)
        #expect(clockwise.release(at: point(168), distance: 25) == nil)
        var counterclockwise = ClickWheelGesture(start: point(169))
        #expect(counterclockwise.move(to: point(-168), distance: 25) == -1)
    }

    @Test func smallMotionDoesNotActivateScrollOrTurnClickIntoDrag() {
        var gesture = ClickWheelGesture(start: point(90))
        #expect(gesture.move(to: point(89), distance: 1) == 0)
        #expect(gesture.release(at: point(89), distance: 1) == .menu)
        #expect(gesture.move(to: point(81), distance: 7) == 0)
        #expect(gesture.move(to: point(73), distance: 16) == 1)
        #expect(gesture.release(at: point(73), distance: 16) == nil)
    }

    @Test func clickTargetsAndBackwardRay() {
        #expect(WheelButton.at(.zero) == .select)
        #expect(WheelButton.at(point(0)) == .next)
        #expect(WheelButton.at(point(180)) == .previous)
        #expect(WheelButton.at(point(-90)) == .playPause)
        let hit = DeviceHitTest(minimum: [-0.02, -0.045, -0.003], maximum: [0.02, 0.045, 0.003],
                                wheelCenter: [0, -0.026, 0.0029], wheelRadius: 0.01355)
        #expect(hit.wheelPoint(origin: [0, -0.026, 0.25], direction: [0, 0, -1]) == .zero)
        #expect(hit.wheelPoint(origin: [0, -0.026, -0.25], direction: [0, 0, 1]) == nil)
        #expect(hit.wheelPoint(origin: [0, 0.026, 0.25], direction: [0, 0, -1]) == nil)
    }
}
