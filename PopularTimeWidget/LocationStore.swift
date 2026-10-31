import Combine
import MapKit
import SwiftUI
import UIKit

final class LocationStore: ObservableObject {
  private static let storageKey = "locations.saved.v1"
  private let defaults: UserDefaults

  @Published var locations: [Location] {
    didSet { save() }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: Self.storageKey) {
      locations =
        (try? JSONDecoder().decode([SavedLocation].self, from: data))?
        .map(\.location) ?? []
    } else {
      locations = ListView.samples
      save()
    }
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(locations.map(SavedLocation.init)) else { return }
    defaults.set(data, forKey: Self.storageKey)
  }
}

private struct SavedLocation: Codable {
  let id: UUID
  let name: String
  let color: SavedColor
  let popularTimes: [Double]
  let latitude: Double?
  let longitude: Double?
  let sourceName: String?

  init(_ location: Location) {
    id = location.id
    name = location.name
    color = SavedColor(location.tint)
    popularTimes = location.popularTimes
    latitude = location.coordinate?.latitude
    longitude = location.coordinate?.longitude
    sourceName = location.sourceName
  }

  var location: Location {
    let coordinate: CLLocationCoordinate2D?
    if let latitude, let longitude {
      coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    } else {
      coordinate = nil
    }
    return Location(
      id: id, name: name, tint: color.color, popularTimes: popularTimes,
      coordinate: coordinate, sourceName: sourceName)
  }
}

private struct SavedColor: Codable {
  // Preserve named colors so the reference palette stays identical after relaunch.
  let presetIndex: Int?
  let red: Double
  let green: Double
  let blue: Double
  let alpha: Double

  init(_ color: Color) {
    presetIndex = GlassPalette.savedTints.firstIndex(of: color)
    let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 1
    resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
    red = Double(r)
    green = Double(g)
    blue = Double(b)
    alpha = Double(a)
  }

  var color: Color {
    if let presetIndex, GlassPalette.savedTints.indices.contains(presetIndex) {
      return GlassPalette.savedTints[presetIndex]
    }
    return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
  }
}
