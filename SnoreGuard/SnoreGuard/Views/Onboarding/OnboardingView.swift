import SwiftData
import SwiftUI

struct OnboardingView: View {
    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false
    @Environment(\.modelContext) private var context
    @State private var page = 0
    @State private var selectedIDs: [UUID] = []

    private let lastPage = 2

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                WelcomePage().tag(0)
                MicrophonePage().tag(1)
                PickRemediesPage(selectedIDs: $selectedIDs).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))

            Button(page < lastPage ? "Continue" : "Start my plan") {
                if page < lastPage {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(page == lastPage && selectedIDs.isEmpty)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .screenBackground()
    }

    private func finish() {
        PlanEngine.createPlan(
            testing: selectedIDs,
            baselineID: RemedyCatalog.remedy(withKey: RemedyCatalog.baselineKey, in: context)?.id,
            in: context
        )
        try? context.save()
        hasOnboarded = true
    }
}

private struct OnboardingPage<Content: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
            .padding(24)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
    }
}

private struct WelcomePage: View {
    var body: some View {
        OnboardingPage(symbol: "moon.stars", title: "Find the remedy that actually works") {
            VStack(alignment: .leading, spacing: 18) {
                step("checklist", "Pick one remedy each night, or none for a baseline night.")
                step("iphone.radiowaves.left.and.right", "Leave your phone by the bed. SnoreGuard listens for snoring on the phone itself.")
                step("chart.bar.xaxis", "After a few nights, see honestly whether any remedy helped.")
            }
            Label(Disclaimer.text, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .card()
        }
    }

    private func step(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .frame(width: 28)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MicrophonePage: View {
    @Environment(\.openURL) private var openURL
    @State private var isGranted = MicrophonePermission.isGranted
    @State private var isDenied = MicrophonePermission.isDenied

    var body: some View {
        OnboardingPage(symbol: "mic", title: "SnoreGuard needs the microphone") {
            Text("It listens for snoring while you sleep. Sound is analyzed on your iPhone and never uploaded. Raw audio isn't saved unless you turn on snore clips in Settings.")
                .foregroundStyle(Theme.secondaryText)
            if isGranted {
                Label("Microphone access is on", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
            } else if isDenied {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Microphone access is off. You can turn it on in the Settings app.")
                        .foregroundStyle(Theme.secondaryText)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            } else {
                Button("Allow microphone") {
                    Task {
                        isGranted = await MicrophonePermission.request()
                        isDenied = !isGranted
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct PickRemediesPage: View {
    @Binding var selectedIDs: [UUID]

    var body: some View {
        OnboardingPage(symbol: "list.bullet.clipboard", title: "What do you want to test?") {
            Text("Pick up to \(PlanEngine.maxRemedies). Your plan starts with \(PlanEngine.nightsPerStep) nights without any remedy, then \(PlanEngine.nightsPerStep) nights of each.")
                .foregroundStyle(Theme.secondaryText)
            RemedySelectionList(selectedIDs: $selectedIDs)
        }
    }
}
