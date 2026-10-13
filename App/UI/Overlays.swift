import SwiftUI
import LucentCore

struct CompositionGrid: View {
    let style: GridStyle
    var corner: GoldenCorner = .topLeft
    var body: some View {
        Canvas { context, size in
            var path = Path()
            if style == .golden {
                let flipX = corner == .topRight || corner == .bottomRight
                let flipY = corner == .bottomLeft || corner == .bottomRight
                func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                    CGPoint(x: (flipX ? 1 - x : x) * size.width, y: (flipY ? 1 - y : y) * size.height)
                }
                func segment(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
                    path.move(to: point(x1, y1)); path.addLine(to: point(x2, y2))
                }
                let small: CGFloat = 0.38196601125, large: CGFloat = 1 - small
                segment(0, small, 1, small); segment(small, 0, small, small)
                var rect = CGRect(x: 0, y: 0, width: small, height: small)
                for step in 0..<8 {
                    switch step % 4 {
                    case 0:
                        let y = rect.minY + rect.height * large
                        segment(rect.minX, y, rect.maxX, y)
                        rect = CGRect(x: rect.minX, y: y, width: rect.width, height: rect.maxY - y)
                    case 1:
                        let x = rect.minX + rect.width * large
                        segment(x, rect.minY, x, rect.maxY)
                        rect = CGRect(x: x, y: rect.minY, width: rect.maxX - x, height: rect.height)
                    case 2:
                        let y = rect.minY + rect.height * large
                        segment(rect.minX, y, rect.maxX, y)
                        rect.size.height = y - rect.minY
                    default:
                        let x = rect.minX + rect.width * large
                        segment(x, rect.minY, x, rect.maxY)
                        rect.size.width = x - rect.minX
                    }
                }
            } else if style == .rabatment {
                if size.height > size.width {
                    for y in [size.width, size.height - size.width] {
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                } else {
                    for x in [size.height, size.width - size.height] {
                        path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                    }
                }
            } else {
                for fraction in style.divisions {
                    path.move(to: CGPoint(x: size.width * fraction, y: 0)); path.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                    path.move(to: CGPoint(x: 0, y: size.height * fraction)); path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                }
            }
            context.stroke(path, with: .color(.white.opacity(0.65)), lineWidth: 0.5)
        }
    }
}

struct HistogramView: View {
    let bins: [Int]
    var body: some View {
        Canvas { context, size in
            guard let maximum = bins.max(), maximum > 0 else { return }
            var path = Path(); path.move(to: CGPoint(x: 0, y: size.height))
            for (i, bin) in bins.enumerated() {
                path.addLine(to: CGPoint(x: CGFloat(i) / CGFloat(max(1, bins.count - 1)) * size.width,
                                        y: size.height - CGFloat(bin) / CGFloat(maximum) * size.height))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height)); path.closeSubpath()
            context.fill(path, with: .color(.white.opacity(0.65)))
        }.padding(5).background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 5))
            .accessibilityLabel("Preview luminance histogram")
    }
}

struct AnalysisOverlay: View {
    let analysis: FrameAnalysis?
    let peaking: Bool
    let zebras: Bool
    var body: some View {
        Canvas { context, size in
            guard let analysis, peaking || zebras else { return }
            let w = size.width / CGFloat(analysis.width), h = size.height / CGFloat(analysis.height)
            var edgePath = Path()
            var zebraPaths = Array(repeating: Path(), count: 8)
            for y in 0..<analysis.height {
                for x in 0..<analysis.width {
                    let i = y * analysis.width + x
                    let rect = CGRect(x: CGFloat(x) * w, y: CGFloat(y) * h, width: w, height: h)
                    if peaking && analysis.edges[i] { edgePath.addRect(rect) }
                    if zebras && analysis.highlights[i] && (x + y) % 7 < 3 {
                        zebraPaths[Int(analysis.highlightChannels[i])].addRect(rect)
                    }
                }
            }
            context.fill(edgePath, with: .color(.mint.opacity(0.8)))
            let colors: [Color] = [.clear, .red, .green, .yellow, .blue, .purple, .cyan, .white]
            for channel in 1...7 { context.fill(zebraPaths[channel], with: .color(colors[channel].opacity(0.85))) }
        }
    }
}

struct LevelView: View {
    let degrees: Double
    var body: some View {
        HStack(spacing: 5) {
            Rectangle().frame(width: 14, height: 1)
            Rectangle().frame(width: 35, height: 1.5).rotationEffect(.degrees(-degrees))
            Rectangle().frame(width: 14, height: 1)
        }.foregroundStyle(abs(degrees) < 1 ? Color.yellow : .white.opacity(0.65))
    }
}
