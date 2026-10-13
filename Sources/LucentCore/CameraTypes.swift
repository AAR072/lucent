import Foundation

public enum CaptureFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case processed, sensorRAW, proRAW
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .processed: return "HEIC / JPEG"
        case .sensorRAW: return "Sensor RAW"
        case .proRAW: return "Apple ProRAW"
        }
    }
}

public enum ExposureMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic, manual, shutterPriority, isoPriority, aperturePriority
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .automatic: return "Auto"
        case .manual: return "Manual"
        case .shutterPriority: return "Shutter Priority"
        case .isoPriority: return "ISO Priority"
        case .aperturePriority: return "Aperture priority"
        }
    }
}

public enum FlashMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case off, on, auto
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum CameraTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case standard, mono, minimal
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum FilmSetting: String, CaseIterable, Codable, Identifiable, Sendable {
    case `default`, on, off
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum LocationMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case off, coarse, fine
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum AspectRatio: String, CaseIterable, Codable, Identifiable, Sendable {
    case native, classic, square, wide, panorama, insta
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .native: return "4:3"
        case .classic: return "3:2"
        case .square: return "1:1"
        case .wide: return "16:9"
        case .panorama: return "65:24"
        case .insta: return "4:5"
        }
    }
    public var landscapeRatio: Double {
        switch self {
        case .native: return 4 / 3
        case .classic: return 3 / 2
        case .square: return 1
        case .wide: return 16 / 9
        case .panorama: return 65 / 24
        case .insta: return 1.91
        }
    }
    public var portraitRatio: Double { self == .insta ? 4 / 5 : 1 / landscapeRatio }
    /// Center crop in source coordinates. Keeps orientation and never extends outside the image.
    public func crop(width: Double, height: Double) -> CropRect {
        guard width > 0, height > 0, width.isFinite, height.isFinite else {
            return CropRect(x: 0, y: 0, width: 0, height: 0)
        }
        let ratio = width >= height ? landscapeRatio : portraitRatio
        let w = min(width, height * ratio)
        let h = min(height, width / ratio)
        return CropRect(x: (width - w) / 2, y: (height - h) / 2, width: w, height: h)
    }
}

public struct CropRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

public enum LevelMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case off, on, auto
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum GoldenCorner: String, CaseIterable, Codable, Identifiable, Sendable {
    case topLeft, bottomLeft, bottomRight, topRight
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .topRight: return "Top Right"
        }
    }
}

public enum GridStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case none, thirds, golden, uniform, rabatment
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: return "Off"
        case .golden: return "Golden Ratio"
        case .uniform: return "Grid"
        default: return rawValue.capitalized
        }
    }
    public var divisions: [Double] {
        switch self {
        case .none, .rabatment: return []
        case .thirds: return [1 / 3, 2 / 3]
        case .golden: return [0.38196601125, 0.61803398875]
        case .uniform: return [0.25, 0.5, 0.75]
        }
    }
}

public enum Look: String, CaseIterable, Codable, Identifiable, Sendable {
    case neutral, ember, verdant, silver, charcoal
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var detail: String {
        switch self {
        case .neutral: return "Natural color, a quiet tone curve."
        case .ember: return "Warm highlights with open shadows."
        case .verdant: return "Rich color and defined midtones."
        case .silver: return "Muted color, crisp contrast."
        case .charcoal: return "Monochrome with a soft shoulder."
        }
    }
}

public struct DevelopmentSettings: Codable, Equatable, Sendable {
    public var look: Look = .neutral
    public var exposure: Double = 0
    public var temperature: Double = 6500
    public var tint: Double = 0
    public var useCustomWhiteBalance = false
    public var aspect: AspectRatio = .native
    public var rotationDegrees: Double = 0
    public var grain: Double = 0
    public var halation: Double = 0
    public var vignette: Double = 0
    public var microcontrast: Double = 0
    public var maxLongEdge: Int = 0
    /// Optional for compatibility with saved recipes from the first development build.
    public var minimalRAWProcessing: Bool?
    public var sensorCrop: Double?
    public var compressionQuality: Double?
    public var hdr: Bool?
    public var filmSetting: FilmSetting?
    public var grainSetting: FilmSetting?
    public var halationSetting: FilmSetting?
    public var mtfSetting: FilmSetting?
    public var vignetteSetting: FilmSetting?
    public init() {}
}

public struct CaptureCapabilities: Sendable {
    public var sensorRAW: Bool
    public var proRAW: Bool
    public var flash: Bool
    public init(sensorRAW: Bool, proRAW: Bool, flash: Bool) {
        self.sensorRAW = sensorRAW; self.proRAW = proRAW; self.flash = flash
    }
}

public enum CapturePlanError: Error, LocalizedError, Equatable {
    case unsupportedSensorRAW, unsupportedProRAW
    public var errorDescription: String? {
        switch self {
        case .unsupportedSensorRAW: return "This camera does not expose sensor RAW. Select another lens or HEIC / JPEG."
        case .unsupportedProRAW: return "Apple ProRAW is unavailable on this camera."
        }
    }
}

public struct CapturePlan: Sendable {
    public let format: CaptureFormat
    public let retainNegative: Bool
    public let flash: Bool
    public init(format: CaptureFormat, retainNegative: Bool, flash: Bool,
                capabilities: CaptureCapabilities) throws {
        if format == .sensorRAW && !capabilities.sensorRAW { throw CapturePlanError.unsupportedSensorRAW }
        if format == .proRAW && !capabilities.proRAW { throw CapturePlanError.unsupportedProRAW }
        self.format = format
        self.retainNegative = retainNegative && format != .processed
        self.flash = flash && capabilities.flash
    }
}
