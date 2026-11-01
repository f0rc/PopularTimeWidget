import SwiftUI

struct LocationDetailsView: View {
  @EnvironmentObject private var store: LocationStore
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

        refreshSection

        Text("Changes are saved automatically.")
          .font(.system(.footnote, design: .rounded))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 4)
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 24)
    }
    .task(id: location.id) { await store.refresh(location.id, force: false) }
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

  private var refreshSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionTitle("Popular times")
      VStack(alignment: .leading, spacing: 12) {
        if let updated = location.busyness?.fetchedAt {
          Text("Updated \(updated.formatted(date: .abbreviated, time: .shortened))")
            .font(.subheadline)
        }
        if let issue = location.refreshIssue {
          Text(issue).font(.subheadline).foregroundStyle(.secondary)
        }
        Button {
          Task { await store.refresh(location.id) }
        } label: {
          HStack {
            Text("Refresh")
            Spacer()
            if store.refreshingIDs.contains(location.id) {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "arrow.clockwise")
            }
          }
          .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(store.refreshingIDs.contains(location.id))

        if let matches = store.matches[location.id], !matches.isEmpty {
          ForEach(matches) { match in
            Divider()
            Button {
              store.select(match, for: location.id)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(match.place.name).font(.subheadline.weight(.semibold))
                Text(match.address).font(.caption).foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
          }
        }
      }
      .padding(18)
      .foregroundStyle(GlassPalette.ink)
      .background(.white, in: RoundedRectangle(cornerRadius: 24))
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
    .environmentObject(LocationStore())
}
