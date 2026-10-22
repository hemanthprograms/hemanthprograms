import SwiftUI

struct RootView: View {
    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false
    @Environment(RecordingService.self) private var recording

    var body: some View {
        @Bindable var recording = recording
        Group {
            if !hasOnboarded {
                OnboardingView()
            } else if recording.isRecording {
                RecordingView()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: recording.isRecording)
        .sheet(item: $recording.completedNight) { night in
            NavigationStack {
                NightDetailView(night: night)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { recording.completedNight = nil }
                        }
                    }
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Tonight", systemImage: "moon.stars") }
            ResultsView()
                .tabItem { Label("Results", systemImage: "chart.bar.xaxis") }
            HistoryView()
                .tabItem { Label("History", systemImage: "calendar") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
