import Foundation

struct MusicAppBridge: MusicService {
    private let queue = DispatchQueue(label: "jp.nanodesk.music-automation", qos: .userInitiated)

    func tracks() async throws -> [MusicTrack] {
        try await work {
            let columns = try Self.execute("tracks")
            guard columns.count == 3, let ids = columns[0] as? [String],
                  let titles = columns[1] as? [Any], let artists = columns[2] as? [Any],
                  titles.count == ids.count, artists.count == ids.count else { throw MusicIssue.failed }
            return ids.indices.map { MusicTrack(id: ids[$0], title: titles[$0] as? String ?? "",
                                               artist: artists[$0] as? String ?? "") }
        }
    }

    func play(_ id: String) async throws -> MusicPlayback {
        try await work {
            let row = try Self.execute("play", id: id)
            guard let result = try Self.playback(row), result.track.id == id, result.isPlaying else {
                throw MusicIssue.cannotPlay
            }
            return result
        }
    }

    func snapshot() async throws -> MusicPlayback? {
        try await work { try Self.playback(Self.execute("snapshot")) }
    }

    func togglePlayback() async throws -> MusicPlayback? {
        try await work { try Self.playback(Self.execute("toggle")) }
    }

    func artwork(for id: String) async throws -> Data? {
        try await work {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent("cover")
            _ = try Self.execute("cover", id: id, artworkPath: file.path)
            guard let info = try? file.resourceValues(forKeys: [.fileSizeKey]),
                  let size = info.fileSize, size > 0, size <= 8 * 1024 * 1024 else { return nil }
            return try Data(contentsOf: file)
        }
    }

    private func work<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result(catching: operation)) }
        }
    }

    private static func playback(_ row: [Any]) throws -> MusicPlayback? {
        guard !row.isEmpty else { return nil }
        guard row.count == 6, let id = row[0] as? String, !id.isEmpty,
              let playing = row[3] as? Bool, let elapsed = row[4] as? Double,
              let length = row[5] as? Double, elapsed.isFinite, length.isFinite else {
            throw MusicIssue.failed
        }
        return MusicPlayback(track: MusicTrack(id: id, title: row[1] as? String ?? "",
                                               artist: row[2] as? String ?? ""),
                             isPlaying: playing, elapsed: max(0, elapsed), duration: max(0, length))
    }

    private static func execute(_ operation: String, id: String = "", artworkPath: String = "") throws -> [Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-", operation, id, artworkPath]
        let source = Pipe()
        let response = Pipe()
        process.standardInput = source
        process.standardOutput = response
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Constant script, separate argv, no shell or string interpolation of library data.
        do {
            defer { try? source.fileHandleForWriting.close() }
            try source.fileHandleForWriting.write(contentsOf: Data(script.utf8))
        }
        let bytes = response.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let envelope = try JSONSerialization.jsonObject(with: bytes) as? [Any],
              envelope.count == 2, let code = envelope[0] as? Int else { throw MusicIssue.failed }
        if code != 0 {
            switch code {
            case -1743, -1744, -10004, -128: throw MusicIssue.denied
            case -600, -609, -10814: throw MusicIssue.unavailable
            default: throw operation == "play" ? MusicIssue.cannotPlay : MusicIssue.failed
            }
        }
        guard let result = envelope[1] as? [Any] else { throw MusicIssue.failed }
        return result
    }

    private static let script = """
    use framework "Foundation"
    use scripting additions

    on run argv
        try
            set operation to item 1 of argv
            set targetID to item 2 of argv
            set coverPath to item 3 of argv
            with timeout of 12 seconds
                set payload to my performOperation(operation, targetID, coverPath)
            end timeout
            return my encodeJSON({0, payload})
        on error number code
            return my encodeJSON({code, {}})
        end try
    end run

    on performOperation(operation, targetID, coverPath)
        if operation is not "tracks" and operation is not "play" then
            if application id "com.apple.Music" is not running then return {}
        end if

        tell application id "com.apple.Music"
            if operation is "tracks" then
                return {persistent ID, name, artist} of every track of library playlist 1
            else if operation is "play" then
                set matched to (first track of library playlist 1 whose persistent ID is targetID)
                play matched
                repeat 8 times
                    set row to my currentPlayback()
                    if (count row) > 3 then
                        if item 1 of row is targetID and item 4 of row is true then return row
                    end if
                    delay 0.12
                end repeat
                error number -2701
            else if operation is "toggle" then
                playpause
                return my currentPlayback()
            else if operation is "cover" then
                set playingTrack to current track
                if persistent ID of playingTrack is targetID and (count artworks of playingTrack) > 0 then
                    set coverData to raw data of artwork 1 of playingTrack
                else
                    return {}
                end if
            else
                return my currentPlayback()
            end if
        end tell

        -- Staging contains artwork only and is deleted by the caller.
        set outputFile to open for access (POSIX file coverPath) with write permission
        try
            write coverData to outputFile
            close access outputFile
        on error number code
            try
                close access outputFile
            end try
            error number code
        end try
        return {}
    end performOperation

    on currentPlayback()
        tell application id "com.apple.Music"
            if player state is stopped then return {}
            set itemTrack to current track
            return {persistent ID of itemTrack, name of itemTrack, artist of itemTrack, ¬
                (player state is playing), player position, duration of itemTrack}
        end tell
    end currentPlayback

    on encodeJSON(value)
        set jsonData to current application's NSJSONSerialization's dataWithJSONObject:value options:0 |error|:(missing value)
        return (current application's NSString's alloc()'s initWithData:jsonData encoding:4) as text
    end encodeJSON
    """
}
