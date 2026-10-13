import CoreLocation
import ImageIO
import LucentCore

struct CaptureLocation: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    var altitude: Double?
    var clLocation: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    var imageProperties: [String: Any] {
        var gps: [String: Any] = [kCGImagePropertyGPSLatitude as String: abs(latitude),
                                kCGImagePropertyGPSLatitudeRef as String: latitude < 0 ? "S" : "N",
                                kCGImagePropertyGPSLongitude as String: abs(longitude),
                                kCGImagePropertyGPSLongitudeRef as String: longitude < 0 ? "W" : "E"]
        if let altitude {
            gps[kCGImagePropertyGPSAltitude as String] = abs(altitude)
            gps[kCGImagePropertyGPSAltitudeRef as String] = altitude < 0 ? 1 : 0
        }
        return [kCGImagePropertyGPSDictionary as String: gps]
    }
}

@MainActor
final class CaptureLocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var mode: LocationMode = .off
    private(set) var current: CaptureLocation?
    override init() { super.init(); manager.delegate = self }
    func update(mode: LocationMode) {
        guard mode != self.mode else { return }
        self.mode = mode; current = nil
        guard mode != .off else { manager.stopUpdatingLocation(); return }
        manager.desiredAccuracy = mode == .fine ? kCLLocationAccuracyBest : kCLLocationAccuracyThreeKilometers
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { beginIfAllowed() }
    }
    func stop() { manager.stopUpdatingLocation(); mode = .off; current = nil }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { beginIfAllowed() }
    private func beginIfAllowed() {
        guard mode != .off else { return }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.startUpdatingLocation() }
        else { current = nil }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard mode != .off, let sample = locations.last, sample.horizontalAccuracy >= 0,
              abs(sample.timestamp.timeIntervalSinceNow) < 120 else { return }
        let c = sample.coordinate
        if mode == .coarse {
            current = CaptureLocation(latitude: (c.latitude * 100).rounded() / 100,
                                      longitude: (c.longitude * 100).rounded() / 100, altitude: nil)
        } else {
            current = CaptureLocation(latitude: c.latitude, longitude: c.longitude,
                                      altitude: sample.verticalAccuracy >= 0 ? sample.altitude : nil)
        }
    }
}
