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

  var initials: String {
    let letters = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      .prefix(2).compactMap(\.first)
    return letters.isEmpty ? "?" : String(letters).uppercased()
  }
}

struct ListView: View {
  @Binding var locations: [Location]
  var bottomContentInset: CGFloat = 0
  var onAdd: () -> Void = {}

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
  ]

  @State private var editingID: UUID?
  @State private var editedName = ""
  @State private var showEditAlert = false
  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 16) {
          ForEach(locations) { location in
            LocationCard(
              location: location,
              onEdit: {
                editingID = location.id
                editedName = location.name
                showEditAlert = true
              },
              onDelete: {
                withAnimation(.smooth) {
                  locations.removeAll {
                    $0.id == location.id
                  }
                }
              }
            )
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
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(GlassPalette.base)
      }
      .alert(
        "Edit Location",
        isPresented: $showEditAlert
      ) {
        TextField("Location Name", text: $editedName)

        Button("Save") {
          let newName =
            editedName
            .trimmingCharacters(
              in: .whitespacesAndNewlines
            )

          guard !newName.isEmpty,
            let editingID,
            let index = locations.firstIndex(
              where: { $0.id == editingID }
            )
          else {
            return
          }

          locations[index].name = newName
          self.editingID = nil
        }

        Button("Cancel", role: .cancel) {
          editingID = nil
        }
      } message: {
        Text("Enter a new name for this location.")
      }
    }
  }
}

#Preview {
  ListView(locations: .constant(ListView.samples))
}
