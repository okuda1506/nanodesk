import Foundation

struct MusicAlbum: Sendable {
    struct ID: Hashable, Sendable {
        let artist: String
        let title: String
    }

    let id: ID
    let artist: String
    let title: String
    let initial: Character
    let tracks: [MusicTrack]

    static func catalog(_ tracks: [MusicTrack]) -> [MusicAlbum] {
        let locale = Locale(identifier: "en_US_POSIX")
        func fold(_ text: String) -> String {
            text.folding(options: [.widthInsensitive, .diacriticInsensitive, .caseInsensitive], locale: locale)
        }
        func artist(_ track: MusicTrack) -> String {
            if !track.albumArtist.isEmpty { return track.albumArtist }
            if track.isCompilation { return "コンピレーション" }
            return track.artist
        }
        var seen = Set<String>()
        let groups = Dictionary(grouping: tracks.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }) {
            ID(artist: fold(artist($0)), title: fold($0.album))
        }
        let albums = groups.map { id, group in
            let ordered = group.sorted {
                ($0.discNumber, $0.trackNumber, $0.title, $0.id) < ($1.discNumber, $1.trackNumber, $1.title, $1.id)
            }
            let track = ordered[0]
            let name = artist(track)
            let sortName = track.sortAlbumArtist.isEmpty ? name : track.sortAlbumArtist
            let latin = sortName.applyingTransform(.toLatin, reverse: false) ?? sortName
            let key = fold(latin).trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: locale)
            let initial = key.first.flatMap { $0.isASCII && $0.isLetter ? $0 : nil } ?? "#"
            return (key, MusicAlbum(id: id, artist: name.isEmpty ? "不明なアーティスト" : name,
                                    title: track.album.isEmpty ? "不明なアルバム" : track.album,
                                    initial: initial, tracks: ordered))
        }
        return albums.sorted { lhs, rhs in
            let a = lhs.1, b = rhs.1
            if a.initial != b.initial { return b.initial == "#" || (a.initial != "#" && a.initial < b.initial) }
            let order = lhs.0.compare(rhs.0, options: .numeric, locale: locale)
            if order != .orderedSame { return order == .orderedAscending }
            return (a.id.artist, a.id.title) < (b.id.artist, b.id.title)
        }.map(\.1)
    }
}

@MainActor
final class CoverFlowBrowser {
    private let service: any MusicService
    private var libraryTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var sections: [Int] = []
    private var ticks: [(time: TimeInterval, steps: Int)] = []
    private var rememberedAlbum: MusicAlbum.ID?
    private(set) var side: LandscapeSide?
    private(set) var albums: [MusicAlbum] = []
    private(set) var index = 0
    private(set) var trackIndex: Int?
    private(set) var scanning = false
    private(set) var notice: String?
    var libraryLoaded: (([MusicTrack]) -> Void)?
    var changed: (() -> Void)?
    var loading: Bool { libraryTask != nil }
    var album: MusicAlbum? { albums.indices.contains(index) ? albums[index] : nil }
    var selectedTrack: MusicTrack? { trackIndex.flatMap { album?.tracks[$0] } }

    init(service: any MusicService) { self.service = service }

    func orient(_ newSide: LandscapeSide?, currentTrack: String?) {
        guard side != newSide else { return }
        let wasOpen = side != nil
        side = newSide
        if newSide == nil {
            rememberedAlbum = album?.id ?? rememberedAlbum
            libraryTask?.cancel()
            libraryTask = nil
            endWheel()
            trackIndex = nil
            albums = []
            sections = []
        } else if !wasOpen {
            load(currentTrack: currentTrack)
        }
        changed?()
    }

    func load(currentTrack: String?) {
        guard side != nil, libraryTask == nil else { return }
        notice = nil
        libraryTask = Task {
            do {
                let (tracks, catalog) = try await Self.fetchCatalog(service)
                guard !Task.isCancelled else { return }
                libraryLoaded?(tracks)
                albums = catalog
                index = catalog.firstIndex { $0.id == rememberedAlbum }
                    ?? catalog.firstIndex { $0.tracks.contains { $0.id == currentTrack } } ?? 0
                sections = catalog.indices.filter { $0 == 0 || catalog[$0].initial != catalog[$0 - 1].initial }
                notice = catalog.isEmpty ? "ライブラリに曲がありません。" : nil
            } catch {
                guard !Task.isCancelled else { return }
                notice = (error as? MusicIssue ?? .failed).message
            }
            libraryTask = nil
            changed?()
        }
        changed?()
    }

    private nonisolated static func fetchCatalog(_ service: any MusicService) async throws -> ([MusicTrack], [MusicAlbum]) {
        let tracks = try await service.tracks()
        try Task.checkCancellation()
        return (tracks, MusicAlbum.catalog(tracks))
    }

    func openAlbum() {
        guard album != nil else { return }
        endWheel()
        trackIndex = 0
        changed?()
    }

    func closeAlbum() {
        trackIndex = nil
        changed?()
    }

    func scroll(_ steps: Int, at time: TimeInterval) {
        guard steps != 0, let album else { return }
        if let trackIndex {
            self.trackIndex = max(0, min(album.tracks.count - 1, trackIndex + steps))
        } else {
            // Four 15° ticks in one direction inside 150 ms starts letter browsing.
            if ticks.last?.steps.signum() != steps.signum() { ticks.removeAll() }
            ticks.removeAll { time - $0.time > 0.15 }
            ticks.append((time, steps))
            let wasScanning = scanning
            if sections.count > 1 && ticks.reduce(0, { $0 + abs($1.steps) }) >= 4 { scanning = true }
            if scanning {
                let current = sections.lastIndex { $0 <= index } ?? 0
                index = sections[max(0, min(sections.count - 1, current + (wasScanning ? steps : 0)))]
                idleTask?.cancel()
                idleTask = Task {
                    do { try await Task.sleep(for: .milliseconds(320)) } catch { return }
                    endWheel()
                }
            } else {
                index = max(0, min(albums.count - 1, index + steps))
            }
        }
        changed?()
    }

    func endWheel() {
        ticks.removeAll()
        idleTask?.cancel()
        idleTask = nil
        if scanning {
            scanning = false
            changed?()
        }
    }
}

// A critically damped spring carries its current velocity across wheel ticks.
struct CoverFlowMotion {
    private var start = 0.0
    private var speed = 0.0
    private var startTime = 0.0
    private(set) var target = 0

    mutating func move(to index: Int, at time: TimeInterval, snap: Bool) {
        guard index != target || snap else { return }
        let state = sample(at: time)
        start = snap ? Double(index) : state.position
        speed = snap ? 0 : state.velocity
        target = index
        startTime = time
    }

    func sample(at time: TimeInterval) -> (position: Double, velocity: Double, moving: Bool) {
        let t = max(0, time - startTime)
        let delta = start - Double(target)
        let stiffness = 24.0
        let slope = speed + stiffness * delta
        let decay = exp(-stiffness * t)
        let remaining = (delta + slope * t) * decay
        let velocity = (speed - stiffness * slope * t) * decay
        if abs(remaining) < 0.001 && abs(velocity) < 0.025 { return (Double(target), 0, false) }
        return (Double(target) + remaining, velocity, true)
    }
}
