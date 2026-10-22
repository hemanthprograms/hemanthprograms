import AVFoundation
import Foundation

/// Listens to the microphone all night.
///
/// Engine control and notifications run on the main queue; classification runs on a private
/// serial queue. After an interruption (a call, Siri), a route change or a media-services reset
/// it rebuilds the engine and carries on, starting a fresh classifier segment whose window
/// times are offset by the wall-clock time since the night started.
final class LiveSnoreDetector: SnoreDetecting, @unchecked Sendable {
    /// Receives every captured buffer on the analysis queue. Used for the optional snore clips.
    var bufferHandler: ((AVAudioPCMBuffer) -> Void)?

    private var engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()
    private let analysisQueue = DispatchQueue(label: "com.hemanthprograms.snoreguard.live-analysis", qos: .userInitiated)
    /// Only touched on `analysisQueue`.
    private var pipeline: SoundClassifierPipeline?
    private var continuation: AsyncThrowingStream<DetectorEvent, Error>.Continuation?
    private var notificationTokens: [NSObjectProtocol] = []
    private var startDate = Date()
    private var segmentStart: Date?
    private var accumulatedDuration: TimeInterval = 0
    private var isActive = false
    private var isRetryScheduled = false

    private static let tapBufferSize: AVAudioFrameCount = 8_192
    private static let retryDelay: TimeInterval = 15

    var listenedDuration: TimeInterval {
        accumulatedDuration + (segmentStart.map { Date().timeIntervalSince($0) } ?? 0)
    }

    func start() throws -> AsyncThrowingStream<DetectorEvent, Error> {
        guard !isActive else { throw SnoreDetectorError.alreadyRunning }
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let (stream, continuation) = AsyncThrowingStream<DetectorEvent, Error>.makeStream()
        self.continuation = continuation
        startDate = Date()
        accumulatedDuration = 0
        isActive = true
        do {
            try startEngine()
        } catch {
            isActive = false
            continuation.finish()
            self.continuation = nil
            try? session.setActive(false)
            throw error
        }
        observeSessionNotifications()
        return stream
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        tearDownEngine()
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens = []
        continuation?.finish()
        continuation = nil
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Tries to resume straight away, e.g. when the app returns to the foreground.
    func resumeIfPaused() {
        restartIfNeeded()
    }

    // MARK: - Engine

    private func startEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SnoreDetectorError.microphoneUnavailable
        }
        let continuation = self.continuation
        let pipeline = try SoundClassifierPipeline(
            format: format,
            timeOffset: Date().timeIntervalSince(startDate),
            onWindow: { window in continuation?.yield(.window(window)) },
            onError: { error in continuation?.finish(throwing: error) }
        )
        analysisQueue.sync { self.pipeline = pipeline }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: format) { [weak self] buffer, _ in
            self?.enqueue(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            analysisQueue.sync { self.pipeline = nil }
            throw error
        }
        segmentStart = Date()
    }

    private func enqueue(_ buffer: AVAudioPCMBuffer) {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.pipeline?.analyze(buffer)
            self.bufferHandler?(buffer)
        }
    }

    /// Stops the engine and flushes the current classifier segment.
    private func tearDownEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let segmentStart {
            accumulatedDuration += Date().timeIntervalSince(segmentStart)
        }
        segmentStart = nil
        analysisQueue.sync {
            self.pipeline?.finish()
            self.pipeline = nil
        }
    }

    /// Restarts listening if the night is still on but the engine isn't running.
    private func restartIfNeeded() {
        guard isActive, !engine.isRunning else { return }
        if segmentStart != nil {
            // The system stopped the engine underneath us; close that segment first.
            tearDownEngine()
        }
        do {
            try session.setActive(true)
            try startEngine()
            continuation?.yield(.resumed)
        } catch {
            continuation?.yield(.paused)
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard !isRetryScheduled else { return }
        isRetryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay) { [weak self] in
            guard let self else { return }
            self.isRetryScheduled = false
            self.restartIfNeeded()
        }
    }

    // MARK: - Session notifications

    private func observeSessionNotifications() {
        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
                self?.handleInterruption(note)
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] _ in
                self?.restartIfNeeded()
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
                self?.handleMediaServicesReset()
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] note in
                self?.handleConfigurationChange(note)
            },
        ]
    }

    private func handleInterruption(_ note: Notification) {
        guard let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        if type == .began {
            guard isActive, segmentStart != nil else { return }
            tearDownEngine()
            continuation?.yield(.paused)
        } else if type == .ended {
            // Resume whether or not the system suggests it: this is an overnight recording.
            restartIfNeeded()
        }
    }

    private func handleConfigurationChange(_ note: Notification) {
        guard isActive, (note.object as? AVAudioEngine) === engine else { return }
        // The input format changed (for example a headset was plugged in); rebuild with the new format.
        if segmentStart != nil {
            tearDownEngine()
        }
        restartIfNeeded()
    }

    private func handleMediaServicesReset() {
        guard isActive else { return }
        if segmentStart != nil {
            tearDownEngine()
        }
        engine = AVAudioEngine()
        try? session.setCategory(.record, mode: .measurement)
        restartIfNeeded()
    }
}
