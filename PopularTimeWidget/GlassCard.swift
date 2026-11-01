import SwiftUI
import UIKit

struct GlassPalette {
  static let base = Color(white: 0.97)
  static let outline = Color(white: 0.54)
  static let ink = Color(white: 0.24)
  static let heading = Color(white: 0.34)
  static let alert = Color(red: 0.72, green: 0.14, blue: 0.18)
  static let liveOverlay = Color(red: 234 / 255, green: 165 / 255, blue: 155 / 255)

  static let savedTints: [Color] = [.blue, .purple, .yellow, .mint, .pink, .red, .gray]

  let fill: Color
  let glow: Color
  let edge: Color
  let border: Color
  let foreground: Color

  init(_ tint: Color? = nil) {
    guard let tint else {
      fill = .white
      glow = .white
      edge = Color(white: 0.96)
      border = Color(white: 0.78)
      foreground = Self.heading
      return
    }

    let presets: [(Color, UInt32, UInt32, UInt32)] = [
      (.blue, 0xDDECF7, 0xB4D3ED, 0x4E788E),
      (.purple, 0xE7D9F3, 0xCBAAE4, 0x7B52A0),
      (.yellow, 0xFBF2D1, 0xF4E19C, 0x8C7833),
      (.mint, 0xBDF5DB, 0x8DE5BB, 0x409B74),
      (.pink, 0xF4D5E9, 0xE9AAD5, 0xA74F88),
      (.red, 0xF4D0C9, 0xEAA59B, 0xA76155),
      (.gray, 0xECECEC, 0xDCDCDC, 0x828282),
    ]
    if let preset = presets.first(where: { $0.0 == tint }) {
      glow = Self.color(preset.1)
      fill = Self.color(preset.1)
      edge = Self.color(preset.2)
      border = Self.color(preset.3).opacity(0.55)
      foreground = Self.color(preset.3)
      return
    }

    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    var alpha: CGFloat = 0
    UIColor(tint).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    let isNeutral = saturation < 0.05

    func color(_ saturation: Double, _ brightness: Double) -> Color {
      Color(hue: Double(hue), saturation: isNeutral ? 0 : saturation, brightness: brightness)
    }

    fill = color(0.20, isNeutral ? 0.91 : 0.97)
    glow = color(0.12, 0.99)
    edge = color(0.31, isNeutral ? 0.86 : 0.94)
    border = color(0.38, isNeutral ? 0.74 : 0.79)
    foreground = color(0.50, isNeutral ? 0.43 : 0.51)
  }

  private static func color(_ hex: UInt32) -> Color {
    Color(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }

}

struct AutoGlassBackground: View {
  var tint: Color? = nil
  var cornerRadius: CGFloat = 26

  private var palette: GlassPalette { GlassPalette(tint) }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    shape
      .fill(
        LinearGradient(
          colors: [palette.glow, palette.fill, palette.edge],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .overlay {
        if tint != nil {
          shape.fill(
            LinearGradient(
              stops: [
                .init(color: .white.opacity(0.50), location: 0),
                .init(color: .white.opacity(0.22), location: 0.5),
                .init(color: .white.opacity(0.12), location: 1),
              ],
              startPoint: .top,
              endPoint: .bottom
            ))
        }
      }
      .overlay {
        shape.strokeBorder(palette.border.opacity(tint == nil ? 0.65 : 0.5), lineWidth: 1)
      }
      .overlay {
        shape.inset(by: 1).strokeBorder(
          LinearGradient(
            colors: [.white.opacity(0.75), .clear], startPoint: .top, endPoint: .center),
          lineWidth: 1
        )
      }
  }
}

#Preview {
  AutoGlassBackground(tint: .purple).frame(height: 80).padding()
}
