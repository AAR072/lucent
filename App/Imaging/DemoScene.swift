import UIKit
import CoreImage

/// A procedurally drawn test scene. No photograph or asset from another app is used.
enum DemoScene {
    static func data() -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1600), format: format)
        return renderer.jpegData(withCompressionQuality: 0.98) { draw in
            let c = draw.cgContext
            let colors = [UIColor(red: 0.15, green: 0.28, blue: 0.37, alpha: 1).cgColor,
                          UIColor(red: 0.73, green: 0.71, blue: 0.57, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            c.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 1150), options: [.drawsAfterEndLocation])
            c.setFillColor(UIColor(red: 0.93, green: 0.86, blue: 0.66, alpha: 1).cgColor)
            c.fillEllipse(in: CGRect(x: 840, y: 330, width: 110, height: 110))
            func ridge(_ points: [CGPoint], color: UIColor) {
                c.setFillColor(color.cgColor); c.beginPath(); c.move(to: CGPoint(x: 0, y: 1600))
                for p in points { c.addLine(to: p) }
                c.addLine(to: CGPoint(x: 1200, y: 1600)); c.closePath(); c.fillPath()
            }
            ridge([CGPoint(x: 0, y: 960), CGPoint(x: 290, y: 490), CGPoint(x: 550, y: 860), CGPoint(x: 880, y: 610), CGPoint(x: 1200, y: 1060)],
                  color: UIColor(red: 0.30, green: 0.39, blue: 0.40, alpha: 1))
            ridge([CGPoint(x: 0, y: 1130), CGPoint(x: 430, y: 840), CGPoint(x: 810, y: 1200), CGPoint(x: 1200, y: 890)],
                  color: UIColor(red: 0.15, green: 0.26, blue: 0.25, alpha: 1))
            c.setFillColor(UIColor(red: 0.61, green: 0.57, blue: 0.43, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 1250, width: 1200, height: 350))
            c.setFillColor(UIColor(red: 0.26, green: 0.37, blue: 0.34, alpha: 1).cgColor)
            c.beginPath(); c.move(to: CGPoint(x: 690, y: 1220)); c.addLine(to: CGPoint(x: 560, y: 1600))
            c.addLine(to: CGPoint(x: 760, y: 1600)); c.addLine(to: CGPoint(x: 710, y: 1220)); c.fillPath()
            for index in 0..<9 {
                let x = CGFloat(70 + index * 118)
                let h = CGFloat(80 + (index * 37 % 140))
                c.setStrokeColor(UIColor(red: 0.27, green: 0.32, blue: 0.20, alpha: 1).cgColor)
                c.setLineWidth(4); c.move(to: CGPoint(x: x, y: 1450)); c.addLine(to: CGPoint(x: x + 12, y: 1450 - h)); c.strokePath()
            }
        }
    }
}
