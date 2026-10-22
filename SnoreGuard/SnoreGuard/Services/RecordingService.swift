import AVFoundation
import Foundation
import Observation
import SwiftData

/// Runs one night: owns the detector, merges windows into events as they arrive,
/// checkpoints the night every few minutes and saves it when the user taps Stop.
@MainActor
@Observable
final class RecordingService {
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var isAnalyzingFile = false
    private(set) var startDate: Date?
    private(set) var remedyName = ""
    private(set) var remedySymbol = "moon.zzz"
    private(set) var eventCount = 0
    /// When the last window above the threshold arrived. Drives the live indicator.
    private(set) var lastSnoringDate: Date?
    private(set) var failureMessage: String?
    /// The night that just finished, shown as a morning summary.
    var completedNight: Night?

    @ObservationIgnored private var detector: (any SnoreDetecting)?
    @ObservationIgnored private var consumeTask: Task<Void, Never>?
    @ObservationIgnored private var merger = EventMerger()
    @ObservationIgnored private var night: Night?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var clipRecorder: SnoreClipRecorder?
    /// Clip file names keyed by the start offset of the event they belong to.
    @ObservationIgnored private var clipFileNames: [TimeInterval: String] = [:]
    @ObservationIgnored private var persistedEventCount = 0
    @ObservationIgnored private var lastCheckpoint = Date.distantPast
    @ObservationIgnored private var isStopping = false

    // MARK: - Live nights

    func startNight(remedy: Remedy, sensitivity: Sensitivity, saveClips: Bool, context: ModelContext) throws {
        guard !isRecording else { return }
        let detector = LiveSnoreDetector()
        let recorder = saveClips ? SnoreClipRecorder() : nil
        if let recorder {
            detector.bufferHandler = { buffer in recorder.append(buffer) }
        }
        let start = Date()
        let stream = try detector.start()

        let night = Night(startDate: start, threshold: sensitivity.threshold, source: .microphone)
        night.isInProgress = true
        context.insert(night)
        night.remedy = remedy
        try? context.save()

        self.detector = detector
        self.context = context
        self.night = night
        clipRecorder = recorder
        merger = EventMerger(threshold: sensitivity.threshold)
        clipFileNames = [:]
        persistedEventCount = 0
        lastCheckpoint = start
        startDate = start
        remedyName = remedy.name
        remedySymbol = remedy.symbol
        eventCount = 0
        lastSnoringDate = nil
        failureMessage = nil
        isPaused = false
        isRecording = true

        consumeTask = Task { [weak self] in
            do {
                for try await event in stream {
                    self?.handle(event)
                }
            } catch {
                self?.failureMessage = "Listening stopped: \(error.localizedDescription) Tap Stop to save what was recorded."
            }
        }
    }

    /// Ends the night. `save: false` discards it (for accidental starts).
    func stopNight(save: Bool) async {
        guard isRecording, !isStopping, let detector else { return }
        isStopping = true
        defer { isStopping = false }

        detector.stop()
        await consumeTask?.value
        merger.finish()
        persistNewEvents()

        if let night, let context {
            if save {
                night.endDate = Date()
                night.recordedDuration = detector.listenedDuration
                night.isInProgress = false
                night.recomputeTotals()
                try? context.save()
                completedNight = night
            } else {
                NightStore.delete(night, in: context)
                try? context.save()
            }
        }
        reset()
    }

    /// Nudges a paused detector, e.g. when the app returns to the foreground.
    func resumeIfNeeded() {
        (detector as? LiveSnoreDetector)?.resumeIfPaused()
    }

    private func handle(_ event: DetectorEvent) {
        switch event {
        case .window(let window):
            if merger.add(window) {
                lastSnoringDate = Date()
            }
            eventCount = merger.eventCount
            captureClipIfNeeded()
            persistNewEvents()
            checkpointIfNeeded()
        case .paused:
            isPaused = true
        case .resumed:
            isPaused = false
        }
    }

    /// Saves one clip per event, once the event is long enough to be kept, up to the nightly cap.
    private func captureClipIfNeeded() {
        guard let recorder = clipRecorder,
              let night,
              clipFileNames.count < DetectionConfig.maxClipsPerNight,
              let open = merger.openEvent,
              open.duration >= DetectionConfig.minimumEventDuration,
              clipFileNames[open.start] == nil else { return }
        let fileName = "\(night.id.uuidString)-\(clipFileNames.count + 1).m4a"
        clipFileNames[open.start] = fileName
        recorder.saveClip(to: ClipStore.url(for: fileName))
    }

    /// Stores events the merger has closed since the last call.
    private func persistNewEvents() {
        guard let night, let context, merger.events.count > persistedEventCount else { return }
        for event in merger.events[persistedEventCount...] {
            night.addEvent(event, clipFileName: clipFileNames[event.start], in: context)
        }
        persistedEventCount = merger.events.count
    }

    private func checkpointIfNeeded() {
        guard let night, let context, let detector else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCheckpoint) >= DetectionConfig.checkpointInterval else { return }
        lastCheckpoint = now
        night.endDate = now
        night.recordedDuration = detector.listenedDuration
        night.recomputeTotals()
        try? context.save()
    }

    private func reset() {
        consumeTask = nil
        detector = nil
        night = nil
        context = nil
        clipRecorder = nil
        clipFileNames = [:]
        persistedEventCount = 0
        startDate = nil
        eventCount = 0
        lastSnoringDate = nil
        failureMessage = nil
        isPaused = false
        isRecording = false
    }

    // MARK: - Audio files

    /// Runs the detection pipeline over an audio file and saves the result as a night.
    func analyzeFile(at url: URL, remedy: Remedy, sensitivity: Sensitivity, context: ModelContext) async throws -> Night {
        isAnalyzingFile = true
        defer { isAnalyzingFile = false }

        let detector = FileSnoreDetector(url: url)
        var fileMerger = EventMerger(threshold: sensitivity.threshold)
        for try await event in try detector.start() {
            if case .window(let window) = event {
                fileMerger.add(window)
            }
        }
        let events = fileMerger.finish()

        let start = Date()
        let night = Night(startDate: start, threshold: sensitivity.threshold, source: .file)
        context.insert(night)
        night.remedy = remedy
        for event in events {
            night.addEvent(event, in: context)
        }
        night.endDate = start.addingTimeInterval(detector.listenedDuration)
        night.recordedDuration = detector.listenedDuration
        night.recomputeTotals()
        try context.save()
        return night
    }
}
