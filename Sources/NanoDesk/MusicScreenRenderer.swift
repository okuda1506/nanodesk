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
    private var firstSongRow = 0
    private let menuSleeves = Bundle.main.url(forResource: "MenuSleeves", withExtension: "jpg")
        .flatMap { NSImage(contentsOf: $0) }
    private var artworkBytes: Data?
    private var artworkImage: NSImage?
    private var scrollingTrackID: String?
    private var scrollStart: TimeInterval = 0
    private let camera: VideoCamera
    private let flow: CoverFlowRenderer
    var artworkChanged: (() -> Void)? {
        didSet { flow.artworkChanged = artworkChanged }
    }
    var frameInterval: Duration? {
        if flow.animating || camera.isOpening { return .microseconds(16_667) }
        return scrollingTrackID == nil ? nil : .milliseconds(80)
    }

    init(service: any MusicService, camera: VideoCamera) {
        self.camera = camera
        flow = CoverFlowRenderer(service: service)
    }

    func suspendCoverFlow() { flow.leave() }

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

        if let side = session.covers.side {
            scrollingTrackID = nil
            if side == .left {
                context.translateBy(x: CGFloat(width), y: 0)
                context.rotate(by: .pi / 2)
            } else {
                context.translateBy(x: 0, y: CGFloat(height))
                context.rotate(by: -.pi / 2)
            }
            fill(.white, 0, 0, CGFloat(height), CGFloat(width))
            let clock = Date.now.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
            let heading = session.covers.trackIndex == nil ? clock : session.covers.album?.title ?? clock
            browseHeader(heading, playback: session.playback, tint: Self.rgb(26, 133, 198), landscape: true)
            flow.draw(session)
            return context.makeImage()
        }
        flow.leave()
        switch session.page {
        case .home, .music:
            menu(session)
            return context.makeImage()
        case .songs:
            songs(session)
        case .playing:
            nowPlaying(session)
        case .camera:
            viewfinder(in: context)
        }
        return context.makeImage()
    }

    private func viewfinder(in context: CGContext) {
        let lcd = CGRect(x: 0, y: 0, width: width, height: height)
        fill(Self.rgb(30, 32, 34), 0, 0, lcd.width, lcd.height)
        if case .failed(let reason) = camera.finder.phase {
            message(reason, color: .white, y: 132, height: 118, size: 15)
            text("MENUで戻る", at: CGRect(x: 8, y: 338, width: 224, height: 20),
                 size: 13, color: .lightGray, align: .center)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let aperture = camera.aperture(at: now)
        if let image = camera.frame {
            NSImage(cgImage: image, size: lcd.size).draw(in: lcd, from: .zero, operation: .copy,
                fraction: 1, respectFlipped: true, hints: nil)
            let elapsed: Int
            let recording: Bool
            if case .recording(let start) = camera.finder.phase {
                recording = true
                elapsed = Int(max(0, now - start))
            } else {
                recording = false
                elapsed = 0
            }
            let timer = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
            let badge = CGRect(x: 166, y: 6, width: 68, height: 22)
            NSColor.black.withAlphaComponent(0.58).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 3, yRadius: 3).fill()
            if recording && (now.truncatingRemainder(dividingBy: 1) < 0.65) {
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: CGRect(x: 172, y: 13, width: 8, height: 8)).fill()
            }
            text(timer, at: CGRect(x: 181, y: 8, width: 49, height: 19), size: 14,
                 weight: .semibold, color: .white, align: .center)
            let status = camera.finder.phase == .saving ? "保存中…" : (camera.hasAudio ? "" : "音声なし")
            if !status.isEmpty {
                fill(NSColor.black.withAlphaComponent(0.58), 6, 347, 70, 22)
                text(status, at: CGRect(x: 8, y: 349, width: 66, height: 19), size: 13, color: .white, align: .center)
            }
        }
        if aperture < 1 { drawIris(aperture, in: lcd, context: context) }
    }

    private func drawIris(_ opening: Double, in rect: CGRect, context: CGContext) {
        let count = 7
        let step = 2 * Double.pi / Double(count)
        let radius = hypot(rect.midX, rect.midY) / cos(step / 2) + 2
        func point(_ radius: Double, _ angle: Double) -> CGPoint {
            CGPoint(x: rect.midX + radius * cos(angle), y: rect.midY + radius * sin(angle))
        }
        func inner(_ angle: Double) -> CGPoint { point(radius * opening, angle) }
        func bend(_ angle: Double) -> CGPoint { point(radius * (0.64 + opening * 0.55), angle + 0.48) }
        func outer(_ angle: Double) -> CGPoint { point(radius * 1.9, angle + 0.64) }
        for index in 0..<count {
            let a = Double(index) * step - 0.48 + 0.40 * opening
            let b = a + step
            let blade = CGMutablePath()
            blade.move(to: inner(a))
            blade.addLine(to: inner(b))
            blade.addQuadCurve(to: outer(b), control: bend(b))
            blade.addLine(to: outer(a))
            blade.addQuadCurve(to: inner(a), control: bend(a))
            blade.closeSubpath()
            context.saveGState()
            context.addPath(blade)
            context.clip()
            let grad = CGGradient(colorSpace: CGColorSpaceCreateDeviceGray(),
                                  colorComponents: [0.34, 1, 0.13, 1], locations: [0, 1], count: 2)
            if let grad {
                context.drawLinearGradient(grad, start: inner(a), end: point(radius * 0.88, b),
                                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            context.addPath(blade)
            context.setStrokeColor(gray: 0.11, alpha: 0.85)
            context.setLineWidth(1.5)
            context.strokePath()
            context.restoreGState()
        }
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

        browseHeader(isHome ? "iPod" : "ミュージック", playback: session.playback,
                     tint: Self.rgb(55, 78, 99))

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
            let size = (notice as NSString).boundingRect(
                with: CGSize(width: 206, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin],
                attributes: [.font: NSFont.systemFont(ofSize: 13)], context: nil
            ).size
            let footerHeight = max(30, ceil(size.height) + 12)
            let top = CGFloat(height) - footerHeight
            fill(.white, 0, top, screenWidth, footerHeight)
            message(notice, color: Self.browse.muted, y: top + 6, height: footerHeight - 10, size: 13)
        }
    }

    private func browseHeader(_ title: String, playback: MusicPlayback?, tint: NSColor, landscape: Bool = false) {
        let w: CGFloat = landscape ? 376 : 240
        gradient(CGRect(x: 0, y: 0, width: w, height: 19),
                 top: Self.rgb(251, 251, 251), bottom: Self.rgb(173, 173, 173))
        fill(Self.rgb(121, 122, 122), 0, 19, w, 1)
        if landscape {
            text(title, at: CGRect(x: 52, y: 1, width: w - 104, height: 18),
                 size: 13, weight: .bold, color: .black, align: .center)
        } else {
            menuLabel(title, in: CGRect(x: 8, y: 0, width: 178, height: 19),
                  font: .boldSystemFont(ofSize: 13), color: .black)
        }
        if let playback {
            menuLabel(playback.isPlaying ? "▶" : "Ⅱ", in: CGRect(x: w - 51, y: 0, width: 14, height: 19),
                      font: .systemFont(ofSize: 10), color: tint)
        }
        fill(Self.rgb(74, 77, 70), w - 30, 4, 20, 10)
        fill(Self.rgb(108, 110, 105), w - 10, 7, 2, 4)
        gradient(CGRect(x: w - 29, y: 5, width: 18, height: 8),
                 top: Self.rgb(204, 239, 153), bottom: Self.rgb(94, 162, 43))
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
        browseHeader("曲", playback: session.playback, tint: Self.rgb(24, 134, 199))
        if session.loadingSongs {
            message("曲を読み込み中…", color: Self.browse.muted)
            return
        }
        guard !session.tracks.isEmpty else {
            firstSongRow = 0
            if let notice = session.notice { message(notice, color: Self.browse.muted) }
            return
        }
        let capacity = session.notice == nil ? 12 : 9
        let totalRows = session.tracks.count + 1
        let selectedRow = session.selection + 1   // Row zero is the unavailable shuffle command.
        let lastStart = max(0, totalRows - capacity)
        firstSongRow = min(firstSongRow, selectedRow, lastStart)
        firstSongRow = selectedRow == 1 ? 0 : max(firstSongRow, selectedRow - capacity + 1)
        let rowHeight = CGFloat(height - 20) / 12
        let playingRow = session.playback?.isPlaying == true ? session.playingTrackNumber : nil
        for index in firstSongRow..<min(firstSongRow + capacity, totalRows) {
            let offset = CGFloat(index - firstSongRow)
            let top = 20 + (offset * rowHeight).rounded()
            let bottom = 20 + ((offset + 1) * rowHeight).rounded()
            let row = CGRect(x: 0, y: top, width: CGFloat(width), height: bottom - top)
            if index == 0 {
                let label = "シャッフル"
                let font = NSFont.systemFont(ofSize: 17, weight: .medium)
                menuLabel(label, in: row.insetBy(dx: 6, dy: 0), font: font, color: Self.browse.muted)
                let labelWidth = (label as NSString).size(withAttributes: [.font: font]).width
                symbol("shuffle", in: CGRect(x: 12 + ceil(labelWidth), y: row.midY - 8, width: 20, height: 16),
                       tint: Self.browse.muted)
                continue
            }
            let track = session.tracks[index - 1]
            let selected = index == selectedRow
            let playing = index == playingRow
            if selected {
                gradient(row, top: Self.rgb(58, 180, 229), bottom: Self.rgb(4, 139, 207))
                fill(Self.rgb(8, 125, 189), 0, row.maxY - 1, row.width, 1)
            }
            let ink = selected ? NSColor.white : Self.browse.text
            let titleRect = CGRect(x: 6, y: row.midY - 12, width: row.width - (playing ? 33 : 12), height: 24)
            text(track.title.isEmpty ? "タイトルなし" : track.title, at: titleRect,
                 size: 17, weight: selected ? .semibold : .medium, color: ink)
            if playing {
                symbol("speaker.wave.2.fill", in: CGRect(x: row.maxX - 24, y: row.midY - 8, width: 18, height: 16),
                       tint: ink)
            }
        }
        if let notice = session.notice {
            message(notice, color: Self.browse.muted, y: 294, height: 77, size: 13)
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
        symbol(name, in: CGRect(x: x, y: 3, width: width, height: 14), tint: Self.playback.muted)
    }

    private func symbol(_ name: String, in rect: CGRect, tint: NSColor) {
        let config = NSImage.SymbolConfiguration(paletteColors: [tint])
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let w = image.size.width * scale, h = image.size.height * scale
        image.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h),
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
