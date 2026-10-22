import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Night> { $0.isInProgress == false }, sort: \Night.startDate, order: .reverse)
    private var nights: [Night]

    var body: some View {
        NavigationStack {
            Group {
                if nights.isEmpty {
                    ContentUnavailableView {
                        Label("No nights yet", systemImage: "moon.zzz")
                    } description: {
                        Text("Every night you record shows up here. Start your first one from the Tonight tab.")
                    }
                } else {
                    List {
                        ForEach(nights) { night in
                            NavigationLink(value: night) {
                                NightRow(night: night)
                            }
                            .listRowBackground(Theme.card)
                        }
                        .onDelete(perform: delete)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .screenBackground()
            .navigationTitle("History")
            .navigationDestination(for: Night.self) { night in
                NightDetailView(night: night)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let doomed = offsets.map { nights[$0] }
        for night in doomed {
            NightStore.delete(night, in: context)
        }
        try? context.save()
    }
}

private struct NightRow: View {
    let night: Night

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: night.remedy?.symbol ?? "moon.zzz")
                .frame(width: 30)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(Format.nightTitle(night.startDate))
                    .font(.headline)
                Text(night.remedy?.name ?? "No remedy")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                NightTags(night: night)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.perHour(night.snoreMinutesPerHour))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text("min/h")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
