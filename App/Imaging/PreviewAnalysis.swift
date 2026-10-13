import CoreImage
import UIKit
import LucentCore

enum PreviewAnalysis {
    /// No film development or full-frame UIImage conversion on the live display path.
    static func sample(_ input: CIImage, aspect: AspectRatio, zoom: Double = 1, analyze: Bool, loupe: Bool) -> (analysis: FrameAnalysis?, loupe: UIImage?) {
        let magnification = clamp(zoom, to: 1...5)
        let source = input.cropped(to: CGRect(x: input.extent.midX - input.extent.width / magnification / 2,
                                             y: input.extent.midY - input.extent.height / magnification / 2,
                                             width: input.extent.width / magnification, height: input.extent.height / magnification))
        let crop = aspect.crop(width: source.extent.width, height: source.extent.height)
        let rect = CGRect(x: source.extent.minX + crop.x, y: source.extent.minY + crop.y, width: crop.width, height: crop.height)
        let cropped = source.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        let pipeline = ImagePipeline.shared
        var result: FrameAnalysis?
        if analyze {
            let scaled = pipeline.resized(cropped, longEdge: 192)
            let width = max(1, Int(scaled.extent.width)), height = max(1, Int(scaled.extent.height))
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            bytes.withUnsafeMutableBytes { ptr in
                pipeline.context.render(scaled, toBitmap: ptr.baseAddress!, rowBytes: width * 4,
                                        bounds: CGRect(x: 0, y: 0, width: width, height: height),
                                        format: .BGRA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            }
            result = FrameAnalysis.analyzeBGRA(bytes, width: width, height: height, rowBytes: width * 4)
        }
        let image = loupe ? try? pipeline.uiImage(pipeline.resized(cropped, longEdge: 720)) : nil
        return (result, image)
    }
}
