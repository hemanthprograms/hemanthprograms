import Charts
import SwiftData
import SwiftUI

struct NightDetailView: View {
    let night: Night

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var player = ClipPlayer()
    @State private var confirmingDelete = false
    @State private var showingAllEvents = false

    var body: some View {
        Group {
            if night.modelContext == nil {
                ContentUnavailableView("Night deleted", systemImage: "trash")
            } else {
                content
            }
        }
        .screenBackground()
        .navigationTitle(Format.nightTitle(night.startDate))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete night", systemImage: "trash", role: .destructive) {
                        confirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("More")
                }
            }
        }
        .confirmationDialog("Delete this night?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete night", role: .destructive, action: deleteNight)
        } message: {
            Text("Its events and any saved clips will be removed.")
        }
        .onDisappear { player.stop() }
    }

    private var content: some View {
        let events = night.sortedEvents
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                stats
                if events.isEmpty {
                    noEventsCard
                } else {
                    TimelineCard(night: night, events: events)
                    HourlyCard(night: night, events: events)
                    eventsCard(events)
                }
            }
            .padding()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(Format.time(night.startDate)) – \(Format.time(night.endDate))")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            if let remedy = night.remedy {
                RemedyBadge(name: remedy.name, symbol: remedy.symbol)
            }
            NightTags(night: night)
            if !night.countsTowardResults {
                Text("Recordings shorter than 30 minutes are kept but not used in your results.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            if night.wasRecovered {
                Text("SnoreGuard closed before you tapped Stop, so this night was restored from its last save.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var stats: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.perHour(night.snoreMinutesPerHour))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                Text("snore minutes\nper hour")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Snore minutes per hour")
            .accessibilityValue(Format.perHour(night.snoreMinutesPerHour))

            HStack {
                StatTile(value: Format.minutes(night.totalSnoreMinutes), unit: "min", caption: "Snoring")
                StatTile(value: "\(night.eventCount)", unit: "", caption: "Snore events")
                StatTile(
                    value: Format.duration(night.recordedDuration),
                    unit: "",
                    caption: "Recorded",
                    spokenValue: Format.spokenDuration(night.recordedDuration)
                )
            }
        }
        .card()
    }

    private var noEventsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.title)
                .foregroundStyle(Theme.accent)
            Text("No snoring detected")
                .font(.headline)
            Text("A quiet night. If you expected snoring, try a higher detection sensitivity in Settings or move the phone closer.")
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }

    private func eventsCard(_ events: [SnoreEvent]) -> some View {
        let visible = showingAllEvents ? events : Array(events.prefix(8))
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Snore events")
            ForEach(visible) { event in
                eventRow(event)
                if event.persistentModelID != visible.last?.persistentModelID {
                    Divider().overlay(Theme.cardBorder)
                }
            }
            if events.count > visible.count {
                Button("Show all \(events.count) events") { showingAllEvents = true }
                    .font(.subheadline)
            }
        }
        .card()
    }

    private func eventRow(_ event: SnoreEvent) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.time(event.startDate))
                    .monospacedDigit()
                Text("\(Format.duration(event.duration)) · peak \(Int((event.peakConfidence * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if let clip = event.clipFileName, ClipStore.existingURL(for: clip) != nil {
                Button {
                    player.toggle(clip)
                } label: {
                    Image(systemName: player.playingFileName == clip ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.playingFileName == clip ? "Stop clip" : "Play clip")
            }
        }
        .font(.subheadline)
    }

    private func deleteNight() {
        player.stop()
        dismiss()
        // Delete after the screen has gone so SwiftUI never renders a deleted model.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            NightStore.delete(night, in: context)
            try? context.save()
        }
    }
}

/// Each snore event as a mark on the night's timeline.
private struct TimelineCard: View {
    let night: Night
    let events: [SnoreEvent]

    var body: some View {
        // Very short events would be invisible at this scale, so give each a minimum width.
        let minimumWidth = max(night.endDate.timeIntervalSince(night.startDate) / 160, 1)
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Through the night")
            Chart {
                ForEach(events) { event in
                    RectangleMark(
                        xStart: .value("Start", event.startDate),
                        xEnd: .value("End", event.startDate.addingTimeInterval(max(event.duration, minimumWidth))),
                        yStart: .value("Bottom", 0),
                        yEnd: .value("Top", 1)
                    )
                    .foregroundStyle(Theme.accent.opacity(0.35 + 0.65 * event.peakConfidence))
                    .accessibilityLabel(Format.time(event.startDate))
                    .accessibilityValue("Snoring for \(Format.spokenDuration(event.duration))")
                }
            }
            .chartXScale(domain: night.startDate...max(night.endDate, night.startDate.addingTimeInterval(60)))
            .chartYScale(domain: 0...1)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Theme.cardBorder)
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .frame(height: 80)
            Text("Darker marks were more confidently snoring.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }
}

/// Snore minutes in each clock hour.
private struct HourlyCard: View {
    let night: Night
    let events: [SnoreEvent]

    struct Bucket: Identifiable {
        let hour: Date
        let minutes: Double
        var id: Date { hour }
    }

    var body: some View {
        let buckets = Self.buckets(for: night, events: events)
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Snore minutes by hour")
            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Hour", bucket.hour, unit: .hour),
                    y: .value("Snore minutes", bucket.minutes)
                )
                .foregroundStyle(Theme.accent.gradient)
                .cornerRadius(4)
                .accessibilityLabel(bucket.hour.formatted(date: .omitted, time: .shortened))
                .accessibilityValue("\(Format.perHour(bucket.minutes)) snore minutes")
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisGridLine().foregroundStyle(Theme.cardBorder)
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .frame(height: 160)
        }
        .card()
    }

    /// Splits each event across the clock hours it spans.
    static func buckets(for night: Night, events: [SnoreEvent]) -> [Bucket] {
        let calendar = Calendar.current
        guard let firstHour = calendar.dateInterval(of: .hour, for: night.startDate)?.start else { return [] }
        var minutesByHour: [Date: Double] = [:]
        var hour = firstHour
        while hour < night.endDate {
            minutesByHour[hour] = 0
            hour = hour.addingTimeInterval(3600)
        }
        for event in events {
            var cursor = event.startDate
            while cursor < event.endDate {
                guard let interval = calendar.dateInterval(of: .hour, for: cursor) else { break }
                let sliceEnd = min(interval.end, event.endDate)
                minutesByHour[interval.start, default: 0] += sliceEnd.timeIntervalSince(cursor) / 60
                cursor = sliceEnd
            }
        }
        return minutesByHour.map { Bucket(hour: $0.key, minutes: $0.value) }.sorted { $0.hour < $1.hour }
    }
}
