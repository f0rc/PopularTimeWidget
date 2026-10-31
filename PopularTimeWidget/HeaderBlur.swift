//
//  HeaderBlur.swift
//  PopularTimeWidget
//
//  Created by xbox on 10/27/26.
//

import Foundation
import SwiftUI

struct ProgressiveHeaderBackground: View {
  var body: some View {
    GeometryReader { geometry in
      Rectangle()
        .fill(
          LinearGradient(
            stops: [
              .init(
                color: GlassPalette.base,
                location: 0
              ),
              .init(
                color: GlassPalette.base
                  .opacity(0.98),
                location: 0.25
              ),
              .init(
                color: GlassPalette.base
                  .opacity(0.82),
                location: 0.50
              ),
              .init(
                color: GlassPalette.base
                  .opacity(0.40),
                location: 0.75
              ),
              .init(
                color: .clear,
                location: 1
              ),
            ],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .frame(height: geometry.size.height)
    }
    .allowsHitTesting(false)
  }
}
