import SwiftUI
import UIKit

struct ContentView: View {
  @StateObject private var locationStore = LocationStore()
  @State private var selectedTab = 0
  @State private var keyboardVisible = false
  @State private var tabBarHeight: CGFloat = 70

  var body: some View {
    TabView(selection: $selectedTab) {
      Tab("List", systemImage: "list.bullet", value: 0) {
        ListView(
          locations: $locationStore.locations,
          bottomContentInset: keyboardVisible ? 0 : tabBarHeight,
          onAdd: { selectedTab = 1 }
        )
        .toolbar(.hidden, for: .tabBar)
      }
      Tab("Map", systemImage: "map", value: 1) {
        MapView(
          locations: $locationStore.locations,
          bottomContentInset: keyboardVisible ? 0 : tabBarHeight
        )
        .toolbar(.hidden, for: .tabBar)
      }
    }
    .overlay(alignment: .bottom) {
      if !keyboardVisible {
        tabBar
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification))
    { _ in
      keyboardVisible = true
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) {
      _ in
      keyboardVisible = false
    }
    .tint(GlassPalette.ink)
    .preferredColorScheme(.light)
  }

  private var tabBar: some View {
    HStack(spacing: 6) {
      tabButton("List", systemImage: "list.bullet", value: 0)
      tabButton("Map", systemImage: "map", value: 1)
    }
    .padding(5)
    .background { AutoGlassBackground(cornerRadius: 32) }
    .shadow(color: .black.opacity(0.04), radius: 10, y: 5)
    .frame(maxWidth: 300)
    .padding(.horizontal, 20)
    .padding(.vertical, 8)
    .onGeometryChange(for: CGFloat.self) { geometry in
      geometry.size.height
    } action: { height in
      tabBarHeight = height
    }
  }

  private func tabButton(_ title: String, systemImage: String, value: Int) -> some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) { selectedTab = value }
    } label: {
      Label(title, systemImage: systemImage)
        .font(.system(.subheadline, design: .rounded, weight: .semibold))
        .foregroundStyle(selectedTab == value ? .white : GlassPalette.heading)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background {
          if selectedTab == value { Capsule().fill(GlassPalette.ink) }
        }
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selectedTab == value ? .isSelected : [])
  }
}

#Preview {
  ContentView()
}
