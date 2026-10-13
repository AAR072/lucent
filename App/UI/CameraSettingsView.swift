import SwiftUI
import LucentCore

struct CameraSettingsView: View {
    @ObservedObject var model: CameraModel
    @Environment(\.dismiss) private var dismiss
    @State private var page: Page = .root
    private let cardColor = Color(white: 0.12)
    enum Page: String { case root = "Settings", looks = "Looks", capture = "Capture", customize = "Customize", membership = "Membership", technical = "Technical Readout", support = "Support", about = "About", love = "Do you love Lucent?" }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(page.rawValue.uppercased()).font(.system(size: 24, weight: .medium, design: .monospaced)).tracking(3)
                    .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 68)
                HStack {
                    if page != .root {
                        Button { withAnimation(.easeInOut(duration: 0.18)) { page = .root } } label: {
                            Image(systemName: "chevron.left").font(.system(size: 22, weight: .medium)).frame(width: 44, height: 44)
                                .background(.white.opacity(0.12), in: Circle()).overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 0.5))
                        }.accessibilityLabel("SETTINGS").accessibilityIdentifier("settingsBack")
                    }
                    Spacer()
                    if page == .root {
                        Button { model.changed(); dismiss() } label: {
                            Image(systemName: "checkmark").font(.system(size: 21, weight: .medium)).frame(width: 44, height: 44)
                                .background(.white.opacity(0.12), in: Circle()).overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 0.5))
                        }.accessibilityLabel("Done").accessibilityIdentifier("settingsDone")
                    }
                }.padding(.horizontal, 16)
            }.frame(height: 70)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch page {
                    case .root: root
                    case .capture: capture
                    case .looks: looks
                    case .customize: customize
                    case .technical: technical
                    case .membership: card { Text("Lucent is free and open source.").font(.title3); Text("All camera and editing features are available without a membership.").foregroundStyle(.secondary) }
                    case .support: card { Text("Support").font(.title2.bold()); Text("Share the camera readout when reporting a problem.").foregroundStyle(.secondary); ShareLink(item: readout) { Label("Share Technical Readout", systemImage: "square.and.arrow.up") } }
                    case .about: card { Text("LUCENT").font(.largeTitle.monospaced()); Text("An independently authored camera."); Text("MIT License • 0.1.1").foregroundStyle(.secondary) }
                    case .love: card { Text("Free and open source").font(.title2.bold()); Text("You can share, study, and improve Lucent.").foregroundStyle(.secondary) }
                    }
                }.padding(.horizontal, 18).padding(.top, page == .capture ? 42 : page == .looks ? 0 : page == .customize ? 22 : 12).padding(.bottom, 32)
            }.scrollIndicators(.hidden)
        }.background(Color(white: 0.065)).foregroundStyle(.white).tint(Color(red: 0.96, green: 0.97, blue: 0.24))
            .presentationDetents([.large]).presentationCornerRadius(50).presentationDragIndicator(.hidden)
            .onDisappear { model.changed() }
    }
    private var root: some View {
        Group {
            VStack(spacing: 0) {
                navigationRow(.looks, icon: "camera.filters", subtitle: "Adjust looks and film simulation")
                navigationRow(.capture, icon: "camera.aperture", subtitle: "Adjust image capture settings")
                navigationRow(.customize, icon: "paintpalette", subtitle: "Change how Lucent looks and works")
                navigationRow(.membership, icon: "person.crop.circle", subtitle: "Free and open source")
            }.padding(18).background(cardColor, in: RoundedRectangle(cornerRadius: 24))
            Text("INFO").font(.system(size: 15, weight: .medium)).foregroundStyle(.gray).padding(.top, 12).padding(.leading, 3)
            VStack(spacing: 0) {
                navigationRow(.technical, icon: "info.square.fill", color: .blue)
                navigationRow(.support, icon: "lifepreserver.fill", color: .red)
                navigationRow(.about, icon: "info.circle.fill", color: .gray)
                navigationRow(.love, icon: "heart.fill", color: .pink)
            }.padding(18).background(cardColor, in: RoundedRectangle(cornerRadius: 24))
        }
    }
    private func navigationRow(_ destination: Page, icon: String, subtitle: String? = nil, color: Color = .gray) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.18)) { page = destination } } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 26)).foregroundStyle(color == .gray ? .white.opacity(0.75) : color).frame(width: 31, height: 31)
                VStack(alignment: .leading, spacing: 4) {
                    Text(destination.rawValue).font(.system(size: 18, weight: .medium))
                    if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.gray) }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.gray)
            }.frame(height: subtitle == nil ? 49 : 60).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("settings-\(destination.rawValue)")
    }
    private func card<Content: View>(spacing: CGFloat = 14, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing, content: content).frame(maxWidth: .infinity, alignment: .leading)
            .padding(18).background(cardColor, in: RoundedRectangle(cornerRadius: 24))
    }
    private func cardTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 14) { Image(systemName: icon).font(.system(size: 26)).frame(width: 31); Text(title).font(.system(size: 22, weight: .bold)) }
    }
    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title).font(.system(size: 17)).foregroundStyle(selected ? .white : .gray); Spacer(); if selected { Image(systemName: "checkmark").font(.system(size: 19, weight: .medium)) } }
                .frame(height: 40).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var capture: some View {
        Group {
            card(spacing: 6) {
                cardTitle("Processed Format", icon: "photo.on.rectangle")
                Divider()
                choice("Most Compatible (JPEG)", selected: !model.heic) { model.heic = false }
                Divider()
                choice("Most Efficient (HEIC)", selected: model.heic) { model.heic = true }
            }
            card {
                cardTitle("System Processing", icon: "sparkles")
                Text("Controls the algorithms applied when shooting with the Apple built-in look. Does not apply to Process Zero based looks.\n\nFast settings disable Smart HDR, Deep Fusion, and other heavy processing.").font(.system(size: 17)).foregroundStyle(.gray)
                HStack {
                    VStack { Image(systemName: "hare.fill"); Text("Fastest") }
                    Slider(value: Binding(get: { Double(model.processingPriority) }, set: { model.processingPriority = Int($0.rounded()) }), in: 0...3, step: 1).tint(.white)
                    VStack { Image(systemName: "tortoise.fill"); Text("Smartest") }
                }.foregroundStyle(.gray).font(.system(size: 16)).padding(.top, 8)
            }
            card {
                cardTitle("Compression", icon: "arrow.down.and.line.horizontal.and.arrow.up")
                if let preview = model.preview { Image(uiImage: preview).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)) }
                Stepper(value: Binding(get: { model.recipe.compressionQuality ?? 0.9 }, set: { model.recipe.compressionQuality = $0 }), in: 0.1...1, step: 0.05) {
                    Text("Quality: \(Int(((model.recipe.compressionQuality ?? 0.9) * 100).rounded()))%")
                }.accessibilityIdentifier("compressionQuality")
            }
            card {
                cardTitle("Location Tagging", icon: "location.fill")
                ForEach(LocationMode.allCases) { mode in
                    if mode != .off { Divider() }
                    choice(mode.title, selected: model.locationMode == mode) { model.locationMode = mode; model.changed() }
                }
            }
            card {
                cardTitle("Preferred Max Resolution", icon: "arrow.up.left.and.arrow.down.right")
                Text("Final resolution depends on lens and camera settings.").font(.system(size: 14)).foregroundStyle(.gray)
                choice("12 MP", selected: !model.highResolution) { model.highResolution = false }
                Divider()
                choice("48 MP", selected: model.highResolution) { model.highResolution = true }
            }
            card {
                settingToggle("Prioritize Responsiveness", detail: "When capturing photos quickly, temporarily reduce smart processing to avoid missing shots.", value: $model.prioritizeResponsiveness)
                settingToggle("Lossy ProRAW Compression", detail: "Major file size savings with a slight reduction in quality. Only applies to Apple Look.", value: $model.lossyProRAW)
                settingToggle("Enable RAW-Only Look", detail: "Allow capturing RAWs without any companion processed image. Will often render wrong in other apps. Only use this if you know what you're doing.", value: $model.rawOnly)
            }
            card {
                Toggle("Automatically save to Photos", isOn: $model.saveToPhotos)
                Toggle("Include RAW in Photos exports", isOn: $model.retainNegative)
            }
        }
    }
    private var looks: some View {
        Group {
            card { settingToggle("HDR", detail: "Brighter highlights and deeper shadows", value: Binding(get: { model.recipe.hdr == true }, set: { model.recipe.hdr = $0 })) }
            card {
                cardTitle("Film Simulation", icon: "film")
                Text("Film simulation adjustments do not apply to the Apple system look.").font(.system(size: 14)).foregroundStyle(.gray)
                VStack(spacing: 0) {
                    filmRow("Film", value: $model.recipe.filmSetting)
                    Divider().padding(.horizontal, 18)
                    filmRow("Grain", value: $model.recipe.grainSetting, indent: 12)
                    Divider().padding(.leading, 30).padding(.trailing, 18)
                    filmRow("Halation", value: $model.recipe.halationSetting, indent: 12)
                    Divider().padding(.leading, 30).padding(.trailing, 18)
                    filmRow("MTF", value: $model.recipe.mtfSetting, indent: 12)
                    Divider().padding(.leading, 30).padding(.trailing, 18)
                    filmRow("Vignette", value: $model.recipe.vignetteSetting, indent: 12)
                }.overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1))).padding(.top, 8)
            }
        }
    }
    private func filmRow(_ title: String, value: Binding<FilmSetting?>, indent: CGFloat = 0) -> some View {
        HStack {
            Text(title).font(.system(size: 17, weight: title == "Film" ? .bold : .regular)).foregroundStyle(.gray).padding(.leading, indent)
            Spacer()
            Picker(title, selection: Binding(get: { value.wrappedValue ?? .default }, set: { value.wrappedValue = $0 })) {
                ForEach(FilmSetting.allCases) { setting in Text(setting.title).tag(setting) }
            }.pickerStyle(.menu).tint(.white)
        }.padding(.horizontal, 18).frame(height: 44)
    }
    private var customize: some View {
        Group {
            AppIconPicker()
            card {
                HStack {
                    Text("Theme").font(.system(size: 17)).foregroundStyle(.gray)
                    Spacer()
                    Picker("Theme", selection: $model.theme) {
                        ForEach(CameraTheme.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu).tint(.white).accessibilityIdentifier("themePicker")
                }
                ThemeCameraPreview(theme: model.theme)
            }
        }
    }
    private func settingToggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(title, isOn: value).font(.system(size: 17))
            Text(detail).font(.system(size: 14)).foregroundStyle(.gray).fixedSize(horizontal: false, vertical: true).padding(.trailing, 65)
        }
    }
    private var readout: String {
        "Lucent 0.1.1 (4)\nCamera: \(model.state.selectedLens)\nPreview: \(Int(model.state.framesPerSecond)) fps\nISO: \(Int(model.state.iso))\nShutter: \(shutterLabel(model.state.shutter))\nSensor RAW: \(model.state.capabilities.sensorRAW)\nApple ProRAW: \(model.state.capabilities.proRAW)\nFlash: \(model.state.capabilities.flash)"
    }
    private var technical: some View { card { Text(readout).font(.system(size: 14, design: .monospaced)).textSelection(.enabled); ShareLink(item: readout) { Label("Share", systemImage: "square.and.arrow.up") } } }
}
