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
    private let menuSleeves = Bundle.main.url(forResource: "MenuSleeves", withExtension: "jpg")
        .flatMap { NSImage(contentsOf: $0) }
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

        switch session.page {
        case .home, .music:
            menu(session)
            return context.makeImage()
        case .songs:
            detailHeader("曲", palette: palette)
            songs(session)
        case .playing:
            detailHeader("再生中", palette: palette)
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

    private func menu(_ session: MusicSession) {
        let isHome = session.page == .home
        let screenWidth = CGFloat(width)
        let statusHeight: CGFloat = 20
        let sleeveSize = screenWidth / 3
        let sleeveTop = CGFloat(height) - sleeveSize
        let rowHeight = isHome ? (sleeveTop - statusHeight) / 9 : 29.3
        let capacity = isHome ? 9 : Int((CGFloat(height) - statusHeight) / rowHeight)
        let items = session.menuItems
        let selection = session.selection
        let first = max(0, selection - capacity + 1)

        gradient(CGRect(x: 0, y: 0, width: screenWidth, height: statusHeight - 1),
                 top: Self.rgb(251, 251, 251), bottom: Self.rgb(173, 173, 173))
        fill(Self.rgb(121, 122, 122), 0, statusHeight - 1, screenWidth, 1)
        let header = CGRect(x: 8, y: 0, width: 190, height: statusHeight - 1)
        menuLabel(isHome ? "iPod" : "ミュージック", in: header,
                  font: .boldSystemFont(ofSize: 13), color: .black)
        if session.playback?.isPlaying == true {
            menuLabel("▶", in: CGRect(x: 189, y: 0, width: 14, height: statusHeight - 1),
                      font: .systemFont(ofSize: 10), color: Self.rgb(55, 78, 99))
        }
        fill(Self.rgb(74, 77, 70), 210, 4, 20, 10)
        fill(Self.rgb(108, 110, 105), 230, 7, 2, 4)
        gradient(CGRect(x: 211, y: 5, width: 18, height: 8),
                 top: Self.rgb(204, 239, 153), bottom: Self.rgb(94, 162, 43))

        let font = NSFont(name: "HiraginoSans-W6", size: 17.5) ?? .boldSystemFont(ofSize: 17.5)
        for index in first..<min(first + capacity, items.count) {
            let top = statusHeight + (CGFloat(index - first) * rowHeight).rounded()
            let bottom = statusHeight + (CGFloat(index - first + 1) * rowHeight).rounded()
            let row = CGRect(x: 0, y: top, width: screenWidth, height: bottom - top)
            let selected = index == selection
            if selected {
                gradient(row, top: Self.rgb(79, 161, 216), bottom: Self.rgb(47, 101, 196))
                fill(Self.rgb(23, 88, 155), 0, row.maxY - 1, screenWidth, 1)
                let arrow = NSBezierPath()
                arrow.move(to: CGPoint(x: screenWidth - 13, y: row.midY - 5))
                arrow.line(to: CGPoint(x: screenWidth - 8, y: row.midY))
                arrow.line(to: CGPoint(x: screenWidth - 13, y: row.midY + 5))
                arrow.lineWidth = 2.8
                NSColor.white.setStroke()
                arrow.stroke()
            }
            menuLabel(items[index].rawValue, in: row.insetBy(dx: 8, dy: 0),
                      font: font, color: selected ? .white : .black)
        }
        if isHome {
            let strip = CGRect(x: 0, y: sleeveTop, width: screenWidth, height: sleeveSize)
            menuSleeves?.draw(in: strip, from: .zero, operation: .copy, fraction: 1,
                              respectFlipped: true, hints: nil)
            if let cover = decodedArtwork(session.artwork) {
                let side = min(cover.size.width, cover.size.height)
                let square = CGRect(x: (cover.size.width - side) / 2, y: (cover.size.height - side) / 2,
                                    width: side, height: side)
                cover.draw(in: CGRect(x: 0, y: sleeveTop, width: sleeveSize, height: sleeveSize),
                           from: square, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
        if let notice = session.notice {
            let footer = CGRect(x: 0, y: CGFloat(height) - 30, width: screenWidth, height: 30)
            fill(.white, 0, footer.minY, screenWidth, footer.height)
            menuLabel(notice, in: footer.insetBy(dx: 8, dy: 0),
                      font: .systemFont(ofSize: 13), color: Self.browse.muted)
        }
    }

    private func menuLabel(_ title: String, in rect: CGRect, font: NSFont, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let label = title as NSString
        let y = (rect.midY - label.size(withAttributes: attributes).height / 2).rounded()
        label.draw(at: CGPoint(x: rect.minX, y: y), withAttributes: attributes)
    }

    private func gradient(_ rect: CGRect, top: NSColor, bottom: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: [top.cgColor, bottom.cgColor] as CFArray, locations: nil) else { return }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY),
                                   end: CGPoint(x: rect.minX, y: rect.maxY), options: [])
        context.restoreGState()
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

    private func decodedArtwork(_ artwork: Data?) -> NSImage? {
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
        return artworkImage
    }

    private func nowPlaying(_ playback: MusicPlayback, artwork: Data?) {
        let palette = Self.playback
        let coverRect = CGRect(x: 47, y: 86, width: 146, height: 146)
        fill(palette.muted.withAlphaComponent(0.13), coverRect.minX, coverRect.minY, coverRect.width, coverRect.height)
        if let image = decodedArtwork(artwork) {
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

    private func detailHeader(_ title: String, palette: Palette) {
        fill(palette.accent, 0, 0, 240, 2)
        text("NANODESK", at: CGRect(x: 15, y: 13, width: 110, height: 19), size: 12,
             weight: .semibold, color: palette.accent)
        let clock = Date.now.formatted(.dateTime.hour().minute())
        text(clock, at: CGRect(x: 132, y: 13, width: 92, height: 19), size: 12,
             color: palette.muted, align: .right)
        fill(palette.muted.withAlphaComponent(0.27), 16, 37, 208, 1)
        text(title, at: CGRect(x: 16, y: 47, width: 185, height: 31), size: 21, weight: .semibold, color: palette.text)
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
