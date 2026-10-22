import Combine
import SwiftUI

/// The overnight screen: near-black, large elapsed time, a live indicator and a Stop button.
/// Content fades almost to black after a short while; tap anywhere to bring it back.
struct RecordingView: View {
    @Environment(RecordingService.self) private var recording
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastInteraction = Date()
    @State private var batteryState: UIDevice.BatteryState = .unknown
    @State private var confirmingStop = false
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 64

    private let dimAfter: TimeInterval = 20

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let isDimmed = timeline.date.timeIntervalSince(lastInteraction) > dimAfter
            content(now: timeline.date)
                .opacity(isDimmed ? 0.12 : 1)
                .animation(.easeInOut(duration: 1.5), value: isDimmed)
                .overlay {
                    if isDimmed {
                        // While dimmed, the first tap only wakes the screen.
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .onTapGesture(perform: wake)
                            .accessibilityLabel("Show recording controls")
                            .accessibilityAddTraits(.isButton)
                    }
                }
        }
        .background(Color.black.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture(perform: wake)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            updateBatteryState()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            updateBatteryState()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                recording.resumeIfNeeded()
            }
        }
        .confirmationDialog("End the night?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop and save") {
                Task { await recording.stopNight(save: true) }
            }
            Button("Discard this night", role: .destructive) {
                Task { await recording.stopNight(save: false) }
            }
            Button("Keep listening", role: .cancel) {}
        }
    }

    private func content(now: Date) -> some View {
        let elapsed = recording.startDate.map { now.timeIntervalSince($0) } ?? 0
        let isSnoring = recording.lastSnoringDate.map { now.timeIntervalSince($0) < DetectionConfig.snoringIndicatorHold } ?? false

        return VStack(spacing: 28) {
            Spacer()
            Label(recording.remedyName, systemImage: recording.remedySymbol)
                .font(.headline)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityLabel("Tonight's remedy: \(recording.remedyName)")

            Text(Format.clock(elapsed))
                .font(.system(size: clockSize, weight: .thin, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityLabel("Listening for \(Format.spokenDuration(elapsed))")

            ListeningIndicator(isSnoring: isSnoring, isPaused: recording.isPaused)

            Text("\(recording.eventCount) snore \(recording.eventCount == 1 ? "event" : "events") so far")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)

            if let failure = recording.failureMessage {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.worse)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if batteryState == .unplugged {
                Label("Plug in your phone. Listening all night uses a lot of battery.", systemImage: "battery.25percent")
                    .font(.footnote)
                    .foregroundStyle(Theme.worse)
                    .multilineTextAlignment(.center)
            }

            Button {
                wake()
                confirmingStop = true
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .foregroundStyle(.white)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ends the night and shows its summary")
        }
        .padding(24)
    }

    private func wake() {
        lastInteraction = Date()
    }

    /// Keeps the screen on while charging (the dark screen is easy on the eyes); on battery the
    /// phone may lock as usual and listening continues in the background.
    private func updateBatteryState() {
        batteryState = UIDevice.current.batteryState
        UIApplication.shared.isIdleTimerDisabled = batteryState == .charging || batteryState == .full
    }
}

private struct ListeningIndicator: View {
    let isSnoring: Bool
    let isPaused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .symbolEffect(.variableColor.iterative, isActive: isSnoring)
                .accessibilityHidden(true)
            Text(text)
        }
        .font(.headline)
        .foregroundStyle(isSnoring ? Theme.accent : Theme.secondaryText)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background((isSnoring ? Theme.accent : Color.white).opacity(0.1), in: Capsule())
        .animation(.easeInOut, value: isSnoring)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        if isPaused { return "pause.circle" }
        return isSnoring ? "waveform" : "ear"
    }

    private var text: String {
        if isPaused { return "Paused. Will resume automatically" }
        return isSnoring ? "Snoring detected" : "Listening…"
    }
}
