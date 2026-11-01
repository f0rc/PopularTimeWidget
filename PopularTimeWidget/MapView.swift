//
//  MapView.swift
//  PopularTimeWidget
//
//  Created by xbox on 10/30/26.
//

import MapKit
import SwiftUI

struct MapView: View {
  @Binding var locations: [Location]
  var bottomContentInset: CGFloat = 0
  @StateObject private var userLocation = MapLocation()
  @State private var position: MapCameraPosition =
    MapLocation.savedRegion.map { .region($0) } ?? .automatic
  @State private var visibleRegion = MapLocation.savedRegion
  @State private var query = ""
  @State private var results: [MKMapItem] = []
  @State private var isSearching = false
  @State private var searchMessage: String?
  @State private var selectedID: UUID?
  @FocusState private var searchFocused: Bool
  @ScaledMetric private var searchFieldHeight = 44
  @ScaledMetric private var locationButtonSize = 60
  @Environment(\.openURL) private var openURL

  var body: some View {
    Map(position: $position) {
      UserAnnotation()
      ForEach(locations) { location in
        if let coordinate = location.coordinate {
          Annotation(location.name, coordinate: coordinate) {
            Button {
              selectedID = location.id
              searchFocused = false
              query = ""
            } label: {
              Text(location.initials)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(GlassPalette(location.tint).foreground)
                .frame(width: 48, height: 48)
                .background { AutoGlassBackground(tint: location.tint).clipShape(Circle()) }
                .overlay(Circle().stroke(.white, lineWidth: selectedID == location.id ? 3 : 1.5))
                .shadow(color: GlassPalette(location.tint).edge.opacity(0.18), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(location.name)
          }
          .annotationTitles(.hidden)
        }
      }
    }
    .mapStyle(
      .standard(
        elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)
    )
    .mapControlVisibility(.hidden)
    .onMapCameraChange(frequency: .onEnd) { context in
      visibleRegion = context.region
      MapLocation.save(context.region)
    }
    .safeAreaPadding(.bottom, bottomContentInset)
    .safeAreaInset(edge: .top, spacing: 0) {
      VStack(alignment: .trailing, spacing: 14) {
        searchPanel
        if query.isEmpty && !searchFocused {
          locationButton
        }
      }
      .padding(16)
    }
    .sheet(
      isPresented: Binding(
        get: { selectedID != nil },
        set: { if !$0 { selectedID = nil } }
      )
    ) {
      if let index = locations.firstIndex(where: { $0.id == selectedID }) {
        LocationDetailsView(location: $locations[index]) {
          selectedID = nil
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(GlassPalette.base)
      }
    }
    .onAppear { userLocation.start() }
    .onChange(of: userLocation.coordinate?.latitude) {
      if let coordinate = userLocation.coordinate { center(on: coordinate) }
    }
    .task(
      id:
        "\(query)|\(userLocation.coordinate?.latitude ?? 0)|\(userLocation.coordinate?.longitude ?? 0)"
    ) {
      await search()
    }
  }

  private var locationButton: some View {
    Button {
      if userLocation.needsSettings, let url = URL(string: UIApplication.openSettingsURLString) {
        openURL(url)
      } else if let coordinate = userLocation.coordinate {
        center(on: coordinate)
      } else {
        userLocation.start()
      }
    } label: {
      Image(systemName: "location.fill")
        .font(.system(size: 23, weight: .semibold))
        .foregroundStyle(GlassPalette.ink)
        .frame(width: locationButtonSize, height: locationButtonSize)
        .background { AutoGlassBackground(cornerRadius: locationButtonSize / 2) }
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      userLocation.needsSettings ? "Open location settings" : "Center on my location")
  }

  private var searchPanel: some View {
    VStack(spacing: 14) {
      HStack(spacing: 12) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 20, weight: .medium))
          .foregroundStyle(GlassPalette.heading)
        TextField("Search places", text: $query)
          .font(.system(.body, design: .rounded))
          .textFieldStyle(.plain)
          .frame(maxWidth: .infinity)
          .focused($searchFocused)
          .submitLabel(.search)
          .autocorrectionDisabled()
          .onSubmit { searchFocused = false }
        ZStack {
          if isSearching {
            ProgressView()
              .controlSize(.small)
              .accessibilityLabel("Searching places")
          }
        }
        .frame(width: 24, height: 24)

        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 20))
            .foregroundStyle(GlassPalette.outline)
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .opacity(query.isEmpty ? 0 : 1)
        .disabled(query.isEmpty)
        .accessibilityHidden(query.isEmpty)
        .accessibilityLabel("Clear search")
      }
      .frame(height: searchFieldHeight)

      if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if !results.isEmpty {
          HStack {
            Text("Search results")
              .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(results.count) places")
              .font(.system(.caption, design: .rounded))
              .foregroundStyle(.secondary)
          }
          .padding(.horizontal, 2)

          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(results, id: \.self) { item in
                searchResult(item)
                if item != results.last {
                  Divider().padding(.leading, 52)
                }
              }
            }
            .padding(.bottom, 2)
          }
          .frame(maxHeight: searchFocused ? 260 : 380)
          .scrollDismissesKeyboard(.interactively)
        } else if let searchMessage {
          VStack(alignment: .leading, spacing: 6) {
            Label(searchMessage, systemImage: "magnifyingglass")
              .font(.system(.subheadline, design: .rounded, weight: .medium))
            Text("Try a place name, category, or city.")
              .font(.system(.caption, design: .rounded))
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 8)
        }
      }
    }
    .padding(14)
    .foregroundStyle(GlassPalette.ink)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    .overlay {
      RoundedRectangle(cornerRadius: 22)
        .strokeBorder(.black.opacity(0.06), lineWidth: 0.5)
    }
    .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
  }

  private func searchResult(_ item: MKMapItem) -> some View {
    let style = resultStyle(item)
    let saved = savedLocation(for: item)
    return Button {
      add(item)
    } label: {
      HStack(alignment: .center, spacing: 12) {
        Image(systemName: style.icon)
          .font(.system(size: 19, weight: .regular))
          .foregroundStyle(.secondary)
          .frame(width: 36, height: 40)

        VStack(alignment: .leading, spacing: 4) {
          Text(item.name ?? "Place")
            .font(.body.weight(.medium))
            .foregroundStyle(GlassPalette.ink)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
          if let address = item.address?.shortAddress ?? item.address?.fullAddress,
            !address.isEmpty
          {
            Text(address)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
          Text(resultSubtitle(item, category: style.title, isSaved: saved != nil))
            .font(.caption)
            .foregroundStyle(GlassPalette.heading)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Image(systemName: saved == nil ? "plus" : "checkmark")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 30, height: 30)
      }
      .padding(.vertical, 14)
      .padding(.horizontal, 2)
      .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityHint(saved == nil ? "Add to your locations" : "Open saved location")
  }

  private func resultStyle(_ item: MKMapItem) -> (icon: String, title: String) {
    switch item.pointOfInterestCategory {
    case .restaurant: return ("fork.knife", "Restaurant")
    case .cafe: return ("cup.and.saucer.fill", "Café")
    case .bakery: return ("birthday.cake.fill", "Bakery")
    case .store: return ("bag.fill", "Shopping")
    case .foodMarket: return ("cart.fill", "Groceries")
    case .park: return ("leaf.fill", "Park")
    case .fitnessCenter: return ("figure.run", "Fitness")
    case .hotel: return ("bed.double.fill", "Hotel")
    case .gasStation: return ("fuelpump.fill", "Gas station")
    default: return ("mappin.and.ellipse", "Place")
    }
  }

  private func resultSubtitle(_ item: MKMapItem, category: String, isSaved: Bool) -> String {
    var parts = [category]
    if let coordinate = userLocation.coordinate {
      let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
      let distance = origin.distance(from: item.location)
      parts.append(
        Measurement(value: distance, unit: UnitLength.meters).formatted(
          .measurement(width: .abbreviated, usage: .road)))
    }
    if isSaved { parts.append("Saved") }
    return parts.joined(separator: " · ")
  }

  private func savedLocation(for item: MKMapItem) -> Location? {
    let coordinate = item.location.coordinate
    return locations.first {
      guard let saved = $0.coordinate else { return false }
      return ($0.sourceName ?? $0.name) == item.name
        && abs(saved.latitude - coordinate.latitude) < 0.0001
        && abs(saved.longitude - coordinate.longitude) < 0.0001
    }
  }

  private func center(on coordinate: CLLocationCoordinate2D) {
    withAnimation(.smooth) { position = .region(MapLocation.region(around: coordinate)) }
  }

  private func search() async {
    results = []
    searchMessage = nil
    isSearching = false
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    isSearching = true
    do {
      try await Task.sleep(for: .milliseconds(350))
      try Task.checkCancellation()
      let request = MKLocalSearch.Request()
      request.naturalLanguageQuery = text
      request.resultTypes = .pointOfInterest
      request.region =
        visibleRegion ?? userLocation.coordinate.map { MapLocation.region(around: $0) }
        ?? MKCoordinateRegion(.world)
      let search = MKLocalSearch(request: request)
      let response = try await withTaskCancellationHandler {
        try await search.start()
      } onCancel: {
        search.cancel()
      }
      try Task.checkCancellation()
      var unique: [MKMapItem] = []
      for item in response.mapItems {
        let duplicate = unique.contains {
          $0.name == item.name && $0.location.distance(from: item.location) < 25
        }
        if !duplicate { unique.append(item) }
      }
      results = Array(unique.prefix(12))
      searchMessage = results.isEmpty ? "No places found. Try another name." : nil
    } catch {
      guard !Task.isCancelled else { return }
      searchMessage = "Couldn't search right now. Try again."
    }
    isSearching = false
  }

  private func add(_ item: MKMapItem) {
    let coordinate = item.location.coordinate
    let existing = savedLocation(for: item)
    if let existing {
      selectedID = existing.id
    } else {
      let tints = GlassPalette.savedTints
      let location = Location(
        name: item.name ?? "New place", tint: tints[locations.count % tints.count],
        popularTimes: [], coordinate: coordinate, sourceName: item.name,
        address: item.address?.fullAddress ?? item.address?.shortAddress)
      locations.append(location)
      selectedID = location.id
    }
    query = ""
    searchFocused = false
    center(on: coordinate)
  }
}

#Preview {
  MapView(locations: .constant([]))
    .environmentObject(LocationStore())
}
