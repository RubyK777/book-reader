import SwiftUI

/// A soft, always-drifting `MeshGradient` wash (`Palette.meshWash`). The four
/// corners stay pinned to the rect and the edge mid-points slide only along
/// their edge, so the fill never leaves gaps; interior control points drift on
/// incommensurate sine frequencies so the motion never visibly loops. Reduce
/// Motion or `isStatic` renders one still mesh. Use at most one *animated*
/// instance per screen (the Review hero).
struct AnimatedMeshBackground: View {
    var isStatic = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let colors = Palette.meshWash

    var body: some View {
        if isStatic || reduceMotion {
            MeshGradient(width: 3, height: 3, points: points(at: 0), colors: colors)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                MeshGradient(width: 3, height: 3, points: points(at: t), colors: colors)
            }
        }
    }

    /// 9 control points. Corners fixed; edge mid-points drift along their edge;
    /// the center drifts freely. Frequencies are mutually incommensurate.
    private func points(at t: Double) -> [SIMD2<Float>] {
        func s(_ freq: Double, _ amp: Double) -> Float { Float(sin(t * freq) * amp) }
        return [
            SIMD2(0, 0),
            SIMD2(0.5 + s(0.23, 0.10), 0),
            SIMD2(1, 0),
            SIMD2(0, 0.5 + s(0.19, 0.10)),
            SIMD2(0.5 + s(0.17, 0.12), 0.5 + s(0.13, 0.12)),
            SIMD2(1, 0.5 + s(0.29, 0.10)),
            SIMD2(0, 1),
            SIMD2(0.5 + s(0.25, 0.10), 1),
            SIMD2(1, 1),
        ]
    }
}
