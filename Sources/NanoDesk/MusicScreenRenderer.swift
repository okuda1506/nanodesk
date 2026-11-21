import AppKit
import ImageIO

@MainActor
final class MusicScreenRenderer {
    private let width = 240
    private let height = 376
    private let ink = NSColor(srgbRed: 0.045, green: 0.077, blue: 0.135, alpha: 1)
    private let white = NSColor(srgbRed: 0.91, green: 0.95, blue: 0.99, alpha: 1)
    private let muted = NSColor(srgbRed: 0.59, green: 0.70, blue: 0.82, alpha: 1)
    private let blue = NSColor(srgbRed: 0.13, green: 0.32, blue: 0.67, alpha: 1)
    private let cyan = NSColor(srgbRed: 0.34, green: 0.82, blue: 0.99, alpha: 1)
    private var artworkBytes: Data?
    private var artworkImage: NSImage?

    func image(for session: MusicSession) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.current = previous }

        fill(ink, 0, 0, 240, 376)
        fill(cyan, 0, 0, 240, 2)
        text("NANODESK", at: CGRect(x: 15, y: 13, width: 110, height: 19), size: 12,
             weight: .semibold, color: cyan)
        let clock = Date.now.formatted(.dateTime.hour().minute())
        text(clock, at: CGRect(x: 132, y: 13, width: 92, height: 19), size: 12,
             color: muted, align: .right)
        fill(muted.withAlphaComponent(0.27), 16, 37, 208, 1)

        switch session.page {
        case .home:
            heading("メニュー")
            menu(["ミュージック", "再生中"], selection: session.selection)
        case .music:
            heading("ミュージック")
            menu(["曲", "再生中"], selection: session.selection)
        case .songs:
            heading("曲")
            songs(session)
        case .playing:
            heading("再生中")
            if let playback = session.playback { nowPlaying(playback, artwork: session.artwork) }
            else if session.notice == nil { message("再生中の曲はありません。") }
        }

        if let notice = session.notice, !session.loadingSongs {
            let showFooter = session.page == .playing && session.playback != nil
            if showFooter {
                fill(ink, 0, 304, 240, 72)
                message(notice, y: 309, height: 51, size: 12)
            } else {
                message(notice, y: session.page == .songs && session.tracks.isEmpty ? 107 : 307,
                        height: 63, size: 12)
            }
        }
        return context.makeImage()
    }

    private func menu(_ labels: [String], selection: Int) {
        for (index, label) in labels.enumerated() {
            let y = CGFloat(96 + index * 46)
            rowBackground(y: y, height: 43, selected: index == selection)
            text(label, at: CGRect(x: 24, y: y + 10, width: 164, height: 25), size: 18, weight: .medium)
            text("›", at: CGRect(x: 198, y: y + 7, width: 19, height: 29), size: 21,
                 color: index == selection ? white : muted, align: .right)
        }
    }

    private func songs(_ session: MusicSession) {
        if session.loadingSongs { message("曲を読み込み中…"); return }
        guard !session.tracks.isEmpty else { return }
        let count = min(6, session.tracks.count)
        let first = min(max(0, session.selection - count + 1), session.tracks.count - count)
        for index in first..<(first + count) {
            let track = session.tracks[index]
            let y = CGFloat(87 + (index - first) * 36)
            rowBackground(y: y, height: 34, selected: index == session.selection)
            text(track.title.isEmpty ? "タイトルなし" : track.title,
                 at: CGRect(x: 23, y: y + 1, width: 190, height: 19), size: 14, weight: .semibold)
            text(track.artist, at: CGRect(x: 23, y: y + 19, width: 190, height: 14),
                 size: 11, color: index == session.selection ? white : muted)
        }
        if session.notice == nil {
            text("\(session.selection + 1) / \(session.tracks.count)",
                 at: CGRect(x: 16, y: 344, width: 208, height: 18), size: 12, color: muted, align: .right)
        }
    }

    private func nowPlaying(_ playback: MusicPlayback, artwork: Data?) {
        let coverRect = CGRect(x: 47, y: 86, width: 146, height: 146)
        fill(blue.withAlphaComponent(0.23), coverRect.minX, coverRect.minY, coverRect.width, coverRect.height)
        if artworkBytes != artwork {
            artworkBytes = artwork
            artworkImage = artwork.flatMap { data in
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 180
                      ] as CFDictionary) else { return nil }
                return NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width), height: CGFloat(image.height)))
            }
        }
        if let image = artworkImage {
            let scale = min(coverRect.width / image.size.width, coverRect.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: coverRect.midX - size.width / 2, y: coverRect.midY - size.height / 2,
                                  width: size.width, height: size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            fill(cyan.withAlphaComponent(0.8), 47, 86, 146, 2)
            text("♪", at: CGRect(x: 47, y: 111, width: 146, height: 96),
                 size: 67, color: cyan, align: .center)
        }
        text(playback.track.title.isEmpty ? "タイトルなし" : playback.track.title,
             at: CGRect(x: 17, y: 245, width: 206, height: 26), size: 17, weight: .semibold)
        text(playback.track.artist, at: CGRect(x: 17, y: 272, width: 206, height: 22), size: 14, color: muted)
        let fraction = playback.duration > 0 ? min(max(playback.elapsed / playback.duration, 0), 1) : 0
        fill(muted.withAlphaComponent(0.38), 17, 309, 206, 5)
        fill(cyan, 17, 309, 206 * fraction, 5)
        text(time(playback.elapsed), at: CGRect(x: 17, y: 324, width: 81, height: 18), size: 12, color: muted)
        text(time(playback.duration), at: CGRect(x: 142, y: 324, width: 81, height: 18),
             size: 12, color: muted, align: .right)
        text(playback.isPlaying ? "▶" : "Ⅱ", at: CGRect(x: 185, y: 51, width: 36, height: 23),
             size: 15, color: cyan, align: .right)
    }

    private func heading(_ title: String) {
        text(title, at: CGRect(x: 16, y: 47, width: 185, height: 31), size: 21, weight: .semibold)
    }

    private func rowBackground(y: CGFloat, height: CGFloat, selected: Bool) {
        if selected {
            fill(blue, 15, y, 210, height)
            fill(cyan, 15, y, 3, height)
        } else {
            fill(muted.withAlphaComponent(0.2), 22, y + height, 196, 1)
        }
    }

    private func message(_ value: String, y: CGFloat = 107, height: CGFloat = 107, size: CGFloat = 14) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        (value as NSString).draw(with: CGRect(x: 17, y: y, width: 206, height: height),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: muted, .paragraphStyle: style])
    }

    private func fill(_ color: NSColor, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
        color.setFill()
        NSBezierPath(rect: CGRect(x: x, y: y, width: width, height: height)).fill()
    }

    private func text(_ value: String, at rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular,
                      color: NSColor? = nil, align: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                         .foregroundColor: color ?? white, .paragraphStyle: style])
    }

    private func time(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let seconds = Int(max(0, min(value, 359_999)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
