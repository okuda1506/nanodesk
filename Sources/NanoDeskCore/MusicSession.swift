import Foundation

struct MusicTrack: Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
}

struct MusicPlayback: Equatable, Sendable {
    let track: MusicTrack
    let isPlaying: Bool
    let elapsed: TimeInterval
    let duration: TimeInterval
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

protocol MusicService: Sendable {
    func tracks() async throws -> [MusicTrack]
    func play(_ id: String) async throws -> MusicPlayback
    func snapshot() async throws -> MusicPlayback?
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
    private(set) var tracks: [MusicTrack] = []
    private(set) var playback: MusicPlayback?
    private(set) var artwork: Data?
    private(set) var notice: String?
    private(set) var loadingSongs = false
    private var selections: [Page: Int] = [:]
    private var playingBackPage: Page = .songs
    private var busy = false
    private var polling = false
    private var revision = 0
    private var artworkID: String?
    var changed: (() -> Void)?

    init(service: any MusicService) { self.service = service }

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

    func scroll(steps: Int) {
        let count = switch page {
        case .home, .music: menuItems.count
        case .songs: tracks.count
        case .playing: 0
        }
        guard count > 0, steps != 0 else { return }
        let next = max(0, min(count - 1, selection + steps))
        guard next != selection else { return }
        selections[page] = next
        if page == .home || page == .music { notice = nil }
        changed?()
    }

    func press(_ button: WheelButton) async {
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
                case .songs: await showSongs()
                case .playing: await showPlaying()
                default:
                    notice = "この項目は未対応です。"
                    changed?()
                }
            case .songs:
                if tracks.indices.contains(selection) { await play(tracks[selection].id) }
                else if notice != nil { await showSongs() }
            case .playing:
                break
            }
        case .playPause:
            guard page == .playing, playback != nil else { return }
            await run { requested in
                let value = try await self.service.togglePlayback()
                if requested == self.revision { self.install(value) }
            }
        case .previous, .next:
            guard page == .playing,
                  let current = playback?.track.id, let index = tracks.firstIndex(where: { $0.id == current }) else {
                return
            }
            let next = index + (button == .next ? 1 : -1)
            if tracks.indices.contains(next) { await play(tracks[next].id) }
        case .menu:
            break
        }
    }

    func refreshPlayback(initial: Bool = false) async {
        guard page == .playing, !busy, !polling, notice == nil,
              initial || playback != nil else { return }
        polling = true
        defer { polling = false }
        let requested = revision
        do {
            let value = try await service.snapshot()
            guard requested == revision else { return }
            install(value)
            await loadArtworkIfNeeded()
        } catch {
            guard requested == revision else { return }
            notice = (error as? MusicIssue ?? .failed).message
            changed?()
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
        await run { requested in
            let list: [MusicTrack]
            do { list = try await self.service.tracks() }
            catch {
                if requested == self.revision { self.tracks = []; self.selections[.songs] = nil }
                throw error
            }
            var seen = Set<String>()
            let previous = self.selections[.songs, default: 0]
            let selected = self.tracks.indices.contains(previous) ? self.tracks[previous].id : nil
            self.tracks = list.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
            self.selections[.songs] = selected.flatMap { id in self.tracks.firstIndex { $0.id == id } } ?? 0
            if requested == self.revision, self.tracks.isEmpty { self.notice = "ライブラリに曲がありません。" }
        }
    }

    private func showPlaying() async {
        playingBackPage = page
        transition(to: .playing)
        await refreshPlayback(initial: true)
    }

    private func play(_ id: String) async {
        await run { requested in
            let value = try await self.service.play(id)
            guard self.revision == requested else { return }
            if self.page != .playing {
                self.playingBackPage = self.page
                self.transition(to: .playing)
            }
            if let index = self.tracks.firstIndex(where: { $0.id == id }) {
                self.selections[.songs] = index
            }
            self.install(value)
            await self.loadArtworkIfNeeded()
        }
    }

    private func install(_ value: MusicPlayback?) {
        if playback?.track.id != value?.track.id {
            artwork = nil
            artworkID = nil
        }
        if playback != value {
            playback = value
            changed?()
        }
    }

    private func loadArtworkIfNeeded() async {
        guard page == .playing, let id = playback?.track.id, artworkID != id else { return }
        artworkID = id
        if let data = try? await service.artwork(for: id), playback?.track.id == id {
            artwork = data
            changed?()
        }
    }

    private func run(_ work: (Int) async throws -> Void) async {
        busy = true
        revision += 1
        let requested = revision
        notice = nil
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
