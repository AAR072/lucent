import SwiftUI

struct AppIconChoice: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    var name: String? { id == "Titanium" ? nil : "Icon" + id }
    static let choices: [Self] = [
        .init(id: "Titanium", title: "Titanium", subtitle: "Fire away."),
        .init(id: "Silver", title: "Silver", subtitle: "A lighter touch."),
        .init(id: "SpaceGrey", title: "Space Grey", subtitle: "After dark."),
        .init(id: "Monochrom", title: "Monochrom", subtitle: "Light and shadow."),
        .init(id: "Pride2022", title: "Pride 2022", subtitle: "Every color belongs."),
        .init(id: "Pride2021", title: "Pride 2021", subtitle: "Show your colors."),
        .init(id: "Aperture", title: "Aperture", subtitle: "Let the light in."),
        .init(id: "MarkI", title: "Mark I", subtitle: "Back to the beginning.")
    ]
}

struct AppIconPicker: View {
    @State private var selection = AppIconChoice.choices.firstIndex { $0.name == UIApplication.shared.alternateIconName } ?? 0
    @State private var changing = false
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                ForEach(Array(AppIconChoice.choices.enumerated()), id: \.element.id) { index, icon in
                    VStack(spacing: 0) {
                        Image("IconPreview" + icon.id).resizable().frame(width: 200, height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 43, style: .continuous))
                            .shadow(color: .black.opacity(0.5), radius: 18, y: 15).padding(.top, 32)
                        Text(icon.title.uppercased()).font(.system(size: 30, weight: .medium, design: .rounded)).tracking(3)
                            .frame(height: 38).padding(.top, 43)
                        Text(icon.subtitle).font(.system(size: 17)).foregroundStyle(.gray).padding(.top, 13)
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity).tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 362).accessibilityIdentifier("iconCarousel")
            HStack(spacing: 10) {
                ForEach(AppIconChoice.choices.indices, id: \.self) { index in
                    Button { withAnimation { selection = index } } label: { Circle().fill(selection == index ? .white : .gray).frame(width: 8, height: 8) }
                        .accessibilityLabel(AppIconChoice.choices[index].title + " icon").accessibilityAddTraits(selection == index ? .isSelected : [])
                }
            }.frame(height: 8).padding(.top, 5).padding(.bottom, 40)
            Button {
                changing = true
                UIApplication.shared.setAlternateIconName(AppIconChoice.choices[selection].name) { failure in
                    DispatchQueue.main.async { changing = false; error = failure?.localizedDescription }
                }
            } label: {
                Text("Set Icon").font(.system(size: 19, weight: .bold)).foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 55)
                    .background(LinearGradient(colors: [Color(white: 0.94), Color(white: 0.8)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.9), lineWidth: 1))
            }.buttonStyle(.plain).disabled(changing).accessibilityIdentifier("setAppIcon")
                .padding(.horizontal, 15.5).padding(.bottom, 24)
        }.background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 24))
            .alert("Couldn’t change the icon", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
}
