import Foundation

struct MusicTrack: Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
    var album: String = ""
    var albumArtist: String = ""
    var sortAlbumArtist: String = ""
    var isCompilation = false
    var discNumber = 0
    var trackNumber = 0
}

struct MusicPlayback: Equatable, Sendable {
    enum RepeatMode: Int, Sendable { case off, one, all }

    let track: MusicTrack
    let isPlaying: Bool
    let elapsed: TimeInterval
    let duration: TimeInterval
    var shuffleEnabled = false
    var repeatMode: RepeatMode = .off

    var timeline: (elapsed: String, remaining: String, fraction: Double) {
        let position = elapsed.isFinite ? max(0, elapsed) : 0
        guard duration.isFinite, duration > 0 else { return (Self.time(position), "–:––", 0) }
        let current = min(position, duration)
        return (Self.time(current), "-" + Self.time(floor(duration) - floor(current)), current / duration)
    }

    private static func time(_ seconds: TimeInterval) -> String {
        let value = Int(min(seconds, 359_999))
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

enum MusicIssue: Error, Sendable {
    case denied, unavailable, cannotPlay, failed
    case timedOut, invalidResponse
    case scriptSetup(code: Int?), eventFailed(code: Int?)

    var message: String {
        switch self {
        case .denied: "設定 → プライバシーとセキュリティ → オートメーションで「ミュージック」を許可してください。"
        case .unavailable: "Macで「ミュージック」を開いて、もう一度お試しください。"
        case .cannotPlay: "この曲を再生できません。ミュージックで再生できるか確認してください。"
        case .failed: "ミュージックに接続できませんでした。もう一度お試しください。"
        case .timedOut: "ミュージックの応答がありません。開いてから再試行してください。"
        case .invalidResponse: "ミュージックの曲情報を読み取れませんでした。"
        case .scriptSetup(let code): "ミュージック操作の準備に失敗しました。" + codeSuffix(code)
        case .eventFailed(let code): "ミュージックの操作に失敗しました。" + codeSuffix(code)
        }
    }

    private func codeSuffix(_ code: Int?) -> String {
        code.map { "（コード \($0)）" } ?? ""
    }
}

enum MusicPlayIntent: Sendable {
    case transport, selectSong, selectAlbumTrack
}

protocol MusicService: Sendable {
    func tracks() async throws -> [MusicTrack]
    func play(_ id: String, intent: MusicPlayIntent) async throws -> MusicPlayback
    func snapshot() async throws -> MusicPlayback?
    /// Toggle an active or paused track. Return nil when Music has no current playback.
    func togglePlayback() async throws -> MusicPlayback?
    func artwork(for id: String) async throws -> Data?
}

@MainActor
final class MusicSession {
    enum Page: Hashable { case home, music, songs, playing }

    enum MenuItem: String {
        case music = "ミュージック", videos = "ビデオ", photos = "写真", podcast = "Podcast"
        case radio = "ラジオ", camera = "ビデオカメラ", extras = "エクストラ", settings = "設定"
        case shuffle = "曲をシャッフル", playing = "再生中"
        case coverFlow = "Cover Flow", geniusMix = "Genius Mix", playlists = "プレイリスト"
        case artists = "アーティスト", albums = "アルバム", songs = "曲", genres = "ジャンル"
        case composers = "作曲者", audiobooks = "オーディオブック", search = "検索"
    }

    private static let homeItems: [MenuItem] = [
        .music, .videos, .photos, .podcast, .radio, .camera, .extras, .settings, .shuffle, .playing
    ]
    private static let musicItems: [MenuItem] = [
        .coverFlow, .geniusMix, .playlists, .artists, .albums, .songs, .genres, .composers, .audiobooks, .search
    ]

    private let service: any MusicService
    private(set) var page: Page = .home
    private(set) var tracks: [MusicTrack] = [] {
        didSet { updateTrackNumber(for: playback?.track.id) }
    }
    private(set) var playback: MusicPlayback?
    private(set) var playingTrackNumber: Int?
    private(set) var artwork: Data?
    private(set) var notice: String?
    private(set) var loadingSongs = false
    private var selections: [Page: Int] = [:]
    private var playingBackPage: Page = .songs
    private var busy = false
    private var pollingRevision: Int?
    private var revision = 0
    private var artworkID: String?
    var changed: (() -> Void)?

    let covers: CoverFlowBrowser
    var orientDevice: ((LandscapeSide?) -> Void)?

    init(service: any MusicService) {
        self.service = service
        covers = CoverFlowBrowser(service: service)
        covers.libraryLoaded = { [weak self] tracks in self?.installLibrary(tracks) }
        covers.changed = { [weak self] in self?.changed?() }
    }

    func setLandscape(_ side: LandscapeSide?) {
        guard side != covers.side else { return }
        notice = nil
        covers.orient(side, currentTrack: playback?.track.id)
    }

    var menuItems: [MenuItem] {
        switch page {
        case .home: Self.homeItems
        case .music: playback == nil ? Self.musicItems : Self.musicItems + [.playing]
        case .songs, .playing: []
        }
    }

    var selection: Int {
        let index = selections[page, default: 0]
        // The music shortcut disappears when the current track ends.
        return page == .music ? min(index, menuItems.count - 1) : index
    }

    func scroll(steps: Int, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if covers.side != nil {
            if steps != 0 { notice = nil }
            covers.scroll(steps, at: time)
            return
        }
        let count = switch page {
        case .home, .music: menuItems.count
        case .songs: tracks.count
        case .playing: 0
        }
        guard count > 0, steps != 0 else { return }
        let next = max(0, min(count - 1, selection + steps))
        guard next != selection else { return }
        selections[page] = next
        notice = nil
        changed?()
    }

    func press(_ button: WheelButton) async {
        if covers.side != nil {
            switch button {
            case .menu:
                notice = nil
                if covers.trackIndex != nil { covers.closeAlbum() }
                else {
                    setLandscape(nil)
                    orientDevice?(nil)
                }
                return
            case .select:
                guard !busy else { return }
                if let track = covers.selectedTrack {
                    await run { try await self.play(track.id, intent: .selectAlbumTrack, requested: $0) }
                } else if covers.album != nil {
                    covers.openAlbum()
                } else {
                    covers.load(currentTrack: playback?.track.id)
                }
                return
            default: break
            }
        }
        if button == .menu {
            notice = nil
            revision += 1
            page = switch page {
            case .home, .music: .home
            case .songs: .music
            case .playing: playingBackPage
            }
            changed?()
            return
        }
        guard !busy else { return }
        switch button {
        case .select:
            switch page {
            case .home, .music:
                switch menuItems[selection] {
                case .music: transition(to: .music)
                case .coverFlow:
                    orientDevice?(.left)
                    setLandscape(.left)
                case .songs: await showSongs()
                case .playing: await showPlaying()
                default:
                    notice = "この項目は未対応です。"
                    changed?()
                }
            case .songs:
                if tracks.indices.contains(selection) {
                    let id = tracks[selection].id
                    await run { try await self.play(id, intent: .selectSong, requested: $0) }
                } else {
                    await showSongs()
                }
            case .playing:
                break
            }
        case .playPause, .previous, .next:
            let startIndex = page == .songs ? selection : 0
            let coverStart = covers.side == nil ? nil : covers.selectedTrack ?? covers.album?.tracks.first
            await run(keepNotice: page == .songs && tracks.isEmpty) { requested in
                try await self.transport(button, startIndex: startIndex, coverStart: coverStart, requested: requested)
            }
        case .menu:
            break
        }
    }

    func refreshPlayback(initial: Bool = false) async {
        guard !busy, pollingRevision != revision, notice == nil else { return }
        if covers.side == nil {
            switch page {
            case .songs: guard !loadingSongs, !tracks.isEmpty else { return }
            case .playing: guard initial || playback != nil else { return }
            case .home, .music: return
            }
        } else if covers.album == nil { return }
        let requested = revision
        pollingRevision = requested
        defer { if pollingRevision == requested { pollingRevision = nil } }
        do {
            let value = try await service.snapshot()
            guard requested == revision else { return }
            install(value)
            await loadArtworkIfNeeded()
        } catch {
            guard requested == revision else { return }
            if page == .songs || covers.side != nil {
                install(nil)
            } else {
                notice = (error as? MusicIssue ?? .failed).message
                changed?()
            }
        }
    }

    private func transition(to page: Page) {
        self.page = page
        notice = nil
        revision += 1
        changed?()
    }

    private func showSongs() async {
        loadingSongs = true
        if page != .songs { transition(to: .songs) }
        await run { try await self.reloadTracks(requested: $0) }
        if page == .songs { await refreshPlayback() }
    }

    private func reloadTracks(requested: Int) async throws {
        let list: [MusicTrack]
        do { list = try await service.tracks() }
        catch {
            if requested == revision { tracks = []; selections[.songs] = nil }
            throw error
        }
        guard requested == revision else { return }
        installLibrary(list)
        notice = tracks.isEmpty ? "ライブラリに曲がありません。" : nil
    }

    private func installLibrary(_ list: [MusicTrack]) {
        var seen = Set<String>()
        let previous = selections[.songs, default: 0]
        let selected = tracks.indices.contains(previous) ? tracks[previous].id : nil
        tracks = list.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
        selections[.songs] = selected.flatMap { id in tracks.firstIndex { $0.id == id } } ?? 0
    }

    private func showPlaying() async {
        playingBackPage = page
        transition(to: .playing)
        await refreshPlayback(initial: true)
    }

    private func transport(_ button: WheelButton, startIndex: Int, coverStart: MusicTrack?, requested: Int) async throws {
        if button == .playPause {
            let current = try await service.togglePlayback()
            install(current)
            if current != nil {
                await loadArtworkIfNeeded()
                return
            }
        } else {
            let current = try await service.snapshot()
            install(current)
            guard current != nil else { return }
        }
        guard revision == requested else { return }
        if button == .playPause, let coverStart {
            try await play(coverStart.id, intent: .transport, requested: requested)
            return
        }
        if tracks.isEmpty { try await reloadTracks(requested: requested) }
        guard revision == requested, !tracks.isEmpty else { return }

        let index: Int
        if button == .playPause {
            index = startIndex
        } else {
            guard let number = playingTrackNumber else {
                notice = "再生中の曲はこの曲一覧にありません。"
                return
            }
            index = number - 1 + (button == .next ? 1 : -1)
        }
        guard tracks.indices.contains(index) else { return }
        try await play(tracks[index].id, intent: .transport, requested: requested)
    }

    private func play(_ id: String, intent: MusicPlayIntent, requested: Int) async throws {
        let value = try await service.play(id, intent: intent)
        install(value)
        guard revision == requested else { return }
        if intent != .transport && page != .playing {
            playingBackPage = page
            transition(to: .playing)
        }
        if page == .playing, let number = playingTrackNumber { selections[.songs] = number - 1 }
        await loadArtworkIfNeeded()
    }

    private func install(_ value: MusicPlayback?) {
        let trackChanged = playback?.track.id != value?.track.id
        let stateChanged = playback?.isPlaying != value?.isPlaying
        if trackChanged {
            updateTrackNumber(for: value?.track.id)
            artwork = nil
            artworkID = nil
        }
        if playback != value {
            playback = value
            if (page != .songs && covers.side == nil) || trackChanged || stateChanged { changed?() }
        }
    }

    private func updateTrackNumber(for id: String?) {
        playingTrackNumber = id.flatMap { id in tracks.firstIndex(where: { $0.id == id }) }.map { $0 + 1 }
    }

    private func loadArtworkIfNeeded() async {
        guard covers.side == nil, page == .playing || page == .home, let id = playback?.track.id, artworkID != id else { return }
        artworkID = id
        if let data = try? await service.artwork(for: id), playback?.track.id == id {
            artwork = data
            changed?()
        }
    }

    private func run(keepNotice: Bool = false, _ work: (Int) async throws -> Void) async {
        busy = true
        revision += 1
        let requested = revision
        if !keepNotice { notice = nil }
        changed?()
        defer {
            busy = false
            loadingSongs = false
            changed?()
        }
        do { try await work(requested) }
        catch {
            guard requested == revision else { return }
            notice = (error as? MusicIssue ?? .failed).message
        }
    }
}
