import SwiftUI
import SwiftData

/// A calm, non-numeric reflection on how your saved words are settling in
/// (UX review §reflection; absorbs the deferred Phase-5 "stats view").
/// Deck maturity as a growth story — Learning → Taking root → Known — from SRS
/// interval length, plus how many you've saved and when the next cards return.
/// Reflection, never a score: no levels, XP, or percentages (DECISIONS #39).
struct ProgressReflectionView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Sentence> { $0.isBookmarked }) private var sentences: [Sentence]
    @Query(filter: #Predicate<Annotation> { !$0.isSuspended }) private var annotations: [Annotation]

    /// One growth stage, from an item's SRS interval length.
    private enum Stage: CaseIterable {
        case learning, takingRoot, known

        var title: String {
            switch self {
            case .learning: "Learning"
            case .takingRoot: "Taking root"
            case .known: "Known"
            }
        }
        var blurb: String {
            switch self {
            case .learning: "Still fresh — you'll keep meeting these."
            case .takingRoot: "Coming back to you across days."
            case .known: "Settled in for the long term."
            }
        }
        var systemImage: String {
            switch self {
            case .learning: "sparkles"
            case .takingRoot: "leaf.fill"
            case .known: "checkmark.seal.fill"
            }
        }
        var tint: Color {
            switch self {
            case .learning: Theme.coral
            case .takingRoot: Theme.marigold
            case .known: Theme.verdigris
            }
        }
    }

    /// Every saved item's current interval, treating a never-reviewed item as 0.
    private var intervals: [Int] {
        var out: [Int] = []
        out.append(contentsOf: sentences.map { $0.srs?.intervalDays ?? 0 })
        out.append(contentsOf: annotations.map { $0.srs?.intervalDays ?? 0 })
        return out
    }

    private var total: Int { intervals.count }

    private func stage(for interval: Int) -> Stage {
        switch SRSEngine.maturity(forInterval: interval) {
        case .known: .known
        case .takingRoot: .takingRoot
        case .learning: .learning
        }
    }

    private func count(_ stage: Stage) -> Int {
        intervals.filter { self.stage(for: $0) == stage }.count
    }

    private var nextDue: Date? {
        var dates: [Date] = []
        dates.append(contentsOf: sentences.compactMap { $0.srs?.dueDate })
        dates.append(contentsOf: annotations.compactMap { $0.srs?.dueDate })
        return dates.filter { $0 > .now }.min()
    }

    var body: some View {
        NavigationStack {
            Group {
                if total == 0 {
                    AnimatedEmptyState(
                        title: "Nothing planted yet",
                        message: "Save a word or bookmark a sentence while you read — your progress grows here.",
                        systemImage: "leaf",
                        tint: Theme.verdigris)
                } else {
                    content
                }
            }
            .navigationTitle("Your progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                hero
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(Array(Stage.allCases.enumerated()), id: \.element) { index, stage in
                        stageRow(stage, delay: 0.15 * Double(index))
                    }
                }
                nextUp
            }
            .padding(DesignSystem.Spacing.md)
        }
    }

    private var hero: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            CountUpText(value: total, font: .largeTitle.bold().monospacedDigit())
            Text(total == 1 ? "word & sentence saved" : "words & sentences saved")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background {
            AnimatedMeshBackground()
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                .overlay(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .stroke(Theme.cardStroke, lineWidth: 1))
        }
    }

    private func stageRow(_ stage: Stage, delay: Double) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: stage.systemImage)
                .font(.title3)
                .foregroundStyle(stage.tint)
                .frame(width: DesignSystem.IconSize.lg)
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.title)
                    .font(.headline)
                Text(stage.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            CountUpText(value: count(stage), delay: delay, font: .title2.bold().monospacedDigit())
                .foregroundStyle(stage.tint)
        }
        .padding(DesignSystem.Spacing.md)
        .background(Palette.soft(stage.tint), in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    @ViewBuilder
    private var nextUp: some View {
        if let nextDue {
            Text("Next review \(nextDue.relativeNamed)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text("All caught up — practice any time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
