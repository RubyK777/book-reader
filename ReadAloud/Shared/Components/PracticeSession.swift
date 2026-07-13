import SwiftUI

/// Shared scaffold for the ungraded practice sessions (Shadowing, Speaking),
/// which were near-clones. Owns the position counter, the current item's text as
/// a hero card, the Next/Finish button, the done screen, and the advance/finish
/// state machine. Callers inject the two content slots that differ — one under
/// the hero, one above the advance button — and clean up their own audio/
/// recording via `onLeaveCard` (fired on advance, finish, and disappear).
struct PracticeSession<BelowHero: View, AboveNext: View>: View {
    let items: [ReviewItem]
    let title: String
    let doneSystemImage: String
    let doneTitle: String
    var onLeaveCard: () -> Void = {}
    @ViewBuilder var belowHero: (ReviewItem) -> BelowHero
    @ViewBuilder var aboveNext: (ReviewItem) -> AboveNext

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    private var current: ReviewItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let item = current {
                    card(item)
                } else {
                    doneView
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                }
            }
        }
        .onDisappear(perform: onLeaveCard)
    }

    private func card(_ item: ReviewItem) -> some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ProgressCounter(current: index + 1, total: items.count)

            Spacer()

            Text(item.promptText)
                .font(Theme.heroFont)
                .fontDesign(Theme.sentenceDesign)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .learningCard()
                .padding(.horizontal, DesignSystem.Spacing.md)

            belowHero(item)

            Spacer()

            aboveNext(item)

            Button {
                advance()
            } label: {
                Text(index + 1 < items.count ? "Next" : "Finish")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal, DesignSystem.Spacing.screenMargin)
        }
        .padding(DesignSystem.Spacing.lg)
    }

    private var doneView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: doneSystemImage)
                .font(.system(size: DesignSystem.IconSize.hero))
                .foregroundStyle(DesignSystem.accent)
            Text(doneTitle)
                .font(.title3.bold())
            Button { finish() } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, DesignSystem.Spacing.screenMargin)
        }
        .padding(DesignSystem.Spacing.lg)
    }

    private func advance() {
        onLeaveCard()
        if index + 1 < items.count {
            index += 1
        } else {
            index = items.count   // → doneView
        }
    }

    private func finish() {
        onLeaveCard()
        dismiss()
    }
}
