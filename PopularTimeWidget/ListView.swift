//
//  ListView.swift
//  PopularTimeWidget
//
//  Created by xbox on 10/30/26.
//

import MapKit
import SwiftUI
import UIKit

struct Location: Identifiable {
  var id = UUID()
  var name: String
  var tint: Color
  var popularTimes: [Double]
  var coordinate: CLLocationCoordinate2D? = nil
  var sourceName: String? = nil
  var address: String? = nil
  var googlePlace: PlaceReference? = nil
  var busyness: PlacePopularTimes? = nil
  var lastRefreshAttempt: Date? = nil
  var refreshIssue: String? = nil

  var initials: String {
    let letters = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      .prefix(2).compactMap(\.first)
    return letters.isEmpty ? "?" : String(letters).uppercased()
  }
}

struct ListView: View {
  @EnvironmentObject private var store: LocationStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isSheetPresented = false

  @Binding var locations: [Location]
  var bottomContentInset: CGFloat = 0
  var onAdd: () -> Void = {}
  @Binding var openedLocationID: UUID?

  static let samples: [Location] = [
    Location(
      name: "The Galleria Shopping Center Houston",
      tint: .blue,
      popularTimes: [
        25, 23, 21, 19, 18, 19,
        20, 22, 25, 28, 32, 38,
        45, 55, 70, 85, 95, 78,
        55, 28, 15, 8, 7, 15,
      ]
    ),
    Location(
      name: "Downtown Restaurant",
      tint: .purple,
      popularTimes: [
        10, 8, 9, 12, 18, 25,
        45, 60, 68, 55, 40, 32,
        35, 42, 55, 75, 90, 80,
        72, 60, 45, 28, 15, 10,
      ]
    ),
    Location(
      name: "Shopping Center",
      tint: .yellow,
      popularTimes: [
        12, 10, 10, 12, 15, 18,
        25, 32, 45, 60, 70, 75,
        80, 85, 88, 90, 85, 78,
        65, 50, 35, 22, 15, 10,
      ]
    ),
  ].map { sample in
    var sample = sample
    let hours = sample.popularTimes.enumerated().map { index, value in
      HourPopularity(
        hour: (index + 6) % 24, busyness: Int(value),
        description: BusynessText.label(Int(value), live: false))
    }
    sample.busyness = PlacePopularTimes(
      placeID: "preview", name: sample.name, address: "", timeZoneIdentifier: nil,
      days: Weekday.allCases.map { PopularTimesDay(weekday: $0, hours: hours) },
      currentBusyness: nil, currentDescription: nil, fetchedAt: Date())
    return sample
  }

  @State private var editingID: UUID?
  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 16) {
          ForEach(locations) { location in
            LocationCard(
              location: location,
              onEdit: {
                editingID = location.id
              },
              onDelete: {
                withAnimation(.smooth) {
                  locations.removeAll {
                    $0.id == location.id
                  }
                }
              },
              onRefresh: { Task { await store.refresh(location.id) } },
              isRefreshing: store.refreshingIDs.contains(location.id)
            )
          }
          .reorderable()
        }
        .reorderContainer(for: Location.self) { difference in
          let destination: UUID?
          switch difference.destination.position {
          case .before(let id): destination = id
          case .end: destination = nil
          }
          withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            store.move(difference.sources, before: destination)
          }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 24)
      }
      .contentMargins(.bottom, bottomContentInset, for: .scrollContent)
      .background {
        GlassPalette.base
          .ignoresSafeArea()
      }
      .safeAreaInset(edge: .top, spacing: 0) {
        HStack {
          Text("Locations")
            .font(.system(.title, design: .rounded, weight: .bold))
            .foregroundStyle(GlassPalette.heading)
          Spacer()
          Button(action: onAdd) {
            Image(systemName: "plus")
              .font(.system(size: 21, weight: .medium))
              .foregroundStyle(GlassPalette.heading)
              .frame(width: 44, height: 44)
              .background { AutoGlassBackground(cornerRadius: 22) }
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Add location")
          Button {
            isSheetPresented = true
          } label: {
            Image(systemName: "gearshape.fill")
              .font(.system(size: 21, weight: .medium))
              .foregroundStyle(GlassPalette.heading)
              .frame(width: 44, height: 44)
              .glassEffect(.regular.interactive(), in: Circle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(GlassPalette.base)
      }
      .sheet(
        isPresented: Binding(
          get: { editingID != nil },
          set: { if !$0 { editingID = nil } }
        )
      ) {
        if let index = locations.firstIndex(where: { $0.id == editingID }) {
          LocationDetailsView(location: $locations[index]) { editingID = nil }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
      }
    }
    .onChange(of: openedLocationID, initial: true) {
      if let id = openedLocationID, locations.contains(where: { $0.id == id }) {
        editingID = id
        openedLocationID = nil
      }
    }
    .sheet(isPresented: $isSheetPresented) {
      SettingsSheet(isPresented: $isSheetPresented) {
        AppSettingsContent(locationCount: locations.count)
      }
    }

  }
}

#Preview {
  ListView(locations: .constant(ListView.samples), openedLocationID: .constant(nil))
    .environmentObject(LocationStore())
    .environmentObject(GoogleMapsSession())
}
