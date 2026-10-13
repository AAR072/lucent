import SwiftUI

@main
struct LucentApp: App {
    @StateObject private var camera = CameraModel()
    var body: some Scene {
        WindowGroup {
            CameraView(model: camera)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.96, green: 0.97, blue: 0.24))
        }
    }
}
