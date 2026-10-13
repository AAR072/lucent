import SwiftUI
import LucentCore

struct CompositionMenu: View {
    @ObservedObject var model: CameraModel
    var body: some View {
        Menu {
            Menu("Level") {
                Picker("Level", selection: $model.levelMode) {
                    ForEach(LevelMode.allCases) { mode in Text(mode.title).tag(mode) }
                }.pickerStyle(.inline)
            }
            Menu("Golden Ratio") {
                Picker("Golden Ratio", selection: Binding<GoldenCorner?>(get: {
                    model.grid == .golden ? model.goldenCorner : nil
                }, set: { corner in
                    guard let corner else { return }
                    model.goldenCorner = corner; model.grid = .golden
                })) {
                    ForEach(GoldenCorner.allCases) { corner in Text(corner.title).tag(Optional(corner)) }
                }.pickerStyle(.inline)
            }
            Picker("Grid", selection: $model.grid) {
                ForEach([GridStyle.rabatment, .uniform, .thirds, .none]) { style in Text(style.title).tag(style) }
            }.pickerStyle(.inline)
        } label: {
            Image(systemName: model.grid == .none ? "rectangle" : "square.grid.3x3")
                .frame(width: 46, height: 46)
        }.menuOrder(.fixed).accessibilityLabel("Grid").accessibilityIdentifier("gridMenu")
    }
}
