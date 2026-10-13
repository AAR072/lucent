import SwiftUI
import LucentCore

struct ManualControls: View {
    @ObservedObject var model: CameraModel
    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Menu {
                    ForEach(ExposureMode.allCases) { mode in
                        Button(mode.title) { model.controls.mode = mode }
                            .disabled(mode == .aperturePriority && model.state.apertureRange.lowerBound == model.state.apertureRange.upperBound)
                    }
                } label: { Label(model.controls.mode.title, systemImage: "chevron.up.chevron.down").font(.system(size: 15, weight: .medium)).frame(height: 44) }
                Spacer()
                Button("Reset") { model.resetControls() }.font(.system(size: 14)).frame(height: 44)
            }
            if model.controls.mode == .manual || model.controls.mode == .isoPriority {
                ControlSlider(title: "ISO", label: "\(Int(model.controls.iso))", value: $model.controls.iso, range: model.state.isoRange, logarithmic: true)
            }
            if model.controls.mode == .manual || model.controls.mode == .shutterPriority {
                ControlSlider(title: "Shutter", label: shutterLabel(model.controls.shutter), value: $model.controls.shutter, range: model.state.shutterRange, logarithmic: true)
            }
            if model.state.apertureRange.lowerBound != model.state.apertureRange.upperBound && (model.controls.mode == .manual || model.controls.mode == .aperturePriority) {
                ControlSlider(title: "Aperture", label: String(format: "ƒ/%.2f", model.controls.aperture), value: $model.controls.aperture, range: model.state.apertureRange)
            }
            if model.controls.mode != .manual {
                ControlSlider(title: "EV", label: String(format: "%+.1f", model.controls.bias), value: $model.controls.bias, range: -3...3)
            }
            HStack {
                Button(model.controls.autofocus ? "AF" : "MF") { model.controls.autofocus.toggle() }
                    .font(.system(size: 14, weight: .semibold, design: .monospaced)).frame(width: 44, height: 44)
                    .disabled(!model.state.manualFocus)
                if model.controls.autofocus {
                    Text("Tap to focus").font(.system(size: 13)).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    Slider(value: $model.controls.focus, in: 0...1).accessibilityLabel("Manual focus position")
                }
                Button { model.showLoupe.toggle() } label: { Image(systemName: "plus.magnifyingglass").font(.system(size: 19)).frame(width: 44, height: 44) }
                    .accessibilityLabel("Focus magnifier")
            }
        }.padding(12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ControlSlider: View {
    let title: String
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var logarithmic = false
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 68, alignment: .leading)
            Slider(value: Binding(get: {
                logarithmic ? logarithmicFraction(value, range: range) : clamp(value, to: range)
            }, set: { value = logarithmic ? logarithmicValue($0, range: range) : $0 }),
                   in: logarithmic ? 0...1 : range).accessibilityLabel(title)
                .disabled(range.lowerBound == range.upperBound)
            Text(label).font(.system(size: 13, design: .monospaced)).frame(width: 66, alignment: .trailing)
        }.frame(minHeight: 40)
    }
}
