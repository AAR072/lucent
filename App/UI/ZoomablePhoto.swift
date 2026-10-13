import SwiftUI
import UIKit

struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage?
    var inspection = false
    var onZoomChanged: ((Bool) -> Void)? = nil
    func makeUIView(context: Context) -> PhotoScrollView { PhotoScrollView() }
    func updateUIView(_ view: PhotoScrollView, context: Context) {
        view.onZoomChanged = onZoomChanged
        view.update(image: image, inspection: inspection)
    }
}

final class PhotoScrollView: UIScrollView, UIScrollViewDelegate {
    let photo = UIImageView()
    private var lastBounds = CGSize.zero
    private var lastInspection = false
    private var zoomed = false
    var onZoomChanged: ((Bool) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self; backgroundColor = .black
        minimumZoomScale = 1; maximumZoomScale = 20
        panGestureRecognizer.isEnabled = false
        showsVerticalScrollIndicator = false; showsHorizontalScrollIndicator = false
        photo.contentMode = .scaleAspectFit; addSubview(photo)
        photo.preferredImageDynamicRange = .high
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2; addGestureRecognizer(doubleTap)
        accessibilityIdentifier = "photoViewer"
        accessibilityLabel = "Photograph. Swipe to browse, pinch to zoom, double tap to magnify."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(image: UIImage?, inspection: Bool) {
        let changed = photo.image?.size != image?.size
        photo.image = image
        if changed { lastBounds = .zero; lastInspection = false; setNeedsLayout(); layoutIfNeeded() }
        if inspection != lastInspection {
            lastInspection = inspection
            if inspection, let cg = image?.cgImage {
                setZoomScale(min(maximumZoomScale, max(1, CGFloat(cg.width) / max(1, photo.bounds.width * UIScreen.main.scale))), animated: true)
            } else { setZoomScale(1, animated: true) }
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if lastBounds != bounds.size, let image = photo.image, bounds.width > 0, bounds.height > 0 {
            lastBounds = bounds.size; zoomScale = 1
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            photo.frame = CGRect(origin: .zero, size: CGSize(width: image.size.width * scale, height: image.size.height * scale))
            contentSize = photo.frame.size
        }
        centerPhoto()
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerPhoto()
        let magnified = zoomScale > 1.01
        panGestureRecognizer.isEnabled = magnified
        if magnified != zoomed { zoomed = magnified; onZoomChanged?(magnified) }
    }
    private func centerPhoto() {
        photo.center = CGPoint(x: max(contentSize.width, bounds.width) / 2, y: max(contentSize.height, bounds.height) / 2)
    }
    @objc private func doubleTapped(_ tap: UITapGestureRecognizer) {
        if zoomScale > 1.01 { setZoomScale(1, animated: true) }
        else {
            let point = tap.location(in: photo), scale: CGFloat = 3
            zoom(to: CGRect(x: point.x - bounds.width / scale / 2, y: point.y - bounds.height / scale / 2,
                            width: bounds.width / scale, height: bounds.height / scale), animated: true)
        }
    }
}

struct ExposureDial: View {
    @Binding var value: Double
    @State private var start: Double?
    var body: some View {
        VStack(spacing: 4) {
            Label(String(format: "%+.1f EV", value), systemImage: "sun.max")
                .font(.system(size: 16, weight: .medium, design: .monospaced))
            Canvas { context, size in
                for tick in -50...50 {
                    let x = size.width / 2 + (Double(tick) / 10 - value) * 55
                    guard x >= 0, x <= size.width else { continue }
                    let height: CGFloat = tick % 10 == 0 ? 24 : 14
                    let rect = CGRect(x: x - 1, y: (size.height - height) / 2, width: 2, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.white.opacity(tick % 10 == 0 ? 0.65 : 0.25)))
                }
                context.fill(Path(roundedRect: CGRect(x: size.width / 2 - 1.5, y: 3, width: 3, height: size.height - 6), cornerRadius: 1.5), with: .color(.accentColor))
            }.frame(height: 40).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    if start == nil { start = value }
                    value = min(5, max(-5, (start ?? 0) - Double(drag.translation.width) / 55))
                }.onEnded { _ in start = nil })
                .onTapGesture(count: 2) { value = 0 }
                .accessibilityRepresentation { Slider(value: $value, in: -5...5, step: 0.1).accessibilityLabel("Development exposure") }
        }
    }
}
