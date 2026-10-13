import Foundation

public struct FrameAnalysis: Sendable {
    public let histogram: [Int]
    public let highlights: [Bool]
    /// R, G and B warning bits for preview channel saturation.
    public let highlightChannels: [UInt8]
    public let edges: [Bool]
    public let width: Int
    public let height: Int
    public let clippedFraction: Double

    /// Analysis of an 8-bit preview, not the sensor's RAW dynamic range.
    /// rowBytes is honored so padded CVPixelBuffers do not contaminate the histogram.
    public static func analyzeBGRA(_ bytes: [UInt8], width: Int, height: Int,
                                   rowBytes: Int, highlightThreshold: UInt8 = 235,
                                   edgeThreshold: Int = 42) -> FrameAnalysis? {
        guard width > 0, height > 0, width <= 4096, height <= 4096,
              rowBytes >= width * 4, rowBytes <= Int.max / height,
              bytes.count >= rowBytes * height else { return nil }
        var bins = [Int](repeating: 0, count: 64)
        var luma = [Int](repeating: 0, count: width * height)
        var highlights = [Bool](repeating: false, count: luma.count)
        var highlightChannels = [UInt8](repeating: 0, count: luma.count)
        var edges = highlights
        var clipped = 0
        for y in 0..<height {
            for x in 0..<width {
                let p = y * rowBytes + x * 4
                let value = (54 * Int(bytes[p + 2]) + 183 * Int(bytes[p + 1]) + 19 * Int(bytes[p])) >> 8
                let i = y * width + x
                luma[i] = value
                bins[min(63, value / 4)] += 1
                var channels: UInt8 = 0
                if bytes[p + 2] >= highlightThreshold { channels |= 1 }
                if bytes[p + 1] >= highlightThreshold { channels |= 2 }
                if bytes[p] >= highlightThreshold { channels |= 4 }
                highlightChannels[i] = channels
                highlights[i] = channels != 0
                if highlights[i] { clipped += 1 }
            }
        }
        if width > 2 && height > 2 {
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let i = y * width + x
                    let gx = -luma[i - width - 1] + luma[i - width + 1]
                        - 2 * luma[i - 1] + 2 * luma[i + 1]
                        - luma[i + width - 1] + luma[i + width + 1]
                    let gy = -luma[i - width - 1] - 2 * luma[i - width] - luma[i - width + 1]
                        + luma[i + width - 1] + 2 * luma[i + width] + luma[i + width + 1]
                    edges[i] = abs(gx) + abs(gy) > max(0, edgeThreshold) * 8
                }
            }
        }
        return FrameAnalysis(histogram: bins, highlights: highlights, highlightChannels: highlightChannels, edges: edges,
                             width: width, height: height,
                             clippedFraction: Double(clipped) / Double(luma.count))
    }
}
