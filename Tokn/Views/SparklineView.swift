import SwiftUI

struct SparklineView: View {
    let points: [Double]   // 0–100 percentages, oldest first
    let color: Color

    var body: some View {
        GeometryReader { geo in
            if points.count >= 2 {
                let pts = scaled(to: geo.size)
                ZStack(alignment: .bottom) {
                    fillPath(pts, size: geo.size)
                        .fill(LinearGradient(
                            colors: [color.opacity(0.25), color.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        ))
                    linePath(pts)
                        .stroke(color.opacity(0.7),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    // Scale to a local min–max range so any variation fills the chart height.
    // A flat line (all identical values) renders centered.
    private func scaled(to size: CGSize) -> [CGPoint] {
        guard let lo = points.min(), let hi = points.max() else { return [] }
        let spread  = hi - lo
        // At least 6pp of visible range so tiny movements are still legible
        let padding = max(spread * 0.25, 3)
        let visMin  = max(0,   lo - padding)
        let visMax  = min(100, hi + padding)
        let range   = visMax - visMin

        return points.enumerated().map { i, val in
            let x = CGFloat(i) / CGFloat(points.count - 1) * size.width
            let norm = range > 0 ? (val - visMin) / range : 0.5
            let y    = size.height - CGFloat(norm) * size.height
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        Path { p in
            for (i, pt) in pts.enumerated() {
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
        }
    }

    private func fillPath(_ pts: [CGPoint], size: CGSize) -> Path {
        Path { p in
            guard let first = pts.first, let last = pts.last else { return }
            p.move(to: CGPoint(x: first.x, y: size.height))
            pts.forEach { p.addLine(to: $0) }
            p.addLine(to: CGPoint(x: last.x, y: size.height))
            p.closeSubpath()
        }
    }
}
