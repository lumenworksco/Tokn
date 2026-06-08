import SwiftUI

struct SparklineView: View {
    let points: [Double]   // 0–100 percentages, oldest first
    let color: Color

    var body: some View {
        GeometryReader { geo in
            if points.count >= 2 {
                ZStack(alignment: .bottom) {
                    fillPath(in: geo.size).fill(
                        LinearGradient(
                            colors: [color.opacity(0.25), color.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    linePath(in: geo.size)
                        .stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func xPos(_ i: Int, width: CGFloat) -> CGFloat {
        guard points.count > 1 else { return 0 }
        return CGFloat(i) / CGFloat(points.count - 1) * width
    }

    private func yPos(_ val: Double, height: CGFloat) -> CGFloat {
        height - CGFloat(min(val, 100) / 100) * height
    }

    private func linePath(in size: CGSize) -> Path {
        Path { p in
            for (i, val) in points.enumerated() {
                let pt = CGPoint(x: xPos(i, width: size.width), y: yPos(val, height: size.height))
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
        }
    }

    private func fillPath(in size: CGSize) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: size.height))
            for (i, val) in points.enumerated() {
                p.addLine(to: CGPoint(x: xPos(i, width: size.width), y: yPos(val, height: size.height)))
            }
            p.addLine(to: CGPoint(x: size.width, y: size.height))
            p.closeSubpath()
        }
    }
}
