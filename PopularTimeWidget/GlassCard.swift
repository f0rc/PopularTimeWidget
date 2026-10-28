//
//  GlassCard.swift
//  PopularTimeWidget
//
//  Created by xbox on 10/27/26.
//

import SwiftUI

struct GlassPalette {
    let fill: Color
    let glow: Color
    let edge: Color
    let border: Color
    let foreground: Color

    init(_ tint: Color) {
        let uiColor = UIColor(tint)

        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        if !uiColor.getHue(
            &h,
            saturation: &s,
            brightness: &b,
            alpha: &a
        ) {
            h = 0
            s = 0
        }

        func color(
            _ saturation: Double,
            _ brightness: Double
        ) -> Color {
            Color(
                hue: Double(h),
                saturation: saturation,
                brightness: brightness
            )
        }

        fill = color(0.25, 0.96)
        glow = color(0.15, 0.99)
        edge = color(0.31, 0.93)
        border = color(0.42, 0.80)
        foreground = color(0.58, 0.60)
    }
}

struct AutoGlassBackground: View {
    let tint: Color

    private let radius: CGFloat = 24

    private var palette: GlassPalette {
        GlassPalette(tint)
    }

    var body: some View {
        GeometryReader { geometry in
            let shape = RoundedRectangle(
                cornerRadius: radius,
                style: .continuous
            )

            shape
                .fill(palette.fill)

                // Soft vertical shading
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                palette.glow.opacity(0.55),
                                palette.fill.opacity(0.20),
                                palette.edge.opacity(0.65)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                // Radial glow
                .overlay {
                    shape.fill(
                        RadialGradient(
                            stops: [
                                .init(
                                    color: .white.opacity(0.23),
                                    location: 0
                                ),
                                .init(
                                    color: .white.opacity(0.10),
                                    location: 0.45
                                ),
                                .init(
                                    color: .clear,
                                    location: 1
                                )
                            ],
                            center: UnitPoint(x: 0.5, y: 0.3),
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.75
                        )
                    )
                }

                // Colored border
                .overlay {
                    shape.strokeBorder(
                        palette.border.opacity(0.68),
                        lineWidth: 1.1
                    )
                }

                // Top glass reflection
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(
                                    color: .white.opacity(0.65),
                                    location: 0
                                ),
                                .init(
                                    color: .white.opacity(0.12),
                                    location: 0.18
                                ),
                                .init(
                                    color: .clear,
                                    location: 0.42
                                )
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
        }
    }
}

#Preview {
    AutoGlassBackground(tint: .red)
}
