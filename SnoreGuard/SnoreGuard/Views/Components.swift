import SwiftUI

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.secondaryText)
    }
}

struct RemedyBadge: View {
    let name: String
    let symbol: String

    var body: some View {
        Label(name, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.accent.opacity(0.15), in: Capsule())
            .foregroundStyle(Theme.accent)
            .accessibilityLabel("Remedy: \(name)")
    }
}

struct EffectPill: View {
    let label: EffectLabel

    var body: some View {
        Text(label.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch label {
        case .likelyHelps: Theme.accent
        case .mightHelp: Theme.accent.opacity(0.8)
        case .seemsWorse: Theme.worse
        case .baseline, .notEnoughData, .noClearEffect: Theme.secondaryText
        }
    }
}

/// A large number with its unit and a caption underneath.
struct StatTile: View {
    let value: String
    let unit: String
    let caption: String
    var spokenValue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text(unit)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(spokenValue ?? "\(value) \(unit)")
    }
}

struct DemoBanner: View {
    var body: some View {
        Label("Showing demo data. Turn off demo mode in Settings.", systemImage: "sparkles")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Small tags shown on night rows ("Too short to count", "Demo").
struct NightTags: View {
    let night: Night

    var body: some View {
        HStack(spacing: 6) {
            if !night.countsTowardResults {
                tag("Too short to count")
            }
            if night.source == .file {
                tag("Audio file")
            }
            if night.wasRecovered {
                tag("Recovered")
            }
            if night.isDemo {
                tag("Demo")
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.08), in: Capsule())
            .foregroundStyle(Theme.secondaryText)
    }
}
