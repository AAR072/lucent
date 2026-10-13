import SwiftUI
import LucentCore

extension CameraTheme {
    var accent: Color { self == .standard ? Color(red: 1, green: 0.85, blue: 0) : .white }
    var usesGlass: Bool { self != .minimal }
}

/// Shared geometry keeps the actual controls and the Customize preview in sync.
struct CameraControlFace: View {
    var theme: CameraTheme
    var selected = false
    var diameter: CGFloat = 46
    var body: some View {
        Circle()
            .fill(theme.usesGlass
                  ? LinearGradient(colors: selected ? [theme.accent.opacity(0.38), theme.accent.opacity(0.28)] : [Color(white: 0.22), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                  : LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom))
            .overlay(Circle().strokeBorder(selected ? theme.accent.opacity(0.3) : .white.opacity(theme.usesGlass ? 0.14 : 0), lineWidth: 0.7))
            .frame(width: diameter, height: diameter)
    }
}

struct CameraShutterFace: View {
    var theme: CameraTheme
    var busy = false
    var diameter: CGFloat = 88
    var body: some View {
        ZStack {
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .gray, .white.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: diameter * 0.025)
            Circle().fill(theme.usesGlass ? LinearGradient(colors: [Color(white: 0.78), Color(white: 0.87)], startPoint: .top, endPoint: .bottom) : LinearGradient(colors: [.white, .white], startPoint: .top, endPoint: .bottom))
                .padding(diameter * 0.075)
                .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1).padding(diameter * 0.075))
            if busy { ProgressView().tint(.black) }
        }.frame(width: diameter, height: diameter).opacity(busy ? 0.5 : 1)
    }
}

struct ThemeCameraPreview: View {
    let theme: CameraTheme
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 10) {
                Text("AF").font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.accent).background(CameraControlFace(theme: theme, selected: true, diameter: 38)).frame(width: 38, height: 46)
                HStack(spacing: 10) {
                    ForEach([".5", "1×", "2", "4"], id: \.self) { title in
                        Text(title).font(.system(size: title == "1×" ? 17 : 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(title == "1×" ? theme.accent : .white)
                            .frame(width: title == "1×" ? 38 : 29, height: 38)
                            .background(CameraControlFace(theme: theme, selected: title == "1×", diameter: title == "1×" ? 38 : 29))
                    }
                }.padding(.horizontal, 7).frame(height: 46).overlay(Capsule().strokeBorder(.white.opacity(theme.usesGlass ? 0.3 : 0), lineWidth: 1))
                Image(systemName: "ellipsis").font(.system(size: 22, weight: .bold)).foregroundStyle(.gray)
                    .frame(width: 46, height: 46).background(CameraControlFace(theme: theme))
            }
            CameraShutterFace(theme: theme, diameter: 55)
        }.frame(maxWidth: .infinity).frame(height: 150).background(.black, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .ignore).accessibilityLabel("\(theme.title) camera theme preview")
    }
}
