import SwiftUI

/// Core screen (PROJECT_PLAN.md §4.3): tappable sentence cards,
/// active card tinted with word-level highlight, playback bar below.
struct ReaderView: View {
    let sentences: [String]
    let languageCode: String

    @State private var player = SpeechPlayer()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(sentences.enumerated()), id: \.offset) { index, sentence in
                            SentenceCard(
                                text: sentence,
                                isActive: player.currentSentenceIndex == index,
                                highlightRange: player.currentSentenceIndex == index ? player.highlightRange : nil
                            )
                            .id(index)
                            .onTapGesture { player.play(at: index) }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: player.currentSentenceIndex) {
                    guard let index = player.currentSentenceIndex else { return }
                    withAnimation { proxy.scrollTo(index, anchor: .center) }
                }
            }

            playbackBar
        }
        .navigationTitle("Reader")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { player.load(sentences: sentences, languageCode: languageCode) }
        .onDisappear { player.stop() }
    }

    private var playbackBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 44) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                }
                .disabled((player.currentSentenceIndex ?? 0) == 0)

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isSpeaking ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                }

                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                }
                .disabled(player.currentSentenceIndex.map { $0 + 1 >= sentences.count } ?? false)
            }
            .font(.title2)

            HStack {
                Toggle(isOn: $player.repeatMode) {
                    Image(systemName: "repeat")
                }
                .toggleStyle(.button)

                Spacer()

                Picker("Speed", selection: $player.speedMultiplier) {
                    ForEach([0.5, 0.65, 0.75, 0.9, 1.0], id: \.self) { speed in
                        Text("\(speed, specifier: "%.2g")×").tag(Float(speed))
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

private struct SentenceCard: View {
    let text: String
    let isActive: Bool
    let highlightRange: NSRange?

    var body: some View {
        Text(attributedText)
            .font(.title3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isActive ? Color.accentColor.opacity(0.14) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isActive ? Color.accentColor : .clear, lineWidth: 2)
            )
            .scaleEffect(isActive ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isActive)
    }

    private var attributedText: AttributedString {
        var attributed = AttributedString(text)
        if let nsRange = highlightRange, let range = Range(nsRange, in: attributed) {
            attributed[range].backgroundColor = .yellow.opacity(0.6)
            attributed[range].font = .title3.bold()
        }
        return attributed
    }
}

#Preview {
    NavigationStack {
        ReaderView(
            sentences: [
                "Le petit prince vivait sur une planète à peine plus grande qu'une maison.",
                "Il regardait le coucher du soleil chaque soir.",
                "Un jour, il décida de partir en voyage.",
            ],
            languageCode: "fr-FR"
        )
    }
}
