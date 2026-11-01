import Foundation
import SwiftUI
import UIKit

struct WidgetPlace: Codable, Identifiable {
  let id: UUID
  let name: String
  let color: WidgetColor
  let reference: PlaceReference?
  var data: PlacePopularTimes?
  var lastAttempt: Date?
}

struct WidgetColor: Codable {
  let preset: Int?
  let red: Double
  let green: Double
  let blue: Double

  init(_ color: Color) {
    preset = GlassPalette.savedTints.firstIndex(of: color)
    let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 1
    resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
    red = Double(r)
    green = Double(g)
    blue = Double(b)
  }

  var color: Color {
    if let preset, GlassPalette.savedTints.indices.contains(preset) {
      return GlassPalette.savedTints[preset]
    }
    return Color(red: red, green: green, blue: blue)
  }
}

enum WidgetStorage {
  static let group =
    Bundle.main.object(forInfoDictionaryKey: "SharedAppGroup") as? String
    ?? "group.com.example.PopularTimeWidget"
  static let kind = "BusyTimeWidget"
  static let liveColorKey = "appearance.liveBarColor.v1"
  static var defaults: UserDefaults { UserDefaults(suiteName: group)! }

  static func liveBarColor(from data: Data) -> Color {
    (try? JSONDecoder().decode(WidgetColor.self, from: data))?.color ?? GlassPalette.liveOverlay
  }

  static func places(from defaults: UserDefaults = WidgetStorage.defaults) -> [WidgetPlace] {
    guard let data = defaults.data(forKey: "widget.places.v1") else { return [] }
    return (try? JSONDecoder().decode([WidgetPlace].self, from: data)) ?? []
  }

  static func publish(_ places: [WidgetPlace], to defaults: UserDefaults = WidgetStorage.defaults) {
    guard let data = try? JSONEncoder().encode(places) else { return }
    defaults.set(data, forKey: "widget.places.v1")
  }

  static func cached(_ place: WidgetPlace, from defaults: UserDefaults = WidgetStorage.defaults)
    -> WidgetPlace
  {
    guard let data = defaults.data(forKey: cacheKey(place.id)),
      let cached = try? JSONDecoder().decode(WidgetPlace.self, from: data),
      cached.reference?.placeID == place.reference?.placeID,
      (cached.lastAttempt ?? .distantPast) > (place.lastAttempt ?? .distantPast)
    else { return place }
    var updated = place
    updated.data = cached.data ?? place.data
    updated.lastAttempt = cached.lastAttempt
    return updated
  }

  static func saveCache(_ place: WidgetPlace, to defaults: UserDefaults = WidgetStorage.defaults) {
    guard let data = try? JSONEncoder().encode(place) else { return }
    defaults.set(data, forKey: cacheKey(place.id))
  }

  static func removeCache(_ id: UUID, from defaults: UserDefaults = WidgetStorage.defaults) {
    defaults.removeObject(forKey: cacheKey(id))
  }

  private static func cacheKey(_ id: UUID) -> String { "widget.cache.\(id.uuidString)" }
}
