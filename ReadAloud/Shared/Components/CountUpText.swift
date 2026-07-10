import SwiftUI

/// A number that rolls up from 0 to `value` when it appears, via the
/// `numericText` content transition. `delay` staggers multiple counters
/// (e.g. summary tally rows). Reduce Motion jumps straight to the value.
struct CountUpText: View {
    let value: Int
    var delay: Double = 0
    var font: Font = .largeTitle.bold()

    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("\(shown)")
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(shown)))
            .task(id: value) {
                guard !reduceMotion else { shown = value; return }
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                withAnimation(.spring(duration: 0.8)) { shown = value }
            }
    }
}
