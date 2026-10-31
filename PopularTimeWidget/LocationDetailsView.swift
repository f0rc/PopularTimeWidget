import SwiftUI

struct LocationDetailsView: View {
  @Binding var location: Location
  var onDone: () -> Void
  @FocusState private var nameFocused: Bool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 10) {
          sectionTitle("Location name")
          TextField("Location name", text: $location.name, axis: .vertical)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(GlassPalette.ink)
            .lineLimit(1...3)
            .focused($nameFocused)
            .submitLabel(.done)
            .onSubmit { nameFocused = false }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
            .accessibilityLabel("Location name")
        }

        VStack(alignment: .leading, spacing: 10) {
          sectionTitle("Appearance")
          ColorPicker("Location color", selection: $location.tint, supportsOpacity: false)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(GlassPalette.ink)
            .padding(18)
            .frame(minHeight: 64)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
        }

        Text("Changes are saved automatically.")
          .font(.system(.footnote, design: .rounded))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 4)
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 24)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(GlassPalette.base.ignoresSafeArea())
    .safeAreaInset(edge: .top, spacing: 0) {
      HStack(spacing: 16) {
        Text("Location details")
          .font(.system(.title2, design: .rounded, weight: .bold))
          .foregroundStyle(GlassPalette.heading)
          .frame(maxWidth: .infinity, alignment: .leading)

        Button {
          nameFocused = false
          onDone()
        } label: {
          Text("Done")
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .background(GlassPalette.ink, in: Capsule())
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 24)
      .padding(.top, 24)
      .padding(.bottom, 18)
      .background(GlassPalette.base)
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(.headline, design: .rounded, weight: .semibold))
      .foregroundStyle(GlassPalette.heading)
      .padding(.horizontal, 4)
  }
}

#Preview {
  LocationDetailsView(location: .constant(ListView.samples[0]), onDone: {})
}
