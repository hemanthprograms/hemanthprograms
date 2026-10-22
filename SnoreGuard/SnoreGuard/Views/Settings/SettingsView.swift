import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var nights: [Night]
    @AppStorage(SettingsKey.saveClips) private var saveClips = false
    @AppStorage(SettingsKey.sensitivity) private var sensitivity: Sensitivity = .normal
    @AppStorage(SettingsKey.demoMode) private var demoMode = false
    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false
    @State private var export: ExportFiles?
    @State private var errorMessage: String?
    @State private var confirmingDeleteAll = false
    @State private var showingNewPlan = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Save snore clips", isOn: $saveClips)
                    Picker("Detection sensitivity", selection: $sensitivity) {
                        ForEach(Sensitivity.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                } header: {
                    Text("Recording")
                } footer: {
                    Text("Clips are off by default. When on, SnoreGuard keeps up to \(DetectionConfig.maxClipsPerNight) clips of \(Int(DetectionConfig.clipDuration)) seconds per night, only on this iPhone. Higher sensitivity catches quieter snoring but may count other sounds too.")
                }
                .listRowBackground(Theme.card)

                Section("Remedies and plan") {
                    NavigationLink("Manage remedies") {
                        ManageRemediesView()
                    }
                    Button("Start a new plan") { showingNewPlan = true }
                }
                .listRowBackground(Theme.card)

                Section {
                    Button("Export all data as CSV", systemImage: "square.and.arrow.up", action: exportData)
                        .disabled(nights.isEmpty)
                    Button("Delete all data", systemImage: "trash", role: .destructive) {
                        confirmingDeleteAll = true
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Everything SnoreGuard records stays on this iPhone. No account, no analytics, no network.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Toggle("Demo mode", isOn: $demoMode)
                } footer: {
                    Text("Fills the app with 12 sample nights so you can explore every screen. Turning it off removes them.")
                }
                .listRowBackground(Theme.card)

                Section("About") {
                    Label(Disclaimer.text, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    LabeledContent("Version", value: Self.appVersion)
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Settings")
            .onChange(of: demoMode) { _, isOn in
                if isOn {
                    DemoData.seed(in: context)
                } else {
                    DemoData.remove(from: context)
                }
            }
            .sheet(item: $export) { files in
                ActivityView(items: files.urls)
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showingNewPlan) {
                NewPlanSheet()
            }
            .confirmationDialog("Delete all data?", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive, action: deleteAllData)
            } message: {
                Text("This removes every night, plan, custom remedy and clip. It can't be undone.")
            }
            .alert("Export failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func exportData() {
        do {
            export = ExportFiles(urls: try CSVExporter.writeExport(nights: nights))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAllData() {
        NightStore.deleteAll(in: context)
        demoMode = false
        hasOnboarded = false
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private struct ExportFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
}
