import Foundation
import Testing
@testable import NanoDeskCore

private actor MockMusic: MusicService {
    let library: [MusicTrack]
    var issue: MusicIssue?
    var snapshotIssue: MusicIssue?
    var current: MusicPlayback?
    var plays: [String] = []
    private(set) var libraryRequests = 0
    var cover: Data?
    var deniedTrack: String?

    init(_ library: [MusicTrack], issue: MusicIssue? = nil, cover: Data? = nil, deniedTrack: String? = nil) {
        self.library = library
        self.issue = issue
        self.cover = cover
        self.deniedTrack = deniedTrack
    }

    func tracks() async throws -> [MusicTrack] {
        libraryRequests += 1
        if let issue { throw issue }
        return library
    }

    func play(_ id: String, intent: MusicPlayIntent = .transport) async throws -> MusicPlayback {
        if intent != .transport, let current, current.track.id == id {
            if intent == .selectAlbumTrack, !current.isPlaying {
                return try await togglePlayback()!
            }
            return current
        }
        guard let track = library.first(where: { $0.id == id }), id != deniedTrack else {
            throw MusicIssue.cannotPlay
        }
        plays.append(id)
        let next = MusicPlayback(track: track, isPlaying: true, elapsed: 0, duration: 120)
        current = next
        return next
    }

    func pauseForCamera() async throws -> MusicPlayback? {
        if current?.isPlaying == true { return try await togglePlayback() }
        return current
    }

    func snapshot() async throws -> MusicPlayback? {
        if let snapshotIssue { throw snapshotIssue }
        return current
    }

    func failSnapshot() { snapshotIssue = .timedOut }

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
    private let first = MusicTrack(id: "A", title: "第一曲", artist: "演奏者", album: "第一集")
    private let second = MusicTrack(id: "B", title: "第二曲", artist: "演奏者")

    @Test(arguments: [true, false])
    func centerOpensTheCurrentTrackAtItsLivePosition(isPlaying: Bool) async throws {
        let cover = Data([4, 2])
        let service = MockMusic([first, second], cover: cover)
        let session = MusicSession(service: service)
        await openSongs(in: session)
        session.scroll(steps: 1)

        // Music starts the highlighted song between two list polls.
        _ = try await service.play(second.id)
        await service.advance(to: 43.5)
        if !isPlaying { _ = try await service.togglePlayback() }
        #expect(session.playback == nil)

        await session.press(.select)
        #expect(session.page == .playing && session.notice == nil)
        #expect(session.playback?.track == second && session.playback?.isPlaying == isPlaying)
        #expect(session.playback?.elapsed == 43.5 && session.artwork == cover)
        #expect(try await service.snapshot() == session.playback)
        #expect(await service.plays == [second.id])
        await session.press(.menu)
        #expect(session.page == .songs && session.selection == 1)
    }

    @Test func centerStartsTheSelectedIDWhenMusicHasSwitchedToAnIdenticallyNamedSong() async throws {
        let other = MusicTrack(id: "C", title: first.title, artist: first.artist)
        let service = MockMusic([first, other])
        _ = try await service.play(first.id)
        let session = MusicSession(service: service)
        await openSongs(in: session)
        #expect(session.playback?.track == first)

        _ = try await service.play(other.id)
        await service.advance(to: 56)
        await session.press(.select)
        #expect(session.page == .playing && session.playback?.track == first)
        #expect(session.playback?.elapsed == 0 && session.playback?.isPlaying == true)
        #expect(await service.plays == [first.id, other.id, first.id])
    }

    @Test(arguments: [MusicSession.Page.home, .music, .songs])
    func transportControlsMusicWithoutMovingTheBrowser(page: MusicSession.Page) async throws {
        let third = MusicTrack(id: "C", title: "第三曲", artist: "演奏者")
        let service = MockMusic([first, second, third])
        // Music can already be playing before NanoDesk has opened the library.
        _ = try await service.play(second.id)
        let session = MusicSession(service: service)
        if page == .music { await session.press(.select) }
        if page == .songs { await openSongs(in: session) }
        session.scroll(steps: 2)
        let highlight = session.selection

        await session.press(.playPause)
        #expect(session.page == page && session.selection == highlight)
        #expect(session.playback?.track == second && session.playback?.isPlaying == false)
        await session.press(.playPause)
        #expect(session.playback?.isPlaying == true)
        #expect(await service.libraryRequests == (page == .songs ? 1 : 0))

        // Skip relative to the real Music track, even if our snapshot is stale.
        _ = try await service.play(first.id)
        await session.press(.next)
        #expect(session.page == page && session.selection == highlight && session.playback?.track == second)
        await session.press(.previous)
        await session.press(.previous)
        #expect(session.page == page && session.selection == highlight && session.playback?.track == first)
        #expect(await service.libraryRequests == 1)
        #expect(await service.plays == ["B", "A", "B", "A"])
    }

    @Test func playFromStoppedUsesTheHighlightedSongOrTheFirstLibraryTrack() async {
        let homeService = MockMusic([first, second])
        let home = MusicSession(service: homeService)
        home.scroll(steps: 3)
        await home.press(.next)
        await home.press(.previous)
        #expect(await homeService.libraryRequests == 0)
        await home.press(.playPause)
        #expect(home.page == .home && home.selection == 3 && home.playback?.track == first)
        #expect(await homeService.plays == ["A"])

        let songsService = MockMusic([first, second])
        let songs = MusicSession(service: songsService)
        await openSongs(in: songs)
        songs.scroll(steps: 1)
        await songs.press(.playPause)
        #expect(songs.page == .songs && songs.selection == 1 && songs.playback?.track == second)
        await songs.press(.next)
        #expect(await songsService.plays == ["B"])
    }

    @Test func transportReportsEmptyOrDeniedLibrariesAndCanRetryInPlace() async {
        let empty = MusicSession(service: MockMusic([]))
        await openSongs(in: empty)
        await empty.press(.previous)
        await empty.press(.playPause)
        #expect(empty.page == .songs && empty.notice == "ライブラリに曲がありません。")

        let service = MockMusic([first], issue: .denied)
        let session = MusicSession(service: service)
        await session.press(.playPause)
        #expect(session.page == .home && session.notice == MusicIssue.denied.message)
        await service.restoreAccess()
        await session.press(.playPause)
        #expect(session.page == .home && session.playback?.track == first && session.notice == nil)
        await session.press(.previous)
        await session.press(.next)
        #expect(await service.plays == ["A"])
    }

    @Test func menuOrderMatchesTheWheelAndUnavailableItemsStayOnTheirPage() async {
        let service = MockMusic([first])
        let session = MusicSession(service: service)
        #expect(session.menuItems == [
            .music, .videos, .photos, .podcast, .radio, .camera, .extras, .settings, .shuffle, .playing
        ])
        session.scroll(steps: 1)
        await session.press(.select)
        #expect(session.page == .home && session.notice != nil)
        session.scroll(steps: 100)
        #expect(session.menuItems[session.selection] == .playing && session.notice == nil)
        await session.press(.select)
        #expect(session.page == .playing)
        await session.press(.menu)
        #expect(session.page == .home && session.selection == 9)
        session.scroll(steps: -100)
        await session.press(.select)
        #expect(session.menuItems == [
            .coverFlow, .geniusMix, .playlists, .artists, .albums, .songs, .genres, .composers, .audiobooks, .search
        ])
        session.scroll(steps: 1)
        await session.press(.select)
        #expect(session.page == .music && session.selection == 1 && session.notice != nil)
        #expect(await service.libraryRequests == 0)
        session.scroll(steps: 4)
        #expect(session.menuItems[session.selection] == .songs && session.notice == nil)
        await session.press(.select)
        #expect(session.page == .songs)
        #expect(await service.libraryRequests == 1)
        await session.press(.select)
        await session.press(.menu)
        await session.press(.menu)
        #expect(session.page == .music && session.selection == 5)
        session.scroll(steps: 100)
        #expect(session.menuItems[session.selection] == .playing)
        await session.press(.select)
        #expect(session.page == .playing && session.playback?.track == first)
        await session.press(.menu)
        #expect(session.page == .music && session.menuItems[session.selection] == .playing)
    }

    @Test func oneSongPlaysPausesAndHasNoNeighbors() async {
        let service = MockMusic([first], cover: Data([0, 1, 2]))
        let session = MusicSession(service: service)
        await openSongs(in: session)
        #expect(session.tracks == [first])
        await session.press(.select)
        #expect(session.page == .playing)
        #expect(session.playback?.track == first)
        #expect(session.playback?.isPlaying == true)
        #expect(session.playback?.track.album == "第一集" && session.playingTrackNumber == 1)
        #expect(session.artwork == Data([0, 1, 2]))
        await service.advance(to: 43)
        await session.refreshPlayback()
        #expect(session.playback?.elapsed == 43)
        #expect(session.playback?.timeline.remaining == "-1:17")
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
        #expect(session.playingTrackNumber == 2 && session.playback?.track.album == "")
        await session.press(.next)
        await session.press(.menu)
        #expect(session.selection == 1)
        await session.press(.select)
        await session.press(.previous)
        #expect(session.playback?.track == first)
        #expect(await service.plays == ["A", "B", "A"])
    }

    @Test func songListTracksMusicIndependentlyOfTheWheelSelection() async throws {
        let service = MockMusic([first, second], cover: Data([1]))
        _ = try await service.play(second.id)
        let session = MusicSession(service: service)
        await openSongs(in: session)
        #expect(session.selection == 0 && session.playingTrackNumber == 2)
        #expect(session.playback?.isPlaying == true && session.artwork == nil)

        var redraws = 0
        session.changed = { redraws += 1 }
        await service.advance(to: 12)
        await session.refreshPlayback()
        #expect(redraws == 0)
        _ = try await service.togglePlayback()
        await session.refreshPlayback()
        #expect(session.playback?.isPlaying == false && redraws == 1)
        _ = try await service.play(first.id)
        await session.refreshPlayback()
        session.scroll(steps: 1)
        #expect(session.selection == 1 && session.playingTrackNumber == 1)
        await service.failSnapshot()
        await session.refreshPlayback()
        #expect(session.playback == nil && session.tracks == [first, second] && session.notice == nil)
        await session.press(.select)
        #expect(session.page == .playing && session.playback?.track == second)
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

    @Test func playbackClockHandlesUnknownDurationLongTracksAndEndOfTrack() {
        func timeline(_ elapsed: Double, _ duration: Double) -> (elapsed: String, remaining: String, fraction: Double) {
            MusicPlayback(track: first, isPlaying: true, elapsed: elapsed, duration: duration).timeline
        }
        #expect(timeline(59.8, 199.2) == ("0:59", "-2:20", 59.8 / 199.2))
        #expect(timeline(3_661, 7_205) == ("1:01:01", "-59:04", 3_661.0 / 7_205.0))
        #expect(timeline(124, 120) == ("2:00", "-0:00", 1))
        #expect(timeline(-3, 60) == ("0:00", "-1:00", 0))
        #expect(timeline(23, 0) == ("0:23", "–:––", 0))
        #expect(timeline(.nan, .infinity) == ("0:00", "–:––", 0))
    }

    @Test func externalPlaybackHasNoInventedListPosition() async throws {
        let service = MockMusic([first])
        _ = try await service.play(first.id)
        let session = MusicSession(service: service)
        session.scroll(steps: 9)
        await session.press(.select)
        #expect(session.page == .playing && session.playback?.track.album == first.album)
        #expect(session.playingTrackNumber == nil)
        #expect(await service.libraryRequests == 0)
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

    @Test(arguments: [MusicSession.Page.home, .music, .songs, .playing])
    func coverFlowRotatesFromEveryMusicPageAndRestoresTheHighlight(page: MusicSession.Page) async throws {
        let service = MockMusic([first, second])
        let session = MusicSession(service: service)
        if page == .music { await session.press(.select) }
        if page == .songs { await openSongs(in: session) }
        if page == .playing {
            _ = try await service.play(second.id)
            session.scroll(steps: 9)
            await session.press(.select)
        }
        session.scroll(steps: 1)
        let highlight = session.selection
        session.setLandscape(.left)
        await waitForCovers(in: session)
        #expect(session.covers.albums.count == 2)
        let index = session.covers.index
        session.setLandscape(.right)
        #expect(session.covers.index == index && session.covers.side == .right)
        session.setLandscape(nil)
        #expect(session.covers.side == nil && session.page == page && session.selection == highlight)
        #expect(await service.plays.count == (page == .playing ? 1 : 0))
    }

    @Test func menuOpensCoversAndCenterPlaysTheSelectedAlbumTrack() async {
        let t1 = MusicTrack(id: "1", title: "First", artist: "A", album: "Record", trackNumber: 1)
        let t2 = MusicTrack(id: "2", title: "Second", artist: "A", album: "Record", trackNumber: 2)
        let service = MockMusic([t2, t1])
        let session = MusicSession(service: service)
        var turns: [LandscapeSide?] = []
        session.orientDevice = { turns.append($0) }
        await session.press(.select)
        await session.press(.select)
        await waitForCovers(in: session)
        #expect(turns == [.left] && session.covers.album?.tracks == [t1, t2])
        await session.press(.select)
        session.scroll(steps: 1)
        #expect(await service.plays.isEmpty && session.covers.selectedTrack == t2)
        await session.press(.select)
        #expect(await service.plays == ["2"] && session.playingTrackNumber == 1)
        #expect(session.covers.selectedTrack == t2 && session.playback?.isPlaying == true)
        await service.advance(to: 32)
        await session.press(.playPause)
        await session.press(.select)
        #expect(session.playback?.elapsed == 32 && session.playback?.isPlaying == true)
        #expect(await service.plays == ["2"])
        await session.press(.menu)
        #expect(session.covers.trackIndex == nil && session.covers.side == .left)
        await session.press(.menu)
        #expect(turns == [.left, nil] && session.page == .playing)
        await session.press(.menu)
        #expect(session.page == .music && session.selection == 0)
    }

    @Test func coverFlowIndexesAlbumArtistsCompilationsDiscOrderAndNonletters() {
        let tracks = [
            MusicTrack(id: "4", title: "Two", artist: "Guest 1", album: "Set", albumArtist: "Écho", discNumber: 2, trackNumber: 1),
            MusicTrack(id: "3", title: "One", artist: "Guest 2", album: "Set", albumArtist: "Écho", discNumber: 1, trackNumber: 2),
            MusicTrack(id: "5", title: "Title", artist: "Zulu", album: "Set"),
            MusicTrack(id: "6", title: "Title", artist: "123", album: "Numbers"),
            MusicTrack(id: "7", title: "Title", artist: "!Band", album: "Symbols"),
            MusicTrack(id: "8", title: "Title", artist: "かな", album: "歌", sortAlbumArtist: "Kana"),
            MusicTrack(id: "9", title: "Guest A", artist: "A", album: "Collection", isCompilation: true),
            MusicTrack(id: "10", title: "Guest B", artist: "B", album: "Collection", isCompilation: true)
        ]
        let catalog = MusicAlbum.catalog(tracks + [tracks[0]])
        #expect(catalog.map(\.initial) == ["E", "K", "K", "Z", "#", "#"])
        #expect(catalog[0].tracks.map(\.id) == ["3", "4"])
        #expect(catalog.first { $0.title == "Collection" }?.tracks.count == 2)
    }

    @Test func rapidWheelBrowsesInitialsAndReturnsToIndividualAlbums() async throws {
        let names = ["A", "A", "A", "A", "A", "B", "Z", "9"]
        let tracks = names.enumerated().map { MusicTrack(id: String($0.offset), title: "曲", artist: $0.element, album: "LP \($0.offset)") }
        let session = MusicSession(service: MockMusic(tracks))
        session.setLandscape(.left)
        await waitForCovers(in: session)
        for step in 0..<4 { session.scroll(steps: 1, at: Double(step) * 0.028) }
        #expect(session.covers.scanning && session.covers.album?.initial == "A")
        session.scroll(steps: 1, at: 0.13)
        #expect(session.covers.index == 5)
        session.scroll(steps: 5, at: 0.17)
        #expect(session.covers.album?.initial == "#")
        session.scroll(steps: -2, at: 0.20)
        #expect(session.covers.index == 5)
        session.covers.endWheel()
        #expect(!session.covers.scanning)
        session.scroll(steps: -1, at: 1)
        #expect(session.covers.index == 4 && !session.covers.scanning)
        session.scroll(steps: 5, at: 1.04)
        #expect(session.covers.scanning)
        try await Task.sleep(for: .milliseconds(400))
        #expect(!session.covers.scanning)
    }

    @Test func coverFlowCanRetryReadFailuresAndEmptyLibraries() async {
        let service = MockMusic([], issue: .denied)
        let session = MusicSession(service: service)
        session.setLandscape(.right)
        await waitForCovers(in: session)
        #expect(session.covers.notice == MusicIssue.denied.message)
        await service.restoreAccess()
        await session.press(.select)
        await waitForCovers(in: session)
        #expect(session.covers.notice == "ライブラリに曲がありません。")
        session.setLandscape(nil)
        #expect(session.page == .home && session.notice == nil)
    }

    @Test func holdLocksTheWheelAndRotationWhileMusicKeepsPlaying() async throws {
        let service = MockMusic([first, second])
        let session = MusicSession(service: service)
        await openSongs(in: session)
        await session.press(.select)
        session.toggleHold()
        await service.advance(to: 42)
        await session.refreshPlayback()
        #expect(session.playback?.elapsed == 42)
        session.setLandscape(.right)
        #expect(session.covers.side == nil)
        for button: WheelButton in [.menu, .next, .previous, .playPause, .select] {
            await session.press(button)
            #expect(session.page == .playing)
            let current = try await service.snapshot()
            #expect(current?.track == first && current?.isPlaying == true && current?.elapsed == 42)
        }
        session.toggleHold()
        await session.press(.playPause)
        #expect(session.playback?.isPlaying == false)
        await session.press(.menu)
        session.toggleHold()
        session.scroll(steps: 1)
        await session.press(.select)
        #expect(session.page == .songs && session.selection == 0)
        session.toggleHold()
        session.scroll(steps: 1)
        #expect(session.selection == 1)
    }

    @Test func holdKeepsCoverFlowOpenAndPreventsAlbumNavigation() async {
        let session = MusicSession(service: MockMusic([first, second]))
        session.setLandscape(.left)
        await waitForCovers(in: session)
        let album = session.covers.index
        session.toggleHold()
        session.setLandscape(nil)
        session.setLandscape(.right)
        session.scroll(steps: 4)
        await session.press(.select)
        await session.press(.menu)
        #expect(session.covers.side == .left && session.covers.index == album)
        #expect(!session.covers.scanning && session.covers.trackIndex == nil)
        session.toggleHold()
        await session.press(.select)
        #expect(session.covers.trackIndex == 0)
        session.setLandscape(nil)
        #expect(session.covers.side == nil)
    }

    @Test func cameraOwnsTheWheelAndReturnsToItsHighlightedHomeItem() async throws {
        let service = MockMusic([first])
        _ = try await service.play(first.id)
        let session = MusicSession(service: service)
        var actions: [MusicSession.CameraAction] = []
        session.cameraAction = { actions.append($0) }
        session.scroll(steps: 5)
        #expect(session.menuItems[session.selection] == .camera)
        await session.press(.select)
        #expect(session.page == .camera && actions == [.open])
        #expect(try await service.snapshot()?.isPlaying == false)
        await session.press(.select)
        session.setLandscape(.left)
        session.scroll(steps: 1)
        await session.press(.playPause)
        #expect(session.covers.side == nil && actions == [.open, .center])
        session.toggleHold()
        await session.press(.select)
        await session.press(.menu)
        #expect(session.page == .camera && actions == [.open, .center])
        session.toggleHold()
        await session.press(.menu)
        #expect(actions == [.open, .center, .close])
        #expect(session.page == .home && session.menuItems[session.selection] == .camera)
        #expect(try await service.snapshot()?.isPlaying == false)
    }

    private func waitForCovers(in session: MusicSession) async {
        let timeout = ContinuousClock.now + .seconds(3)
        while session.covers.loading && ContinuousClock.now < timeout { await Task.yield() }
        #expect(!session.covers.loading)
    }

    private func openSongs(in session: MusicSession) async {
        await session.press(.select)
        #expect(session.page == .music)
        session.scroll(steps: 5)
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
