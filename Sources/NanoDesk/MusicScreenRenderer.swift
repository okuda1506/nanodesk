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
    private static let playback = Palette(background: rgb(18, 18, 20), text: .white,
                                          muted: rgb(206, 206, 210), accent: rgb(52, 137, 232))

    private let width = 240
    private let height = 376
    private let selectionBlue = MusicScreenRenderer.rgb(51, 109, 200)
    private let selectionStripe = MusicScreenRenderer.rgb(73, 151, 212)
    private let menuSleeves = Bundle.main.url(forResource: "MenuSleeves", withExtension: "jpg")
        .flatMap { NSImage(contentsOf: $0) }
    private var artworkBytes: Data?
    private var artworkImage: NSImage?
    private var scrollingTrackID: String?
    private var scrollStart: TimeInterval = 0
    var titleIsScrolling: Bool { scrollingTrackID != nil }

    func image(for session: MusicSession) -> CGImage? {
        if session.page != .playing || session.playback == nil { scrollingTrackID = nil }
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
            if let notice = session.notice, !session.loadingSongs {
                message(notice, color: palette.muted, y: session.tracks.isEmpty ? 107 : 307, height: 63, size: 12)
            }
        case .playing:
            nowPlaying(session)
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
                        kCGImageSourceThumbnailMaxPixelSize: width
                      ] as CFDictionary) else { return nil }
                return NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width), height: CGFloat(image.height)))
            }
        }
        return artworkImage
    }

    private func nowPlaying(_ session: MusicSession) {
        let palette = Self.playback
        playbackStatus(session.playback)
        guard let playback = session.playback else {
            message(session.notice ?? "再生中の曲はありません。", color: palette.muted)
            return
        }
        gradient(CGRect(x: 0, y: 20, width: 240, height: 61),
                 top: Self.rgb(72, 72, 74), bottom: .black)
        text(playback.track.artist, at: CGRect(x: 5, y: 24, width: 230, height: 17),
             size: 12, weight: .semibold, color: palette.muted, align: .center)
        playbackTitle(playback, animate: session.notice == nil)
        text(playback.track.album, at: CGRect(x: 5, y: 59, width: 230, height: 19),
             size: 12, weight: .semibold, color: palette.muted, align: .center)

        playbackCover(session.artwork)
        if let notice = session.notice {
            fill(palette.background, 0, 296, 240, 80)
            message(notice, color: palette.muted, y: 301, height: 72, size: 12)
            return
        }
        let timeline = playback.timeline
        let timeFont = NSFont.boldSystemFont(ofSize: 12)
        let labels = [timeline.elapsed, timeline.remaining]
        let labelWidth = labels.map { ($0 as NSString).size(withAttributes: [.font: timeFont]).width }.max() ?? 0
        let inset = max(46, ceil(labelWidth) + 9)
        let bar = CGRect(x: inset, y: 341, width: 240 - inset * 2, height: 9)
        gradient(bar, top: Self.rgb(201, 205, 211), bottom: Self.rgb(246, 246, 247))
        if timeline.fraction > 0 {
            let played = CGRect(x: bar.minX, y: bar.minY, width: bar.width * timeline.fraction, height: bar.height)
            gradient(played, top: Self.rgb(143, 199, 253), bottom: palette.accent)
        }
        text(timeline.elapsed, at: CGRect(x: 2, y: 337, width: inset - 7, height: 17),
             size: 12, weight: .bold, color: .white, align: .right)
        text(timeline.remaining, at: CGRect(x: bar.maxX + 5, y: 337, width: inset - 7, height: 17),
             size: 12, weight: .bold, color: .white)
        if let number = session.playingTrackNumber {
            text("\(number) / \(session.tracks.count)", at: CGRect(x: 4, y: 354, width: 232, height: 18),
                 size: 12, weight: .medium, color: palette.text, align: .center)
        }
    }

    private func playbackCover(_ artwork: Data?) {
        let cover = CGRect(x: 0, y: 81, width: 240, height: 240)
        let footer = CGRect(x: 0, y: cover.maxY, width: 240, height: 55)
        gradient(footer, top: Self.rgb(64, 64, 68), bottom: Self.playback.background)
        guard let image = decodedArtwork(artwork) else {
            missingCover(in: cover)
            return
        }
        let scale = min(cover.width / image.size.width, cover.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let dest = CGRect(x: cover.midX - size.width / 2, y: cover.midY - size.height / 2,
                          width: size.width, height: size.height)
        image.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.clip(to: footer)
        context.translateBy(x: 0, y: cover.maxY * 2)
        context.scaleBy(x: 1, y: -1)
        image.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 0.27, respectFlipped: true, hints: nil)
        context.restoreGState()
        gradient(footer, top: .clear, bottom: NSColor.black.withAlphaComponent(0.55))
    }

    private func playbackTitle(_ playback: MusicPlayback, animate: Bool) {
        let rect = CGRect(x: 4, y: 40, width: 232, height: 21)
        let title = playback.track.title.isEmpty ? "タイトルなし" : playback.track.title
        let label = title as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 16), .foregroundColor: NSColor.white]
        let size = label.size(withAttributes: attributes)
        guard animate, playback.isPlaying, size.width > rect.width,
              let context = NSGraphicsContext.current?.cgContext else {
            scrollingTrackID = nil
            text(title, at: rect, size: 16, weight: .bold, color: .white, align: .center)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if scrollingTrackID != playback.track.id {
            scrollingTrackID = playback.track.id
            scrollStart = now
        }
        let distance = size.width + 24
        let speed: CGFloat = 22
        let phase = (now - scrollStart).truncatingRemainder(dividingBy: 1.5 + distance / speed)
        let x = rect.minX - max(0, phase - 1.5) * speed
        let y = (rect.midY - size.height / 2).rounded()
        context.saveGState()
        context.clip(to: rect)
        label.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
        label.draw(at: CGPoint(x: x + distance, y: y), withAttributes: attributes)
        context.restoreGState()
    }

    private func playbackStatus(_ playback: MusicPlayback?) {
        gradient(CGRect(x: 0, y: 0, width: 240, height: 20), top: Self.rgb(86, 86, 89), bottom: Self.rgb(61, 61, 64))
        let clock = Date.now.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
        text(clock, at: CGRect(x: 55, y: 2, width: 130, height: 16),
             size: 12, weight: .semibold, color: Self.playback.muted, align: .center)
        if let playback {
            if playback.shuffleEnabled { statusSymbol("shuffle", x: 4, width: 19) }
            if playback.repeatMode != .off {
                statusSymbol(playback.repeatMode == .one ? "repeat.1" : "repeat", x: playback.shuffleEnabled ? 28 : 4, width: 18)
            }
            statusSymbol(playback.isPlaying ? "play.fill" : "pause.fill", x: 191, width: 14)
        }
        statusSymbol("battery.100", x: 210, width: 26)
    }

    private func statusSymbol(_ name: String, x: CGFloat, width: CGFloat) {
        let config = NSImage.SymbolConfiguration(paletteColors: [Self.playback.muted])
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let scale = min(width / symbol.size.width, 14 / symbol.size.height)
        let w = symbol.size.width * scale, h = symbol.size.height * scale
        symbol.draw(in: CGRect(x: x + (width - w) / 2, y: 10 - h / 2, width: w, height: h),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func missingCover(in rect: CGRect) {
        gradient(rect, top: Self.rgb(59, 68, 78), bottom: Self.rgb(24, 29, 36))
        // Shape in the square's local coordinates, with two joined notes and tilted heads.
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        let note = NSBezierPath()
        note.move(to: CGPoint(x: 96, y: 58))
        note.line(to: CGPoint(x: 187, y: 43))
        note.line(to: CGPoint(x: 187, y: 161))
        note.curve(to: CGPoint(x: 158, y: 177), controlPoint1: CGPoint(x: 187, y: 175), controlPoint2: CGPoint(x: 169, y: 182))
        note.curve(to: CGPoint(x: 176, y: 145), controlPoint1: CGPoint(x: 129, y: 170), controlPoint2: CGPoint(x: 147, y: 142))
        note.line(to: CGPoint(x: 176, y: 84))
        note.line(to: CGPoint(x: 107, y: 96))
        note.line(to: CGPoint(x: 107, y: 175))
        note.curve(to: CGPoint(x: 77, y: 194), controlPoint1: CGPoint(x: 107, y: 190), controlPoint2: CGPoint(x: 91, y: 198))
        note.curve(to: CGPoint(x: 96, y: 159), controlPoint1: CGPoint(x: 47, y: 187), controlPoint2: CGPoint(x: 65, y: 153))
        note.close()
        note.addClip()
        gradient(note.bounds, top: Self.rgb(206, 215, 223), bottom: Self.rgb(154, 172, 192))
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
}
