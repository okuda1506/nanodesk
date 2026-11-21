import AppKit
import ImageIO

@MainActor
final class MusicScreenRenderer {
    private struct Palette {
        let background: NSColor
        let text: NSColor
        let muted: NSColor
        let accent: NSColor
    }

    private static let browse = Palette(background: .white, text: rgb(22, 26, 32),
                                        muted: rgb(82, 96, 113), accent: rgb(38, 91, 165))
    private static let playback = Palette(background: rgb(30, 30, 32), text: rgb(245, 245, 247),
                                          muted: rgb(192, 194, 200), accent: rgb(153, 190, 240))

    private let width = 240
    private let height = 376
    private let selectionBlue = MusicScreenRenderer.rgb(51, 109, 200)
    private let selectionStripe = MusicScreenRenderer.rgb(73, 151, 212)
    private var artworkBytes: Data?
    private var artworkImage: NSImage?

    func image(for session: MusicSession) -> CGImage? {
        let palette = session.page == .playing ? Self.playback : Self.browse
        let rgba = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: rgba) else { return nil }
        context.setFillColor(palette.background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.current = previous }

        fill(palette.accent, 0, 0, 240, 2)
        text("NANODESK", at: CGRect(x: 15, y: 13, width: 110, height: 19), size: 12,
             weight: .semibold, color: palette.accent)
        let clock = Date.now.formatted(.dateTime.hour().minute())
        text(clock, at: CGRect(x: 132, y: 13, width: 92, height: 19), size: 12,
             color: palette.muted, align: .right)
        fill(palette.muted.withAlphaComponent(0.27), 16, 37, 208, 1)

        switch session.page {
        case .home:
            heading("メニュー", color: palette.text)
            menu(["ミュージック", "再生中"], selection: session.selection)
        case .music:
            heading("ミュージック", color: palette.text)
            menu(["曲", "再生中"], selection: session.selection)
        case .songs:
            heading("曲", color: palette.text)
            songs(session)
        case .playing:
            heading("再生中", color: palette.text)
            if let playback = session.playback { nowPlaying(playback, artwork: session.artwork) }
            else if session.notice == nil { message("再生中の曲はありません。", color: palette.muted) }
        }

        if let notice = session.notice, !session.loadingSongs {
            let showFooter = session.page == .playing && session.playback != nil
            if showFooter {
                fill(palette.background, 0, 304, 240, 72)
                message(notice, color: palette.muted, y: 309, height: 51, size: 12)
            } else {
                message(notice, color: palette.muted,
                        y: session.page == .songs && session.tracks.isEmpty ? 107 : 307,
                        height: 63, size: 12)
            }
        }
        return context.makeImage()
    }

    private func menu(_ labels: [String], selection: Int) {
        for (index, label) in labels.enumerated() {
            let y = CGFloat(96 + index * 46)
            let selected = index == selection
            rowBackground(y: y, height: 43, selected: selected)
            text(label, at: CGRect(x: 24, y: y + 10, width: 164, height: 25), size: 18, weight: .medium,
                 color: selected ? .white : Self.browse.text)
            text("›", at: CGRect(x: 198, y: y + 7, width: 19, height: 29), size: 21,
                 color: selected ? .white : Self.browse.muted, align: .right)
        }
    }

    private func songs(_ session: MusicSession) {
        if session.loadingSongs {
            message("曲を読み込み中…", color: Self.browse.muted)
            return
        }
        guard !session.tracks.isEmpty else { return }
        let count = min(6, session.tracks.count)
        let first = min(max(0, session.selection - count + 1), session.tracks.count - count)
        for index in first..<(first + count) {
            let track = session.tracks[index]
            let y = CGFloat(87 + (index - first) * 36)
            let selected = index == session.selection
            rowBackground(y: y, height: 34, selected: selected)
            text(track.title.isEmpty ? "タイトルなし" : track.title,
                 at: CGRect(x: 23, y: y + 1, width: 190, height: 19), size: 14, weight: .semibold,
                 color: selected ? .white : Self.browse.text)
            text(track.artist, at: CGRect(x: 23, y: y + 19, width: 190, height: 14),
                 size: 11, color: selected ? .white : Self.browse.muted)
        }
        if session.notice == nil {
            text("\(session.selection + 1) / \(session.tracks.count)",
                 at: CGRect(x: 16, y: 344, width: 208, height: 18), size: 12,
                 color: Self.browse.muted, align: .right)
        }
    }

    private func nowPlaying(_ playback: MusicPlayback, artwork: Data?) {
        let palette = Self.playback
        let coverRect = CGRect(x: 47, y: 86, width: 146, height: 146)
        fill(palette.muted.withAlphaComponent(0.13), coverRect.minX, coverRect.minY, coverRect.width, coverRect.height)
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
            fill(palette.accent.withAlphaComponent(0.8), 47, 86, 146, 2)
            text("♪", at: CGRect(x: 47, y: 111, width: 146, height: 96),
                 size: 67, color: palette.accent, align: .center)
        }
        text(playback.track.title.isEmpty ? "タイトルなし" : playback.track.title,
             at: CGRect(x: 17, y: 245, width: 206, height: 26), size: 17, weight: .semibold, color: palette.text)
        text(playback.track.artist, at: CGRect(x: 17, y: 272, width: 206, height: 22), size: 14, color: palette.muted)
        let fraction = playback.duration > 0 ? min(max(playback.elapsed / playback.duration, 0), 1) : 0
        fill(palette.muted.withAlphaComponent(0.38), 17, 309, 206, 5)
        fill(palette.accent, 17, 309, 206 * fraction, 5)
        text(time(playback.elapsed), at: CGRect(x: 17, y: 324, width: 81, height: 18), size: 12, color: palette.muted)
        text(time(playback.duration), at: CGRect(x: 142, y: 324, width: 81, height: 18),
             size: 12, color: palette.muted, align: .right)
        text(playback.isPlaying ? "▶" : "Ⅱ", at: CGRect(x: 185, y: 51, width: 36, height: 23),
             size: 15, color: palette.accent, align: .right)
    }

    private func heading(_ title: String, color: NSColor) {
        text(title, at: CGRect(x: 16, y: 47, width: 185, height: 31), size: 21, weight: .semibold, color: color)
    }

    private func rowBackground(y: CGFloat, height: CGFloat, selected: Bool) {
        if selected {
            fill(selectionBlue, 15, y, 210, height)
            fill(selectionStripe, 15, y, 3, height)
        } else {
            fill(Self.browse.muted.withAlphaComponent(0.2), 22, y + height, 196, 1)
        }
    }

    private func message(_ value: String, color: NSColor, y: CGFloat = 107, height: CGFloat = 107, size: CGFloat = 14) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        (value as NSString).draw(with: CGRect(x: 17, y: y, width: 206, height: height),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color, .paragraphStyle: style])
    }

    private func fill(_ color: NSColor, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
        color.setFill()
        NSBezierPath(rect: CGRect(x: x, y: y, width: width, height: height)).fill()
    }

    private func text(_ value: String, at rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular,
                      color: NSColor, align: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                         .foregroundColor: color, .paragraphStyle: style])
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }

    private func time(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let seconds = Int(max(0, min(value, 359_999)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
