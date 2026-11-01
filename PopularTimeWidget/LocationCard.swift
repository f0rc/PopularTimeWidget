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
  var onRefresh: () -> Void = {}
  var isRefreshing = false
  var hasRefreshIssue = false

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

        Button(action: onRefresh) {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(isRefreshing)

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
        Image(systemName: hasRefreshIssue ? "exclamationmark.circle" : "ellipsis")
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
          .opacity(isRefreshing ? 0 : 1)
          .overlay {
            if isRefreshing {
              ProgressView()
                .controlSize(.small)
                .tint(GlassPalette(tint).foreground)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
          }
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Location options")
      .accessibilityValue(isRefreshing ? "Refreshing" : (hasRefreshIssue ? "Last update failed" : ""))
    }
  }
}

struct LocationCard: View {
  let location: Location
  let onEdit: () -> Void
  let onDelete: () -> Void
  var onRefresh: () -> Void = {}
  var isRefreshing = false
  var showsLive = true

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      LocationCardHeader(
        name: location.name,
        tint: location.tint,
        onEdit: onEdit,
        onDelete: onDelete,
        onRefresh: onRefresh,
        isRefreshing: isRefreshing,
        hasRefreshIssue: location.busyness != nil && location.refreshIssue != nil
      )

      if let data = location.busyness {
        PopularTimesChart(tint: location.tint, data: data, showsLive: showsLive)
      } else {
        Text(
          location.refreshIssue == "Choose Google listing"
            ? "Choose a listing in Details" : "No popular times"
        )
        .font(.system(.subheadline, design: .rounded))
        .foregroundStyle(GlassPalette.heading)
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
    location: ListView.samples[0],
    onEdit: {},
    onDelete: {}
  )
}
