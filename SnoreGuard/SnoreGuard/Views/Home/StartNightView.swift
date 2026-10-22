import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Pick tonight's remedy and start listening, or run the detector on an audio file.
struct StartNightView: View {
    let suggestedRemedyID: UUID?
    let onFileAnalyzed: (Night) -> Void

    @Environment(\.modelContext) private var context
    @Environment(RecordingService.self) private var recording
    @Environment(\.openURL) private var openURL
    @Query(sort: \Remedy.sortOrder) private var remedies: [Remedy]
    @AppStorage(SettingsKey.sensitivity) private var sensitivity: Sensitivity = .normal
    @AppStorage(SettingsKey.saveClips) private var saveClips = false
    @State private var selectedID: UUID?
    @State private var showingImporter = false
    @State private var errorMessage: String?
    @State private var showingMicrophoneDenied = false

    private var selectedRemedy: Remedy? {
        let id = selectedID ?? suggestedRemedyID
        return remedies.first { $0.id == id } ?? remedies.first(where: \.isBaseline)
    }

    var body: some View {
        List {
            Section {
                ForEach(remedies) { remedy in
                    remedyRow(remedy)
                }
            } header: {
                Text("One remedy per night")
            } footer: {
                if let suggested = remedies.first(where: { $0.id == suggestedRemedyID }) {
                    Text("Your plan suggests \(suggested.name) tonight.")
                }
            }
            .listRowBackground(Theme.card)

            Section("Before you sleep") {
                Label("Plug in your phone. Listening all night uses a lot of battery.", systemImage: "powerplug")
                Label("Put it on the nightstand, screen up, close to your head.", systemImage: "iphone")
                Label("Audio is analyzed on this iPhone and never uploaded.", systemImage: "lock")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryText)
            .listRowBackground(Theme.card)

            Section {
                Button("Analyze sample recording", systemImage: "waveform") {
                    if let url = Bundle.main.url(forResource: "SampleSnoring", withExtension: "m4a") {
                        analyzeFile(at: url, securityScoped: false)
                    }
                }
                Button("Import an audio file…", systemImage: "square.and.arrow.down") {
                    showingImporter = true
                }
            } header: {
                Text("Try it without sleeping")
            } footer: {
                Text("Runs the same detection on a recording instead of the microphone. Handy in the Simulator. Recordings under 30 minutes are saved but don't count toward results.")
            }
            .listRowBackground(Theme.card)
            .disabled(recording.isAnalyzingFile)
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Start night")
        .safeAreaInset(edge: .bottom) {
            Button(action: startNight) {
                Label("Start listening", systemImage: "moon.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selectedRemedy == nil || recording.isAnalyzingFile)
            .padding()
            .background(Theme.background.opacity(0.95))
        }
        .overlay {
            if recording.isAnalyzingFile {
                ProgressView("Analyzing recording…")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url):
                analyzeFile(at: url, securityScoped: true)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("Couldn't start", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Microphone access is off", isPresented: $showingMicrophoneDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("SnoreGuard needs the microphone to listen for snoring. Audio never leaves your phone.")
        }
    }

    private func remedyRow(_ remedy: Remedy) -> some View {
        let isSelected = remedy.id == selectedRemedy?.id
        return Button {
            selectedID = remedy.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: remedy.symbol)
                    .frame(width: 28)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(remedy.name)
                        .foregroundStyle(.white)
                    if remedy.isBaseline {
                        Text("Baseline night")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func startNight() {
        guard let remedy = selectedRemedy else { return }
        Task {
            guard await MicrophonePermission.request() else {
                showingMicrophoneDenied = true
                return
            }
            do {
                try recording.startNight(remedy: remedy, sensitivity: sensitivity, saveClips: saveClips, context: context)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func analyzeFile(at url: URL, securityScoped: Bool) {
        guard let remedy = selectedRemedy else { return }
        Task {
            let isAccessing = securityScoped && url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let night = try await recording.analyzeFile(at: url, remedy: remedy, sensitivity: sensitivity, context: context)
                onFileAnalyzed(night)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
