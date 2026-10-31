//
//  LocationCard.swift
//  PopularTimeWidget
//
//  Created by xbox on 10/27/26.
//

import SwiftUI

struct LocationCardHeader: View {
  let name: String
  let tint: Color
  let onEdit: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Text(name)
        .font(.system(.title3, design: .rounded, weight: .bold))
        .foregroundStyle(GlassPalette.ink)
        .lineLimit(2)
        .truncationMode(.tail)
        .frame(
          maxWidth: .infinity,
          alignment: .leading
        )
        .layoutPriority(1)

      Menu {
        Button(action: onEdit) {
          Label(
            "Edit Location",
            systemImage: "pencil"
          )
        }

        Divider()

        Button(
          role: .destructive,
          action: onDelete
        ) {
          Label(
            "Delete Location",
            systemImage: "trash"
          )
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(
            .system(
              size: 19,
              weight: .semibold
            )
          )
          .foregroundStyle(
            GlassPalette(tint).foreground
          )
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Location options")
    }
  }
}

struct LocationCard: View {
  let location: Location
  let onEdit: () -> Void
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      LocationCardHeader(
        name: location.name,
        tint: location.tint,
        onEdit: onEdit,
        onDelete: onDelete
      )

      if location.popularTimes.isEmpty {
        Label("Popular times aren't available yet", systemImage: "clock")
          .font(.subheadline)
          .foregroundStyle(GlassPalette(location.tint).foreground)
      } else {
        PopularTimesChart(
          tint: location.tint,
          values: location.popularTimes
        )
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity)
    .background {
      AutoGlassBackground(tint: location.tint)
    }
  }
}

#Preview {
  LocationCard(
    location: Location(name: "[Object object]", tint: .red, popularTimes: [12, 12, 12]),
    onEdit: {},
    onDelete: {}
  )
}
