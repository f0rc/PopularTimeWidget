import SwiftUI

struct SettingsSheet<Content: View>: View {
    @Binding var isPresented: Bool
    private let content: Content

    init(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) {
        _isPresented = isPresented
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                content
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.body, design: .rounded))
        .foregroundStyle(GlassPalette.ink)
        .background(GlassPalette.base.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 18) {
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(GlassPalette.heading)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close settings")

                Text("Settings")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(GlassPalette.heading)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .background(GlassPalette.base)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(32)
        .presentationBackground(GlassPalette.base)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(GlassPalette.heading)
                .padding(.horizontal, 6)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                content
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 26))
            .shadow(color: .black.opacity(0.025), radius: 14, y: 6)
        }
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    private let accessory: Accessory

    init(_ title: String, subtitle: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(GlassPalette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            accessory
                .foregroundStyle(.secondary)
        }
        .font(.system(.body, design: .rounded))
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(minHeight: 64)
    }
}

struct AppSettingsContent: View {
    let locationCount: Int

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        SettingsGroup("App data") {
            SettingsRow("Saved locations") {
                Text(locationCount, format: .number)
                    .monospacedDigit()
            }
            Divider().padding(.horizontal, 20)
            SettingsRow("Storage") {
                Text("On this device")
            }
        }

        SettingsGroup("Appearance") {
            SettingsRow("Theme") {
                Label("Light", systemImage: "sun.max.fill")
            }
        }

        SettingsGroup("About") {
            SettingsRow("Version") {
                Text(version)
            }
        }
    }
}

#Preview {
    SettingsSheet(isPresented: .constant(true)) {
        AppSettingsContent(locationCount: 3)
    }
}
