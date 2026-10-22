import Charts
import SwiftData
import SwiftUI

struct ResultsView: View {
    @Query(filter: #Predicate<Night> { $0.isInProgress == false }, sort: \Night.startDate)
    private var nights: [Night]
    @Query(sort: \Remedy.sortOrder) private var remedies: [Remedy]
    @AppStorage(SettingsKey.demoMode) private var demoMode = false

    var body: some View {
        let report = ResultsBuilder.report(nights: nights, remedies: remedies)
        let excludedCount = nights.filter { !$0.countsTowardResults }.count

        NavigationStack {
            Group {
                if report.isEmpty {
                    ContentUnavailableView {
                        Label("No results yet", systemImage: "chart.bar.xaxis")
                    } description: {
                        Text("Start with \(RemedyAnalyzer.minimumNights) nights without any remedy. Then try a remedy for \(RemedyAnalyzer.minimumNights) nights and SnoreGuard will compare them here.")
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if demoMode {
                                DemoBanner()
                            }
                            summaryCard(report)
                            chartCard(report)
                            VStack(spacing: 12) {
                                if let baseline = report.baseline {
                                    RemedyResultRow(item: baseline)
                                }
                                ForEach(report.remedies) { item in
                                    RemedyResultRow(item: item)
                                }
                            }
                            MethodCard(excludedCount: excludedCount)
                        }
                        .padding()
                    }
                }
            }
            .screenBackground()
            .navigationTitle("Results")
        }
    }

    private func summaryCard(_ report: RemedyReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "So far")
            Text(report.summary)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func chartCard(_ report: RemedyReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Snore minutes per hour")
            RemedyChart(report: report)
            Text("Bars show the average night. Lines show ±1 standard deviation; the dashed line is your baseline.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }
}

/// One horizontal bar per remedy with ±1 SD error bars and a dashed baseline reference.
private struct RemedyChart: View {
    let report: RemedyReport

    var body: some View {
        let items = report.all
        Chart {
            ForEach(items) { item in
                BarMark(
                    x: .value("Snore minutes per hour", item.mean),
                    y: .value("Remedy", item.name),
                    height: .ratio(0.55)
                )
                .foregroundStyle(item.isBaseline ? Theme.baselineBar : Theme.accent)
                .cornerRadius(6)
                .accessibilityLabel(item.name)
                .accessibilityValue("\(Format.perHour(item.mean)) snore minutes per hour, \(Format.nights(item.nights)), \(item.label.title)")

                if item.nights > 1 {
                    RuleMark(
                        xStart: .value("Low", max(0, item.mean - item.standardDeviation)),
                        xEnd: .value("High", item.mean + item.standardDeviation),
                        y: .value("Remedy", item.name)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityHidden(true)
                }
            }
            if let baseline = report.baseline {
                RuleMark(x: .value("Baseline", baseline.mean))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(.white.opacity(0.6))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Baseline")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .accessibilityLabel("Baseline")
                    .accessibilityValue("\(Format.perHour(baseline.mean)) snore minutes per hour")
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.cardBorder)
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
        .frame(height: CGFloat(items.count) * 52 + 40)
    }
}

private struct RemedyResultRow: View {
    let item: RemedyComparison

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbol)
                .font(.title3)
                .frame(width: 32)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.isBaseline ? "No remedy (baseline)" : item.name)
                        .font(.headline)
                    Spacer()
                    EffectPill(label: item.label)
                }
                HStack(spacing: 14) {
                    metric(Format.perHour(item.mean), "min/h")
                    metric(Format.nights(item.nights), nil)
                    if let change = item.percentChange {
                        metric(Format.percentChange(change), "vs baseline")
                    }
                }
                if let detail = item.label.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func metric(_ value: String, _ unit: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

private struct MethodCard: View {
    let excludedCount: Int

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text("Each remedy's nights are compared with your nights without a remedy, using snore minutes per hour so short and long nights count equally.")
                Text("“Likely helps” needs at least \(RemedyAnalyzer.minimumNights) nights of each, at least 20% less snoring, and a permutation test showing the drop is unlikely to be chance (p < 0.1).")
                Text("“Might help” means at least 10% less snoring, but not enough evidence yet. “Seems worse” means at least 10% more.")
                if excludedCount > 0 {
                    Text("\(Format.nights(excludedCount)) shorter than 30 minutes \(excludedCount == 1 ? "isn't" : "aren't") counted.")
                }
                Text(Disclaimer.text)
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            .padding(.top, 8)
        } label: {
            Text("How SnoreGuard decides")
                .font(.subheadline.weight(.semibold))
        }
        .card()
    }
}
