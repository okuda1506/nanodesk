import AppKit
import OSAKit

struct MusicAppBridge: MusicService {
    private static let bundleID = "com.apple.Music"
    private let queue = DispatchQueue(label: "jp.nanodesk.music-automation", qos: .userInitiated)

    func tracks() async throws -> [MusicTrack] {
        try await Self.openMusicIfNeeded()
        return try await work {
            let columns = try Self.execute(.tracks)
            guard columns.numberOfItems == 9, let ids = columns.atIndex(1) else { throw MusicIssue.invalidResponse }
            let fields = (1...9).compactMap { columns.atIndex($0) }
            guard fields.count == 9, fields.allSatisfy({ $0.numberOfItems == ids.numberOfItems }) else {
                throw MusicIssue.invalidResponse
            }
            return (0..<ids.numberOfItems).compactMap { offset in
                let row = offset + 1
                guard let id = ids.atIndex(row)?.stringValue, !id.isEmpty else { return nil }
                return MusicTrack(id: id, title: fields[1].atIndex(row)?.stringValue ?? "",
                                  artist: fields[2].atIndex(row)?.stringValue ?? "",
                                  album: fields[3].atIndex(row)?.stringValue ?? "",
                                  albumArtist: fields[4].atIndex(row)?.stringValue ?? "",
                                  sortAlbumArtist: fields[5].atIndex(row)?.stringValue ?? "",
                                  isCompilation: (fields[6].atIndex(row)?.int32Value ?? 0) != 0,
                                  discNumber: Int(fields[7].atIndex(row)?.int32Value ?? 0),
                                  trackNumber: Int(fields[8].atIndex(row)?.int32Value ?? 0))
            }
        }
    }

    func play(_ id: String, intent: MusicPlayIntent) async throws -> MusicPlayback {
        try await Self.openMusicIfNeeded()
        return try await work {
            let command: Command = switch intent {
            case .transport: .play
            case .selectSong: .selectTrack
            case .selectAlbumTrack: .selectAlbumTrack
            }
            let row = try Self.execute(command, id: id)
            guard let playback = try Self.playback(row), playback.track.id == id,
                  intent == .selectSong || playback.isPlaying else {
                throw MusicIssue.cannotPlay
            }
            return playback
        }
    }

    func snapshot() async throws -> MusicPlayback? {
        guard await Self.isMusicRunning() else { return nil }
        return try await work { try Self.playback(Self.execute(.snapshot)) }
    }

    func togglePlayback() async throws -> MusicPlayback? {
        guard await Self.isMusicRunning() else { return nil }
        return try await work { try Self.playback(Self.execute(.toggle)) }
    }

    func artwork(for id: String) async throws -> Data? {
        guard await Self.isMusicRunning() else { return nil }
        return try await work {
            let reply = try Self.execute(.artwork, id: id)
            guard reply.numberOfItems == 1, let bytes = reply.atIndex(1)?.data,
                  !bytes.isEmpty, bytes.count <= 8 * 1024 * 1024 else { return nil }
            return bytes
        }
    }

    @MainActor
    private static func isMusicRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
    }

    @MainActor
    private static func openMusicIfNeeded() async throws {
        guard !isMusicRunning() else { return }
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            throw MusicIssue.unavailable
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        do { _ = try await workspace.openApplication(at: url, configuration: configuration) }
        catch { throw MusicIssue.unavailable }
    }

    private func work<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result(catching: operation)) }
        }
    }

    private static func playback(_ row: NSAppleEventDescriptor) throws -> MusicPlayback? {
        guard row.numberOfItems != 0 else { return nil }
        guard row.numberOfItems == 9, let id = row.atIndex(1)?.stringValue, !id.isEmpty,
              let playing = row.atIndex(4)?.int32Value,
              let elapsed = row.atIndex(5)?.doubleValue, let length = row.atIndex(6)?.doubleValue,
              elapsed.isFinite, length.isFinite else {
            throw MusicIssue.invalidResponse
        }
        let track = MusicTrack(id: id, title: row.atIndex(2)?.stringValue ?? "",
                               artist: row.atIndex(3)?.stringValue ?? "", album: row.atIndex(7)?.stringValue ?? "")
        return MusicPlayback(track: track, isPlaying: playing == 1, elapsed: max(0, elapsed), duration: max(0, length),
                             shuffleEnabled: row.atIndex(8)?.int32Value == 1,
                             repeatMode: .init(rawValue: Int(row.atIndex(9)?.int32Value ?? 0)) ?? .off)
    }

    // Keep OSA objects on the worker. A private language instance keeps the
    // execution independent of any shared scripting instance.
    private static func execute(_ command: Command, id: String = "") throws -> NSAppleEventDescriptor {
        guard let language = OSALanguage(forName: "AppleScript"), language.isThreadSafe else {
            throw MusicIssue.scriptSetup(code: nil)
        }
        let script = OSAScript(source: command.source, language: language)
        script.languageInstance = OSALanguageInstance(language: language)
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else {
            throw issue(for: error, command: command, compiling: true)
        }
        error = nil
        // IDs are handler arguments and never form part of the script source.
        guard let result = script.executeHandler(withName: "performrequest", arguments: [id], error: &error) else {
            throw issue(for: error, command: command, compiling: false)
        }
        return result
    }

    private static func issue(for error: NSDictionary?, command: Command, compiling: Bool) -> MusicIssue {
        let code = (error?[OSAScriptErrorNumber] as? NSNumber)?.intValue
        switch code {
        case -1743, -1744, -10004, -128: return .denied
        case -600, -609, -10814: return .unavailable
        case -1712: return .timedOut
        default:
            if compiling { return .scriptSetup(code: code) }
            if command == .play || command == .selectTrack || command == .selectAlbumTrack, code == -2701 || code == -1728 { return .cannotPlay }
            return .eventFailed(code: code)
        }
    }

    private enum Command {
        case tracks, play, selectTrack, selectAlbumTrack, snapshot, toggle, artwork

        var source: String {
            let readPlayback = """
                if player state is stopped then return {}
                set itemTrack to current track
                set playingFlag to 0
                if player state is playing then set playingFlag to 1
                set albumName to ""
                try
                    set albumValue to album of itemTrack
                    if albumValue is not missing value then set albumName to albumValue
                end try
                set shuffleFlag to 0
                set repeatFlag to 0
                try
                    if shuffle enabled then set shuffleFlag to 1
                    set repeatSetting to song repeat
                    if repeatSetting is one then set repeatFlag to 1
                    if repeatSetting is all then set repeatFlag to 2
                end try
                return {persistent ID of itemTrack, name of itemTrack, artist of itemTrack, ¬
                    playingFlag, player position, duration of itemTrack, albumName, shuffleFlag, repeatFlag}
                """
            let code: String
            switch self {
            case .tracks:
                code = """
                    if (count tracks of library playlist 1) is 0 then return {{}, {}, {}, {}, {}, {}, {}, {}, {}}
                    return {persistent ID, name, artist, album, album artist, sort album artist, ¬
                        compilation, disc number, track number} of every track of library playlist 1
                    """
            case .play, .selectTrack, .selectAlbumTrack:
                let startTrack = """
                    set itemTrack to first track of library playlist 1 whose persistent ID is targetID
                    play itemTrack
                    repeat 8 times
                        if player state is playing then
                            if persistent ID of current track is targetID then exit repeat
                        end if
                        delay 0.12
                    end repeat
                    if player state is not playing then return {}
                    """
                if self != .play {
                    let resume = self == .selectAlbumTrack ? "else if player state is paused then\nplay" : ""
                    code = """
                        set shouldStart to true
                        if player state is not stopped then
                            if exists current track then set shouldStart to ((persistent ID of current track) is not targetID)
                        end if
                        if shouldStart then
                            \(startTrack)
                        \(resume)
                        end if
                        \(readPlayback)
                        """
                } else {
                    code = startTrack + "\n" + readPlayback
                }
            case .snapshot:
                code = readPlayback
            case .toggle:
                code = "if player state is stopped then return {}\nplaypause\n" + readPlayback
            case .artwork:
                code = """
                    set artTrack to missing value
                    if player state is not stopped then
                        try
                            if persistent ID of current track is targetID then set artTrack to current track
                        end try
                    end if
                    if artTrack is missing value then set artTrack to first track of library playlist 1 whose persistent ID is targetID
                    if (count of artworks of artTrack) is 0 then return {}
                    return {raw data of artwork 1 of artTrack}
                    """
            }
            return """
                on performrequest(targetID)
                    with timeout of 12 seconds
                        tell application id "com.apple.Music"
                            \(code)
                        end tell
                    end timeout
                end performrequest
                """
        }
    }
}
