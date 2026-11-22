@preconcurrency import AVFoundation
import CoreImage

/// One visit to the camera. Session configuration, samples and writer state all
/// run on the same serial queue. Only immutable, LCD-sized images reach the UI.
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                           AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Event: Sendable {
        case frame(CGImage, hasAudio: Bool), recording, saved, failure(String), saveFailure
    }

    private let queue: DispatchQueue
    private let receive: @MainActor @Sendable (Event) -> Void
    private let session = AVCaptureSession()
    private let video = AVCaptureVideoDataOutput()
    private let audio = AVCaptureAudioDataOutput()
    private lazy var context = CIContext(options: [.cacheIntermediates: false])
    private let videoColorSpace = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
    private let sensorBounds = CGRect(x: 0, y: 0, width: Int(ND_CAMERA_WIDTH), height: Int(ND_CAMERA_HEIGHT))
    private var sensorPool: CVPixelBufferPool?
    private var frameSeed: UInt32 = 0
    private var moviePixels: AVAssetWriterInputPixelBufferAdaptor?
    private var previousMovieFrame: CVPixelBuffer?
    private var lastVideoSlot: Int64 = -1
    private let frameSlot = DispatchSemaphore(value: 1)
    private let finalizing = DispatchGroup()
    private var observer: NSObjectProtocol?
    private var watchdog: DispatchSourceTimer?
    private var lastFrame = 0.0
    private var hasAudio = false
    private var ended = false
    private var requestedRecording = false
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var firstVideoTime = CMTime.invalid

    init(queue: DispatchQueue, receive: @escaping @MainActor @Sendable (Event) -> Void) {
        self.queue = queue
        self.receive = receive
    }

    private func send(_ event: Event) {
        DispatchQueue.main.async { self.receive(event) }
    }

    func start(microphone: Bool) {
        queue.async {
            guard !self.ended else { return }
            do {
                let camera = try self.configure(microphone: microphone)
                self.setFrameRate(on: camera)
                self.observer = NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                    object: self.session, queue: nil) { [weak self] _ in
                        guard let self else { return }
                        self.queue.async { self.fail("カメラとの接続が切れました。MENUで戻って開き直してください。") }
                    }
                self.session.startRunning()
                self.lastFrame = ProcessInfo.processInfo.systemUptime
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now() + 7, repeating: 1)
                timer.setEventHandler { [weak self] in
                    guard let self, ProcessInfo.processInfo.systemUptime - self.lastFrame >= 7 else { return }
                    self.fail("映像を取得できません。カメラの接続や使用状況を確認してください。")
                }
                self.watchdog = timer
                timer.resume()
            } catch {
                self.fail((error as? CaptureError)?.message ?? "カメラを起動できません。他のアプリの使用状況を確認してください。")
            }
        }
    }

    private struct CaptureError: Error { let message: String }

    private func configure(microphone: Bool) throws -> AVCaptureDevice {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                ?? AVCaptureDevice.default(for: .video) else {
            throw CaptureError(message: "カメラが見つかりません。接続を確認してください。")
        }
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: Int(ND_CAMERA_WIDTH),
            kCVPixelBufferHeightKey as String: Int(ND_CAMERA_HEIGHT),
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &sensorPool) == kCVReturnSuccess else {
            throw CaptureError(message: "VGA映像の準備ができません。")
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CaptureError(message: "カメラを使用できません。") }
        session.addInput(input)
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        video.alwaysDiscardsLateVideoFrames = true
        video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        guard session.canAddOutput(video) else { throw CaptureError(message: "カメラ映像を取得できません。") }
        session.addOutput(video)
        video.setSampleBufferDelegate(self, queue: queue)
        if let connection = video.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        if microphone, let mic = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: mic), session.canAddInput(input) {
            session.addInput(input)
            if session.canAddOutput(audio) {
                session.addOutput(audio)
                audio.setSampleBufferDelegate(self, queue: queue)
                hasAudio = true
            } else { session.removeInput(input) }
        }
        return camera
    }

    private func setFrameRate(on camera: AVCaptureDevice) {
        if camera.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }),
           (try? camera.lockForConfiguration()) != nil {
            let duration = CMTime(value: 1, timescale: 30)
            camera.activeVideoMinFrameDuration = duration
            camera.activeVideoMaxFrameDuration = duration
            camera.unlockForConfiguration()
        }
    }

    func record() {
        queue.async { if !self.ended && self.writer == nil { self.requestedRecording = true } }
    }

    func stopRecording() { queue.async { self.finishMovie() } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !ended, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if output === video {
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            guard let graded = sensorFrame(from: buffer) else {
                fail("VGA映像を生成できません。MENUで戻って開き直してください。")
                return
            }
            if requestedRecording {
                requestedRecording = false
                do { try beginMovie(at: time) }
                catch { fail("録画を開始できません。ムービーフォルダの空き容量とアクセス権を確認してください。"); return }
            }
            appendVideo(graded, at: time)
            guard !ended else { return }
            if frameSlot.wait(timeout: .now()) == .success {
                // Aspect-fill the LCD and mirror the viewfinder only.
                let source = CIImage(cvPixelBuffer: graded, options: [.colorSpace: videoColorSpace]).oriented(.upMirrored)
                let scale = max(240 / source.extent.width, 376 / source.extent.height)
                let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                let crop = CGRect(x: small.extent.midX - 120, y: small.extent.midY - 188, width: 240, height: 376)
                guard let frame = context.createCGImage(small, from: crop) else {
                    frameSlot.signal()
                    fail("プレビュー映像を表示できません。MENUで戻って開き直してください。")
                    return
                }
                lastFrame = ProcessInfo.processInfo.systemUptime
                let withAudio = hasAudio
                DispatchQueue.main.async {
                    defer { self.frameSlot.signal() }
                    self.receive(.frame(frame, hasAudio: withAudio))
                }
            }
        } else if firstVideoTime.isValid, CMTimeCompare(time, firstVideoTime) >= 0 {
            append(sampleBuffer, to: audioInput)
        }
    }

    private func sensorFrame(from source: CVPixelBuffer) -> CVPixelBuffer? {
        guard let sensorPool else { return nil }
        var target: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, sensorPool, &target) == kCVReturnSuccess, let target else { return nil }

        // The entire imaging pipeline uses a 4:3 VGA field, even when the device
        // only offers a widescreen capture preset.
        let image = CIImage(cvPixelBuffer: source)
        let scale = max(sensorBounds.width / image.extent.width, sensorBounds.height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let centered = scaled.transformed(by: CGAffineTransform(translationX: sensorBounds.midX - scaled.extent.midX,
                                                                 y: sensorBounds.midY - scaled.extent.midY))
        context.render(centered, to: target, bounds: sensorBounds, colorSpace: videoColorSpace)
        guard CVPixelBufferLockBaseAddress(target, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(target, []) }
        guard let bytes = CVPixelBufferGetBaseAddress(target) else { return nil }
        frameSeed &+= 1
        NDGradeCameraFrame(bytes.assumingMemoryBound(to: UInt8.self), CVPixelBufferGetBytesPerRow(target), frameSeed)
        CVBufferSetAttachment(target, kCVImageBufferCGColorSpaceKey, videoColorSpace, .shouldPropagate)
        return target
    }

    private func appendVideo(_ frame: CVPixelBuffer, at time: CMTime) {
        guard let writer, let videoInput, let moviePixels else { return }
        guard writer.status == .writing else {
            fail("動画を書き込めません。ムービーフォルダの空き容量を確認してください。")
            return
        }
        // Anchor the 30 Hz grid to the first capture timestamp so audio stays in sync.
        let slot = CMTimeConvertScale(CMTimeSubtract(time, firstVideoTime), timescale: ND_CAMERA_FPS,
                                      method: .roundHalfAwayFromZero)
        guard slot.isNumeric, slot.value > lastVideoSlot else { return }
        // In low light a camera can deliver fewer than 30 distinct pictures per
        // second. Hold the preceding picture over those slots without shifting audio.
        guard slot.value - lastVideoSlot <= Int64(ND_CAMERA_FPS) * 7 else {
            fail("カメラからの映像が途切れたため録画を終了しました。")
            return
        }
        for number in (lastVideoSlot + 1)...slot.value {
            guard videoInput.isReadyForMoreMediaData else { return }
            let picture = number == slot.value ? frame : (previousMovieFrame ?? frame)
            let pts = CMTimeAdd(firstVideoTime, CMTime(value: number, timescale: ND_CAMERA_FPS))
            guard moviePixels.append(picture, withPresentationTime: pts) else {
                fail("映像を書き込めません。ムービーフォルダの空き容量を確認してください。")
                return
            }
            lastVideoSlot = number
            previousMovieFrame = picture
        }
    }

    private func append(_ sample: CMSampleBuffer, to input: AVAssetWriterInput?) {
        guard let writer, let input else { return }
        if writer.status == .failed || (input.isReadyForMoreMediaData && !input.append(sample)) {
            fail("録画を書き込めません。ムービーフォルダの空き容量を確認してください。")
        }
    }

    static func movieFolder() throws -> URL {
        let movies = try FileManager.default.url(for: .moviesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = movies.appendingPathComponent("NanoDesk/Camera Roll", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func beginMovie(at time: CMTime) throws {
        let folder = try Self.movieFolder()
        let url = folder.appendingPathComponent(".nano_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString).mp4")
        let movie = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let picture = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(ND_CAMERA_WIDTH), AVVideoHeightKey: Int(ND_CAMERA_HEIGHT),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_500_000, AVVideoExpectedSourceFrameRateKey: Int(ND_CAMERA_FPS)
            ]
        ])
        picture.expectsMediaDataInRealTime = true
        guard movie.canAdd(picture) else { throw CaptureError(message: "映像を録画できません。") }
        movie.add(picture)
        var sound: AVAssetWriterInput?
        if hasAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96000
            ])
            input.expectsMediaDataInRealTime = true
            guard movie.canAdd(input) else { throw CaptureError(message: "音声を録音できません。") }
            movie.add(input)
            sound = input
        }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: picture, sourcePixelBufferAttributes: nil)
        guard movie.startWriting() else { throw CaptureError(message: "録画を開始できません。") }
        movie.startSession(atSourceTime: time)
        writer = movie
        moviePixels = adaptor
        lastVideoSlot = -1
        videoInput = picture
        audioInput = sound
        firstVideoTime = time
        send(.recording)
    }

    private func finishMovie() {
        requestedRecording = false
        guard let movie = writer else { return }
        writer = nil
        moviePixels = nil
        previousMovieFrame = nil
        let start = firstVideoTime
        firstVideoTime = .invalid
        guard movie.status == .writing else { send(.saveFailure); return }
        if lastVideoSlot >= 0 {
            let duration = CMTime(value: lastVideoSlot + 1, timescale: ND_CAMERA_FPS)
            movie.endSession(atSourceTime: CMTimeAdd(start, duration))
        }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        videoInput = nil
        audioInput = nil
        finalizing.enter()
        movie.finishWriting {
            defer { self.finalizing.leave() }
            guard movie.status == .completed else { self.send(.saveFailure); return }
            // Publish the MP4 only after its index has been written.
            let partial = movie.outputURL
            let name = String(partial.lastPathComponent.dropFirst())
            do {
                try FileManager.default.moveItem(at: partial, to: partial.deletingLastPathComponent().appendingPathComponent(name))
                self.send(.saved)
            } catch { self.send(.saveFailure) }
        }
    }

    private func fail(_ message: String) {
        guard !ended else { return }
        ended = true
        send(.failure(message))
        // stopRunning is synchronous. Unwind a sample delegate callback before stopping the session.
        queue.async { self.shutdown() }
    }

    private func shutdown() {
        ended = true
        watchdog?.cancel()
        watchdog = nil
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        finishMovie()
        if session.isRunning { session.stopRunning() }
        video.setSampleBufferDelegate(nil, queue: nil)
        audio.setSampleBufferDelegate(nil, queue: nil)
        for input in session.inputs { session.removeInput(input) }
    }

    func close(completion: @escaping @Sendable () -> Void) {
        queue.async {
            self.shutdown()
            self.finalizing.notify(queue: self.queue, execute: completion)
        }
    }
}
