import SwiftData
import SwiftUI

struct ManageRemediesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Remedy.sortOrder) private var remedies: [Remedy]
    @State private var newName = ""
    @State private var newSymbol = RemedyCatalog.customSymbols[0]
    @State private var pendingDeletion: Remedy?

    private var builtIns: [Remedy] { remedies.filter(\.isBuiltIn) }
    private var custom: [Remedy] { remedies.filter { !$0.isBuiltIn } }

    var body: some View {
        List {
            Section("Built in") {
                ForEach(builtIns) { remedy in
                    row(remedy)
                }
            }
            .listRowBackground(Theme.card)

            Section {
                if custom.isEmpty {
                    Text("Add anything you want to test, like mouth tape or a humidifier.")
                        .foregroundStyle(Theme.secondaryText)
                }
                ForEach(custom) { remedy in
                    row(remedy)
                }
                .onDelete { offsets in
                    pendingDeletion = offsets.first.map { custom[$0] }
                }
            } header: {
                Text("Your remedies")
            } footer: {
                if !custom.isEmpty {
                    Text("Swipe left to delete one of your remedies.")
                }
            }
            .listRowBackground(Theme.card)

            Section("Add a remedy") {
                TextField("Name", text: $newName)
                    .textInputAutocapitalization(.sentences)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(RemedyCatalog.customSymbols, id: \.self) { symbol in
                            symbolButton(symbol)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Button("Add remedy", systemImage: "plus.circle.fill", action: addRemedy)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Remedies")
        .confirmationDialog(
            "Delete \(pendingDeletion?.name ?? "remedy")?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let remedy = pendingDeletion {
                    deleteRemedy(remedy)
                }
            }
        } message: {
            let count = pendingDeletion?.nights.count ?? 0
            Text(count == 0 ? "It hasn't been used yet." : "Its \(Format.nights(count)) will be deleted too.")
        }
    }

    private func row(_ remedy: Remedy) -> some View {
        HStack(spacing: 12) {
            Image(systemName: remedy.symbol)
                .frame(width: 28)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(remedy.name)
            Spacer()
            if remedy.isBaseline {
                Text("Baseline")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func symbolButton(_ symbol: String) -> some View {
        let isSelected = symbol == newSymbol
        return Button {
            newSymbol = symbol
        } label: {
            Image(systemName: symbol)
                .frame(width: 40, height: 40)
                .background(isSelected ? Theme.accent.opacity(0.25) : Color.white.opacity(0.06), in: Circle())
                .foregroundStyle(isSelected ? Theme.accent : .white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func addRemedy() {
        guard RemedyCatalog.addCustom(name: newName, symbol: newSymbol, in: context) != nil else { return }
        try? context.save()
        newName = ""
    }

    private func deleteRemedy(_ remedy: Remedy) {
        ClipStore.delete(remedy.nights.flatMap(\.events).compactMap(\.clipFileName))
        context.delete(remedy)
        try? context.save()
        pendingDeletion = nil
    }
}
