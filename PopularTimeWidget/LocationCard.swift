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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black.opacity(0.82))
                .lineLimit(1)
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
                    .frame(width: 36, height: 36)
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

            PopularTimesChart(
                tint: location.tint,
                values: location.popularTimes
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            AutoGlassBackground(tint: location.tint)
        }
    }
}

#Preview {
    LocationCard(
        location: Location(name: "[Object object]", tint: .red, popularTimes: [12,12,12]),
        onEdit: {},
        onDelete: {}
    )
}
