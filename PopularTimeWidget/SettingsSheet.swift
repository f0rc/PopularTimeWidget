import SwiftUI
import WebKit
import WidgetKit

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
  @AppStorage(WidgetStorage.liveColorKey, store: WidgetStorage.defaults)
  private var liveColorData = Data()

  private var liveBarColor: Binding<Color> {
    Binding(
      get: { WidgetStorage.liveBarColor(from: liveColorData) },
      set: { color in
        guard let data = try? JSONEncoder().encode(WidgetColor(color)) else { return }
        liveColorData = data
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.kind)
      }
    )
  }

  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
  }

  var body: some View {
    GoogleConnectionSettings()

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
      Divider().padding(.horizontal, 20)
      SettingsRow("Live bar color") {
        ColorPicker("Live bar color", selection: liveBarColor, supportsOpacity: false)
          .labelsHidden()
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
  .environmentObject(GoogleMapsSession())
}

struct GoogleConnectionSettings: View {
  @EnvironmentObject private var session: GoogleMapsSession

  private var connectionLabel: String {
    switch session.connection {
    case .disconnected: return "Not connected"
    case .available: return "Session saved"
    case .verified: return "Connected"
    }
  }

  var body: some View {
    SettingsGroup("Google Maps") {
      SettingsRow("Session", subtitle: "Saved securely on this device") {
        Text(connectionLabel).font(.subheadline)
      }
      Divider().padding(.horizontal, 20)
      Button(action: session.connect) {
        SettingsRow(session.connection == .disconnected ? "Connect Google" : "Reconnect Google") {
          Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
        }
      }
      .buttonStyle(.plain)
      .disabled(session.busy)
      if session.connection != .disconnected {
        Divider().padding(.horizontal, 20)
        Button(role: .destructive, action: session.disconnect) {
          SettingsRow("Disconnect") {
            Image(systemName: "rectangle.portrait.and.arrow.right")
          }
        }
        .buttonStyle(.plain)
        .disabled(session.busy)
      }
    }
    .sheet(isPresented: $session.presented, onDismiss: session.close) {
      GoogleConnectionView()
    }
  }
}

private struct GoogleConnectionView: View {
  @EnvironmentObject private var session: GoogleMapsSession

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Sign in, then save your session.")
            .font(.system(.subheadline, design: .rounded))
          Text(session.status)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)
          ProgressView().controlSize(.small)
            .opacity(session.loading || session.busy ? 1 : 0)
            .frame(height: 16)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)

        MapsBrowser(webView: session.webView)
      }
      .background(GlassPalette.base)
      .safeAreaInset(edge: .bottom) {
        Button("Save session", action: session.useSession)
          .font(.system(.body, design: .rounded, weight: .semibold))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity, minHeight: 50)
          .background(GlassPalette.ink, in: Capsule())
          .buttonStyle(.plain)
          .disabled(session.busy || session.loading)
          .opacity(session.busy || session.loading ? 0.5 : 1)
          .padding(20)
          .background(GlassPalette.base)
      }
      .navigationTitle("Google Maps")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", systemImage: "xmark", action: session.close)
            .labelStyle(.iconOnly)
        }
      }
      .onAppear(perform: session.appeared)
    }
  }
}

private struct MapsBrowser: UIViewRepresentable {
  let webView: WKWebView
  func makeUIView(context: Context) -> WKWebView { webView }
  func updateUIView(_ uiView: WKWebView, context: Context) {}
}
