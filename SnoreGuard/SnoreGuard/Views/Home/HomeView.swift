import SwiftData
import SwiftUI

enum HomeRoute: Hashable {
    case startNight
    case night(Night)
}

struct HomeView: View {
    @Query(filter: #Predicate<Night> { $0.isInProgress == false }, sort: \Night.startDate, order: .reverse)
    private var nights: [Night]
    @Query(sort: \Remedy.sortOrder) private var remedies: [Remedy]
    @Query(sort: \Plan.createdAt, order: .reverse) private var plans: [Plan]
    @AppStorage(SettingsKey.demoMode) private var demoMode = false
    @State private var path: [HomeRoute] = []
    @State private var showingNewPlan = false

    var body: some View {
        let plan = PlanEngine.activePlan(in: plans, demoMode: demoMode)
        let progress = plan.map { PlanEngine.progress(for: $0, nights: nights) }
        let suggested = suggestedRemedy(for: progress)

        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    if demoMode {
                        DemoBanner()
                    }
                    TonightCard(remedy: suggested, progress: progress) {
                        path.append(.startNight)
                    }
                    if let progress {
                        PlanProgressCard(progress: progress, remedies: remedies) {
                            showingNewPlan = true
                        }
                    } else {
                        noPlanCard
                    }
                    if let lastNight = nights.first {
                        NavigationLink(value: HomeRoute.night(lastNight)) {
                            LastNightCard(night: lastNight)
                        }
                        .buttonStyle(.plain)
                    } else {
                        firstNightCard
                    }
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Tonight")
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .startNight:
                    StartNightView(suggestedRemedyID: suggested?.id) { night in
                        path = [.night(night)]
                    }
                case .night(let night):
                    NightDetailView(night: night)
                }
            }
            .sheet(isPresented: $showingNewPlan) {
                NewPlanSheet()
            }
        }
    }

    private func suggestedRemedy(for progress: PlanProgress?) -> Remedy? {
        if let id = progress?.suggestedRemedyID, let remedy = remedies.first(where: { $0.id == id }) {
            return remedy
        }
        return remedies.first(where: \.isBaseline)
    }

    private var noPlanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Your plan")
            Text("Set up a short experiment: a few nights without any remedy, then a few nights of each remedy you want to test.")
                .foregroundStyle(Theme.secondaryText)
            Button("Set up a plan") { showingNewPlan = true }
                .buttonStyle(.bordered)
        }
        .card()
    }

    private var firstNightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Last night")
            Text("No nights yet")
                .font(.headline)
            Text("Tonight, put your phone by the bed and tap Start night. Your summary will be here in the morning.")
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }
}

private struct TonightCard: View {
    let remedy: Remedy?
    let progress: PlanProgress?
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Tonight's remedy")
            if let remedy {
                HStack(spacing: 14) {
                    Image(systemName: remedy.symbol)
                        .font(.title)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 48, height: 48)
                        .background(Theme.accent.opacity(0.15), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(remedy.name)
                            .font(.title2.bold())
                        Text(caption)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Button(action: onStart) {
                Label("Start night", systemImage: "moon.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            Label("Plug in your phone and put it on the nightstand, close to your head.", systemImage: "powerplug")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }

    private var caption: String {
        guard let progress else { return "Pick any remedy on the next screen" }
        if progress.isComplete { return "Plan complete. Keep testing anything you like" }
        return "Suggested by your plan"
    }
}

private struct PlanProgressCard: View {
    let progress: PlanProgress
    let remedies: [Remedy]
    let onNewPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(text: "Your plan")
                Spacer()
                Text(progressText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            ProgressView(value: Double(progress.completedNights), total: Double(max(progress.totalNights, 1)))
                .tint(Theme.accent)
                .accessibilityLabel("Plan progress")
                .accessibilityValue("\(progress.completedNights) of \(progress.totalNights) nights done")
            VStack(spacing: 10) {
                ForEach(progress.steps) { step in
                    stepRow(step)
                }
            }
            if progress.isComplete {
                Text("Your plan is done. See what worked in Results, or start a new plan.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                Button("Start a new plan", action: onNewPlan)
                    .buttonStyle(.bordered)
            }
        }
        .card()
    }

    private var progressText: String {
        progress.isComplete ? "Complete" : "Night \(progress.currentNight) of \(progress.totalNights)"
    }

    private func stepRow(_ step: PlanStepProgress) -> some View {
        let remedy = remedies.first { $0.id == step.remedyID }
        let done = min(step.completedNights, step.requiredNights)
        let title: String = remedy.map { $0.isBaseline ? "Baseline (no remedy)" : $0.name } ?? "Removed remedy"
        let spokenProgress = step.isComplete ? "Done" : "\(done) of \(step.requiredNights) nights"
        return HStack(spacing: 12) {
            Image(systemName: remedy?.symbol ?? "questionmark")
                .frame(width: 24)
                .foregroundStyle(step.isComplete ? Theme.accent : Theme.secondaryText)
            Text(title)
            Spacer()
            if step.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
            } else {
                Text("\(done)/\(step.requiredNights)")
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityValue(spokenProgress)
    }
}

private struct LastNightCard: View {
    let night: Night

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Last night")
                Spacer()
                Text(Format.nightTitle(night.startDate))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.perHour(night.snoreMinutesPerHour))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text("snore min / hour")
                    .foregroundStyle(Theme.secondaryText)
            }
            if let remedy = night.remedy {
                RemedyBadge(name: remedy.name, symbol: remedy.symbol)
            }
            Text("\(Format.minutes(night.totalSnoreMinutes)) min of snoring · \(night.eventCount) events · \(Format.duration(night.recordedDuration)) recorded")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            NightTags(night: night)
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the details of this night")
    }
}
