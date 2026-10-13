import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers
import LucentCore

enum ImagingError: LocalizedError {
    case unreadable, renderFailed, encodingFailed
    var errorDescription: String? {
        switch self {
        case .unreadable: return "This image could not be decoded on this device."
        case .renderFailed: return "Image development failed. Your original is still available."
        case .encodingFailed: return "The developed photograph could not be encoded."
        }
    }
}

/// Independently authored recipes built from public Core Image operations.
final class ImagePipeline {
    static let shared = ImagePipeline()
    let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    static func isRAWData(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0, let type = CGImageSourceGetType(source),
              let uniformType = UTType(type as String) else { return false }
        return uniformType.conforms(to: .rawImage)
    }

    func decode(_ data: Data, isRAW: Bool, settings: DevelopmentSettings,
                preview: Bool = false, hdrOutput: Bool = false) throws -> CIImage {
        var image: CIImage
        if isRAW {
            guard Self.isRAWData(data) else { throw ImagingError.unreadable }
            guard let raw = CIRAWFilter(imageData: data, identifierHint: nil) else { throw ImagingError.unreadable }
            raw.exposure = Float(clamp(settings.exposure, to: -5...5))
            raw.extendedDynamicRangeAmount = hdrOutput ? 1 : 0
            // Preserve the decoder's calibrated tone mapping, particularly ProRAW's gain map.
            // Removing it is not a neutral rendering and can clip highlights in SDR output.
            if settings.minimalRAWProcessing == true {
                raw.boostAmount = 0
                raw.boostShadowAmount = 0
                if raw.isLuminanceNoiseReductionSupported { raw.luminanceNoiseReductionAmount = 0 }
                if raw.isColorNoiseReductionSupported { raw.colorNoiseReductionAmount = 0 }
                if raw.isSharpnessSupported { raw.sharpnessAmount = 0 }
                if raw.isContrastSupported { raw.contrastAmount = 0 }
                if raw.isDetailSupported { raw.detailAmount = 0 }
                if raw.isMoireReductionSupported { raw.moireReductionAmount = 0 }
                if raw.responds(to: NSSelectorFromString("isDespeckleSupported")), raw.isDespeckleSupported { raw.despeckleAmount = 0 }
                if raw.isLocalToneMapSupported { raw.localToneMapAmount = 0 }
            }
            if settings.useCustomWhiteBalance {
                raw.neutralTemperature = Float(clamp(settings.temperature, to: 2000...12000))
                raw.neutralTint = Float(clamp(settings.tint, to: -100...100))
            }
            if preview {
                raw.scaleFactor = Float(min(1, 1400 / max(raw.nativeSize.width, raw.nativeSize.height)))
            }
            guard let output = raw.outputImage else { throw ImagingError.unreadable }
            image = output
        } else {
            guard let decoded = CIImage(data: data, options: [.applyOrientationProperty: true, .expandToHDR: hdrOutput]) else { throw ImagingError.unreadable }
            image = decoded
            if preview { image = resized(image, longEdge: 1400) }
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: clamp(settings.exposure, to: -5...5)])
            if settings.useCustomWhiteBalance {
                image = image.applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: clamp(settings.temperature, to: 2000...12000), y: clamp(settings.tint, to: -100...100))
                ])
            }
        }
        return develop(image, settings: settings, preview: preview)
    }

    func develop(_ source: CIImage, settings: DevelopmentSettings, preview: Bool = false) -> CIImage {
        var settings = settings
        if settings.filmSetting == .off {
            settings.grain = 0; settings.halation = 0; settings.microcontrast = 0; settings.vignette = 0
        } else {
            if settings.grainSetting == .off { settings.grain = 0 }
            else if settings.grainSetting == .on || settings.filmSetting == .on { settings.grain = max(0.25, settings.grain) }
            if settings.halationSetting == .off { settings.halation = 0 }
            else if settings.halationSetting == .on || settings.filmSetting == .on { settings.halation = max(0.25, settings.halation) }
            if settings.mtfSetting == .off { settings.microcontrast = 0 }
            else if settings.mtfSetting == .on || settings.filmSetting == .on { settings.microcontrast = max(0.25, settings.microcontrast) }
            if settings.vignetteSetting == .off { settings.vignette = 0 }
            else if settings.vignetteSetting == .on || settings.filmSetting == .on { settings.vignette = max(0.3, settings.vignette) }
        }
        var image = source
        let zoom = clamp(settings.sensorCrop ?? 1, to: 1...5)
        if zoom > 1 {
            let rect = CGRect(x: image.extent.midX - image.extent.width / zoom / 2,
                              y: image.extent.midY - image.extent.height / zoom / 2,
                              width: image.extent.width / zoom, height: image.extent.height / zoom)
            image = image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        }
        switch settings.look {
        case .neutral:
            break
        case .ember:
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.045, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.008, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.95, w: 0),
                "inputBiasVector": CIVector(x: 0.012, y: 0.004, z: 0, w: 0)
            ]).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.94, kCIInputContrastKey: 1.04])
        case .verdant:
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.15, kCIInputContrastKey: 1.10])
        case .silver:
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.48, kCIInputContrastKey: 1.20])
        case .charcoal:
            image = image.applyingFilter("CIColorMonochrome", parameters: [kCIInputColorKey: CIColor(red: 0.74, green: 0.74, blue: 0.74), kCIInputIntensityKey: 1])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.08])
        }
        let extent = image.extent
        if settings.microcontrast > 0 {
            image = image.applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: 2.5, kCIInputIntensityKey: clamp(settings.microcontrast, to: 0...1) * 0.8])
        }
        if settings.halation > 0 {
            // Highlight bloom is an approximation, not a physically calibrated film model.
            image = image.clampedToExtent().applyingFilter("CIBloom", parameters: [
                kCIInputRadiusKey: max(extent.width, extent.height) * 0.003,
                kCIInputIntensityKey: clamp(settings.halation, to: 0...1) * 0.35
            ]).cropped(to: extent)
        }
        if settings.grain > 0 {
            let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
                .cropped(to: extent).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: clamp(settings.grain, to: 0...1) * 0.16)
                ])
            image = noise.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
        }
        if settings.vignette > 0 {
            image = image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: clamp(settings.vignette, to: 0...1), kCIInputRadiusKey: min(extent.width, extent.height) * 0.6])
        }
        if settings.rotationDegrees != 0 {
            let angle = clamp(settings.rotationDegrees, to: -15...15) * .pi / 180
            let transform = CGAffineTransform(translationX: extent.midX, y: extent.midY)
                .rotated(by: angle).translatedBy(x: -extent.midX, y: -extent.midY)
            image = image.transformed(by: transform).cropped(to: extent)
            // Shrink the crop enough to remove transparent corners after straightening.
            let scale = 1 / (cos(abs(angle)) + max(extent.width / extent.height, extent.height / extent.width) * sin(abs(angle)))
            let inset = CGRect(x: extent.midX - extent.width * scale / 2, y: extent.midY - extent.height * scale / 2,
                               width: extent.width * scale, height: extent.height * scale)
            image = image.cropped(to: inset)
        }
        let crop = settings.aspect.crop(width: image.extent.width, height: image.extent.height)
        image = image.cropped(to: CGRect(x: image.extent.minX + crop.x, y: image.extent.minY + crop.y, width: crop.width, height: crop.height))
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        if settings.maxLongEdge > 0 { image = resized(image, longEdge: CGFloat(settings.maxLongEdge)) }
        if preview { image = resized(image, longEdge: 1400) }
        return image
    }

    func resized(_ image: CIImage, longEdge: CGFloat) -> CIImage {
        let edge = max(image.extent.width, image.extent.height)
        guard edge > longEdge, longEdge > 0 else { return image }
        let scale = longEdge / edge
        return image.clampedToExtent().applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
            .cropped(to: image.extent.applying(CGAffineTransform(scaleX: scale, y: scale)))
    }

    func uiImage(_ image: CIImage, hdr: Bool = false) throws -> UIImage {
        if hdr {
            let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
            let cg: CGImage?
            if #available(iOS 26, *) {
                cg = context.createCGImage(image, from: image.extent, format: .RGBAh, colorSpace: space,
                                           deferred: false, calculateHDRStats: true)
            } else { cg = context.createCGImage(image, from: image.extent, format: .RGBAh, colorSpace: space) }
            guard let cg else { throw ImagingError.renderFailed }
            return UIImage(cgImage: cg)
        }
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: colorSpace) else { throw ImagingError.renderFailed }
        return UIImage(cgImage: cg)
    }

    func jpeg(_ image: CIImage, quality: Double = 0.95, hdrImage: CIImage? = nil) throws -> Data {
        var options: [CIImageRepresentationOption: Any] = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: clamp(quality, to: 0.1...1)]
        if let hdrImage {
            if #available(iOS 26, *) { options[.hdrImage] = context.calculateHDRStats(for: hdrImage) ?? hdrImage }
            else { options[.hdrImage] = hdrImage }
        }
        guard let bytes = context.jpegRepresentation(of: image, colorSpace: colorSpace, options: options) else { throw ImagingError.encodingFailed }
        return bytes
    }

    func heic(_ image: CIImage, quality: Double = 0.95, hdrImage: CIImage? = nil) throws -> Data {
        var options: [CIImageRepresentationOption: Any] = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: clamp(quality, to: 0.1...1)]
        if let hdrImage {
            if #available(iOS 26, *) { options[.hdrImage] = context.calculateHDRStats(for: hdrImage) ?? hdrImage }
            else { options[.hdrImage] = hdrImage }
        }
        guard let bytes = context.heifRepresentation(of: image, format: .RGBA8, colorSpace: colorSpace,
                                                     options: options) else { throw ImagingError.encodingFailed }
        return bytes
    }
}
