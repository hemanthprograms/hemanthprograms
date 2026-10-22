import SwiftData
import SwiftUI

/// Pick up to `limit` remedies to test, with a field to add your own.
struct RemedySelectionList: View {
    @Binding var selectedIDs: [UUID]
    var limit = PlanEngine.maxRemedies

    @Environment(\.modelContext) private var context
    @Query(sort: \Remedy.sortOrder) private var remedies: [Remedy]
    @State private var customName = ""

    private var candidates: [Remedy] { remedies.filter { !$0.isBaseline } }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(candidates) { remedy in
                row(for: remedy)
            }
            HStack(spacing: 10) {
                TextField("Add your own (e.g. mouth tape)", text: $customName)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .onSubmit(addCustom)
                Button("Add", action: addCustom)
                    .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func row(for remedy: Remedy) -> some View {
        let isSelected = selectedIDs.contains(remedy.id)
        let isFull = selectedIDs.count >= limit
        return Button {
            toggle(remedy)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: remedy.symbol)
                    .frame(width: 28)
                    .foregroundStyle(Theme.accent)
                Text(remedy.name)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryText)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : Theme.cardBorder, lineWidth: isSelected ? 1.5 : 1)
            )
            .opacity(!isSelected && isFull ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!isSelected && isFull)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle(_ remedy: Remedy) {
        if let index = selectedIDs.firstIndex(of: remedy.id) {
            selectedIDs.remove(at: index)
        } else if selectedIDs.count < limit {
            selectedIDs.append(remedy.id)
        }
    }

    private func addCustom() {
        guard let remedy = RemedyCatalog.addCustom(name: customName, symbol: "sparkles", in: context) else { return }
        try? context.save()
        customName = ""
        if selectedIDs.count < limit {
            selectedIDs.append(remedy.id)
        }
    }
}

/// Replaces the current plan with a new one (from Settings or a finished plan).
struct NewPlanSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: [UUID] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pick up to \(PlanEngine.maxRemedies) remedies. The plan starts with \(PlanEngine.nightsPerStep) nights without any remedy, then \(PlanEngine.nightsPerStep) nights of each.")
                        .foregroundStyle(Theme.secondaryText)
                    RemedySelectionList(selectedIDs: $selectedIDs)
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("New plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        PlanEngine.createPlan(
                            testing: selectedIDs,
                            baselineID: RemedyCatalog.remedy(withKey: RemedyCatalog.baselineKey, in: context)?.id,
                            in: context
                        )
                        try? context.save()
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }
}
