import SwiftUI

/// A one-shot confetti burst. Bump `trigger` to fire it (e.g. on session
/// completion). Physics is ballistic — each particle launches upward/outward
/// and falls under gravity, spinning and fading in its final half-second. The
/// timeline pauses itself whenever no particles are live, so it costs nothing
/// at rest. Reduce Motion renders nothing. Purely decorative: non-interactive
/// and hidden from VoiceOver. Overlay it *inside* the presented hierarchy you
/// want it above (a fullScreenCover won't render confetti from its presenter).
struct ConfettiView: View {
    let trigger: Int

    @State private var particles: [Particle] = []
    @State private var burstStart = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let gravity: Double = 950   // px/sec²

    private struct Particle: Identifiable {
        let id = UUID()
        let x: Double        // normalized 0…1 launch column
        let vx: Double       // px/sec horizontal drift
        let vy: Double       // px/sec vertical (negative = upward)
        let color: Color
        let size: Double
        let spin: Double     // radians/sec
        let phase: Double    // initial rotation
    }

    var body: some View {
        TimelineView(.animation(paused: particles.isEmpty)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSince(burstStart)
                for p in particles {
                    let px = p.x * size.width + p.vx * t
                    let py = 0.26 * size.height + p.vy * t + 0.5 * Self.gravity * t * t
                    guard py < size.height + 40 else { continue }
                    let fade = t > 1.9 ? max(0, 1 - (t - 1.9) / 0.5) : 1

                    var layer = ctx
                    layer.translateBy(x: px, y: py)
                    layer.rotate(by: .radians(p.phase + p.spin * t))
                    layer.opacity = fade
                    layer.fill(
                        Path(CGRect(x: -p.size / 2, y: -p.size / 2,
                                    width: p.size, height: p.size * 0.5)),
                        with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in fire() }
    }

    private func fire() {
        guard !reduceMotion, trigger > 0 else { return }
        burstStart = Date()
        particles = (0..<90).map { _ in
            Particle(
                x: Double.random(in: 0.15...0.85),
                vx: Double.random(in: -130...130),
                vy: Double.random(in: -560 ... -320),
                color: Palette.celebration.randomElement() ?? Theme.accent,
                size: Double.random(in: 7...12),
                spin: Double.random(in: -6...6),
                phase: Double.random(in: 0...(2 * .pi)))
        }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            particles = []
        }
    }
}
