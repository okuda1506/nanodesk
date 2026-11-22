import AppKit
import CoreImage
import ImageIO

/// Draws into the landscape LCD's flipped 376 × 240 coordinate system.
@MainActor
final class CoverFlowRenderer {
    private let service: any MusicService
    private lazy var compositor = CIContext(options: [.cacheIntermediates: false])
    private let tiles = NSCache<NSString, CIImage>()
    private var wanted: [MusicAlbum] = []
    private var nextTrack: [String: Int] = [:]
    private var failed = Set<String>()
    private var loader: Task<Void, Never>?
    private var motion = CoverFlowMotion()
    private var browsing = false
    private(set) var animating = false
    var artworkChanged: (() -> Void)?
    private lazy var placeholder = Self.tile(image: nil)

    init(service: any MusicService) {
        self.service = service
        tiles.countLimit = 48
    }

    func leave() {
        wanted = []
        nextTrack.removeAll()
        failed.removeAll()
        browsing = false
        animating = false
    }

    func draw(_ session: MusicSession) {
        let browser = session.covers
        guard let album = browser.album else {
            leave()
            label(browser.loading ? "アルバムを読み込み中…" : browser.notice ?? "",
                  in: CGRect(x: 16, y: 92, width: 344, height: 66), size: 15, bold: false, wraps: true)
            return
        }
        if let selected = browser.trackIndex {
            leave()
            trackList(album, selected: selected, playing: session.playback, notice: session.notice)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        motion.move(to: browser.index, at: now, snap: !browsing || browser.scanning)
        browsing = true
        let state = motion.sample(at: now)
        animating = state.moving
        let center = state.position
        let nearest = max(0, min(browser.albums.count - 1, Int(center.rounded())))
        let range = max(0, nearest - 5)...min(browser.albums.count - 1, nearest + 5)
        let indices = range.sorted { abs(Double($0) - center) < abs(Double($1) - center) }
        wanted = indices.map { browser.albums[$0] }
        requestTiles()

        let viewport = CGRect(x: 0, y: 0, width: 376, height: 220)
        var stack = CIImage(color: .white).cropped(to: viewport)
        for index in indices.reversed() {
            let id = browser.albums[index].tracks[0].id as NSString
            let tile = tiles.object(forKey: id) ?? placeholder
            stack = projected(tile, distance: Double(index) - center).composited(over: stack)
        }
        if let raster = compositor.createCGImage(stack, from: viewport) {
            NSImage(cgImage: raster, size: viewport.size).draw(
                in: viewport.offsetBy(dx: 0, dy: 20), from: .zero, operation: .copy,
                fraction: 1, respectFlipped: true, hints: nil)
        }
        if let notice = session.notice {
            label(notice, in: CGRect(x: 10, y: 187, width: 356, height: 51), size: 13, bold: false, wraps: true)
        } else {
            label(album.title, in: CGRect(x: 5, y: 190, width: 366, height: 20), size: 16, bold: true)
            label(album.artist, in: CGRect(x: 5, y: 208, width: 366, height: 21), size: 14, bold: false)
        }
        if browser.scanning {
            let badge = CGRect(x: 154, y: 75, width: 68, height: 66)
            NSColor.black.withAlphaComponent(0.78).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 9, yRadius: 9).fill()
            label(String(album.initial), in: badge, size: 43, bold: true, color: .white)
        }
    }

    // Each side sleeve narrows toward the center. Its reflection shares its
    // perspective transform, so the bottom seam stays attached as it turns.
    private func projected(_ tile: CIImage, distance: Double) -> CIImage {
        let d = abs(distance)
        let turn = min(1, d)
        let sign = distance < 0 ? -1.0 : 1.0
        let centerX = 188 + sign * (85 * turn + 29 * max(0, d - 1))
        let halfWidth = 64 - 43 * turn
        let leftHeight = 64 - (distance > 0 ? 22 * turn : 0)
        let rightHeight = 64 - (distance < 0 ? 22 * turn : 0)
        // CI uses bottom-left coordinates. The visible square is centered at LCD y=111.
        let axis = 129.0
        return tile.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": CIVector(x: centerX - halfWidth, y: axis + leftHeight),
            "inputTopRight": CIVector(x: centerX + halfWidth, y: axis + rightHeight),
            "inputBottomLeft": CIVector(x: centerX - halfWidth, y: axis - 2 * leftHeight),
            "inputBottomRight": CIVector(x: centerX + halfWidth, y: axis - 2 * rightHeight)
        ])
    }

    /// One outstanding Music request. Between requests consult the newest visible
    /// range, including when the wheel reverses direction during an Apple event.
    private func nextAlbum() -> MusicAlbum? {
        wanted.filter {
            let id = $0.tracks[0].id
            return !failed.contains(id) && tiles.object(forKey: id as NSString) == nil
        }.min { nextTrack[$0.tracks[0].id, default: 0] < nextTrack[$1.tracks[0].id, default: 0] }
    }

    private func requestTiles() {
        guard loader == nil, nextAlbum() != nil else { return }
        loader = Task { [weak self] in
            guard let self else { return }
            defer { loader = nil }
            while let album = nextAlbum() {
                let id = album.tracks[0].id
                let index = min(nextTrack[id, default: 0], album.tracks.count - 1)
                do {
                    let bytes = try await service.artwork(for: album.tracks[index].id)
                    if let bytes, let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                       let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                           kCGImageSourceCreateThumbnailFromImageAlways: true,
                           kCGImageSourceCreateThumbnailWithTransform: true,
                           kCGImageSourceThumbnailMaxPixelSize: 192
                       ] as CFDictionary) {
                        tiles.setObject(Self.tile(image: image), forKey: id as NSString)
                    } else if index + 1 == album.tracks.count {
                        tiles.setObject(placeholder, forKey: id as NSString)
                    } else if wanted.contains(where: { $0.id == album.id }) {
                        // Give other visible sleeves a turn before trying the next track on this album.
                        nextTrack[id] = index + 1
                        continue
                    }
                } catch {
                    if wanted.contains(where: { $0.id == album.id }) { failed.insert(id) }
                }
                nextTrack[id] = nil
                if wanted.contains(where: { $0.id == album.id }) { artworkChanged?() }
            }
        }
    }

    private static func tile(image: CGImage?) -> CIImage {
        let edge = 160
        let square = CGRect(x: 0, y: 0, width: edge, height: edge)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: edge, height: 240, bitsPerComponent: 8,
                                      bytesPerRow: edge * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return CIImage(color: .white).cropped(to: square)
        }
        func drawFace() {
            context.saveGState()
            context.clip(to: square)
            if let image {
                let scale = CGFloat(edge) / CGFloat(min(image.width, image.height))
                let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                context.draw(image, in: CGRect(x: square.midX - size.width / 2, y: square.midY - size.height / 2,
                                               width: size.width, height: size.height))
            } else {
                let gradient = CGGradient(colorsSpace: space, colors: [
                    NSColor(white: 0.53, alpha: 1).cgColor, NSColor(white: 0.3, alpha: 1).cgColor
                ] as CFArray, locations: nil)!
                context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 160), end: .zero, options: [])
                let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(paletteColors: [.white]))
                if let glyph = note?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    let w = 82 * CGFloat(glyph.width) / CGFloat(glyph.height)
                    context.draw(glyph, in: CGRect(x: (160 - w) / 2, y: 39, width: w, height: 82))
                }
            }
            context.restoreGState()
        }
        context.translateBy(x: 0, y: 80)
        drawFace()
        context.scaleBy(x: 1, y: -1)
        drawFace()
        context.clip(to: CGRect(x: 0, y: 0, width: edge, height: 80))
        let fade = CGGradient(colorsSpace: space, colors: [
            NSColor.white.withAlphaComponent(0.48).cgColor, NSColor.white.cgColor
        ] as CFArray, locations: nil)!
        context.drawLinearGradient(fade, start: .zero, end: CGPoint(x: 0, y: 80), options: [])
        return context.makeImage().map { CIImage(cgImage: $0) } ?? CIImage(color: .white).cropped(to: square)
    }

    private func trackList(_ album: MusicAlbum, selected: Int, playing: MusicPlayback?, notice: String?) {
        let capacity = notice == nil ? 8 : 6
        let first = max(0, selected - capacity + 1)
        for i in first..<min(first + capacity, album.tracks.count) {
            let rect = CGRect(x: 0, y: 20 + (i - first) * 27, width: 376, height: 27)
            let ink: NSColor = i == selected ? .white : .black
            if i == selected {
                NSGradient(starting: NSColor(srgbRed: 0.24, green: 0.72, blue: 0.93, alpha: 1),
                           ending: NSColor(srgbRed: 0.03, green: 0.48, blue: 0.76, alpha: 1))?.draw(in: rect, angle: 90)
            }
            let track = album.tracks[i]
            label(track.title.isEmpty ? "タイトルなし" : track.title, in: rect.insetBy(dx: 28, dy: 0),
                  size: 15, bold: i == selected, color: ink, align: .left)
            label("\(i + 1)", in: CGRect(x: 0, y: rect.minY, width: 25, height: 27),
                  size: 12, bold: false, color: ink, align: .right)
            if playing?.track.id == track.id {
                label(playing?.isPlaying == true ? "▶" : "Ⅱ", in: CGRect(x: 347, y: rect.minY, width: 24, height: 27),
                      size: 12, bold: true, color: ink)
            }
        }
        if let notice {
            label(notice, in: CGRect(x: 8, y: 184, width: 360, height: 54), size: 13, bold: false, wraps: true)
        }
    }

    private func label(_ text: String, in rect: CGRect, size: CGFloat, bold: Bool, color: NSColor = .black,
                       align: NSTextAlignment = .center, wraps: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        let value = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: bold ? .bold : .medium),
            .foregroundColor: color, .paragraphStyle: style
        ])
        let height = min(rect.height, ceil(value.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin], context: nil).height))
        value.draw(with: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }
}
