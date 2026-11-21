import AppKit
import OSAKit

struct MusicAppBridge: MusicService {
    private static let bundleID = "com.apple.Music"
    private let queue = DispatchQueue(label: "jp.nanodesk.music-automation", qos: .userInitiated)

    func tracks() async throws -> [MusicTrack] {
        try await Self.openMusicIfNeeded()
        return try await work {
            let columns = try Self.execute(.tracks)
            guard columns.numberOfItems == 3, let ids = columns.atIndex(1),
                  let names = columns.atIndex(2), let artists = columns.atIndex(3),
                  names.numberOfItems == ids.numberOfItems, artists.numberOfItems == ids.numberOfItems else {
                throw MusicIssue.invalidResponse
            }
            return (0..<ids.numberOfItems).compactMap { offset in
                let index = offset + 1
                guard let id = ids.atIndex(index)?.stringValue, !id.isEmpty else { return nil }
                return MusicTrack(id: id, title: names.atIndex(index)?.stringValue ?? "",
                                  artist: artists.atIndex(index)?.stringValue ?? "")
            }
        }
    }

    func play(_ id: String) async throws -> MusicPlayback {
        try await Self.openMusicIfNeeded()
        return try await work {
            let row = try Self.execute(.play, id: id)
            guard let playback = try Self.playback(row), playback.track.id == id, playback.isPlaying else {
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
        guard await Self.isMusicRunning() else { throw MusicIssue.unavailable }
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
        guard row.numberOfItems == 6, let id = row.atIndex(1)?.stringValue, !id.isEmpty,
              let playing = row.atIndex(4)?.int32Value,
              let elapsed = row.atIndex(5)?.doubleValue, let length = row.atIndex(6)?.doubleValue,
              elapsed.isFinite, length.isFinite else {
            throw MusicIssue.invalidResponse
        }
        return MusicPlayback(track: MusicTrack(id: id, title: row.atIndex(2)?.stringValue ?? "",
                                               artist: row.atIndex(3)?.stringValue ?? ""),
                             isPlaying: playing == 1, elapsed: max(0, elapsed), duration: max(0, length))
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
            if command == .play, code == -2701 || code == -1728 { return .cannotPlay }
            return .eventFailed(code: code)
        }
    }

    private enum Command {
        case tracks, play, snapshot, toggle, artwork

        var source: String {
            let readPlayback = """
                if player state is stopped then return {}
                set itemTrack to current track
                set playingFlag to 0
                if player state is playing then set playingFlag to 1
                return {persistent ID of itemTrack, name of itemTrack, artist of itemTrack, ¬
                    playingFlag, player position, duration of itemTrack}
                """
            let code: String
            switch self {
            case .tracks:
                code = """
                    if (count tracks of library playlist 1) is 0 then return {{}, {}, {}}
                    return {persistent ID, name, artist} of every track of library playlist 1
                    """
            case .play:
                code = """
                    set itemTrack to first track of library playlist 1 whose persistent ID is targetID
                    play itemTrack
                    repeat 8 times
                        if player state is playing then
                            set playingTrack to current track
                            if persistent ID of playingTrack is targetID then
                                return {persistent ID of playingTrack, name of playingTrack, artist of playingTrack, ¬
                                    1, player position, duration of playingTrack}
                            end if
                        end if
                        delay 0.12
                    end repeat
                    error "Music did not start the selected track" number -2701
                    """
            case .snapshot:
                code = readPlayback
            case .toggle:
                code = "playpause\n" + readPlayback
            case .artwork:
                code = """
                    if player state is stopped then return {}
                    set playingTrack to current track
                    if persistent ID of playingTrack is not targetID then return {}
                    if (count of artworks of playingTrack) is 0 then return {}
                    return {raw data of artwork 1 of playingTrack}
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
