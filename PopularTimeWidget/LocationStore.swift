import Combine
import MapKit
import SwiftUI
import UIKit
import WidgetKit

@MainActor
final class LocationStore: ObservableObject {
  private static let storageKey = "locations.saved.v1"
  private let defaults: UserDefaults
  private let publishesWidgets: Bool
  @Published var locations: [Location] {
    didSet {
      if publishesWidgets {
        for removed in oldValue where !locations.contains(where: { $0.id == removed.id }) {
          WidgetStorage.removeCache(removed.id)
        }
      }
      save()
    }
  }
  @Published private(set) var refreshingIDs: Set<UUID> = []
  @Published private(set) var matches: [UUID: [MapsSearchMatch]] = [:]
  @Published private(set) var lastVerifiedAt: Date?
  private var refreshingAll = false

  init(defaults: UserDefaults? = nil) {
    self.defaults = defaults ?? .standard
    publishesWidgets = defaults == nil
    if let data = self.defaults.data(forKey: Self.storageKey),
      let saved = try? JSONDecoder().decode([SavedLocation].self, from: data)
    {
      locations = saved.map { $0.location }
    } else {
      locations = []
    }
    if publishesWidgets {
      WidgetStorage.publish(locations.map { widgetPlace($0) })
      WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.kind)
    }
  }

  func importWidgetUpdates() {
    guard publishesWidgets else { return }
    for index in locations.indices {
      let snapshot = widgetPlace(locations[index])
      let cached = WidgetStorage.cached(snapshot)
      if let data = cached.data,
        data.fetchedAt > (locations[index].busyness?.fetchedAt ?? .distantPast)
      {
        locations[index].busyness = data
        locations[index].lastRefreshAttempt = cached.lastAttempt
        locations[index].refreshIssue = nil
      }
    }
  }

  private func widgetPlace(_ location: Location) -> WidgetPlace {
    WidgetPlace(
      id: location.id, name: location.name, color: WidgetColor(location.tint),
      reference: location.googlePlace, data: location.busyness,
      lastAttempt: location.lastRefreshAttempt)
  }

  func refreshAll(cadence: RefreshCadence = .foreground, force: Bool = false) async {
    guard !refreshingAll else { return }
    refreshingAll = true
    defer { refreshingAll = false }
    for id in locations.map(\.id) {
      guard !Task.isCancelled else { return }
      await refresh(id, cadence: cadence, force: force)
    }
  }

  /// Resolve IDs against the current list so a refresh during a drag keeps its data.
  func move(_ ids: [UUID], before destination: UUID?) {
    let requested = Set(ids)
    guard !requested.isEmpty,
      destination.map({ !requested.contains($0) }) ?? true
    else { return }
    var seen = Set<UUID>()
    let moving = ids.compactMap { id -> Location? in
      guard seen.insert(id).inserted else { return nil }
      return locations.first { $0.id == id }
    }
    guard !moving.isEmpty else { return }
    var reordered = locations.filter { !requested.contains($0.id) }
    let insertion: Int
    if let destination {
      guard let index = reordered.firstIndex(where: { $0.id == destination }) else { return }
      insertion = index
    } else {
      insertion = reordered.endIndex
    }
    reordered.insert(contentsOf: moving, at: insertion)
    guard reordered.map(\.id) != locations.map(\.id) else { return }
    locations = reordered
  }

  func refresh(_ id: UUID, cadence: RefreshCadence = .foreground, force: Bool = true) async {
    guard !refreshingIDs.contains(id), let index = locations.firstIndex(where: { $0.id == id }),
      locations[index].coordinate != nil,
      force || cadence.isDue(locations[index])
    else { return }
    let location = locations[index]
    refreshingIDs.insert(id)
    defer { refreshingIDs.remove(id) }
    locations[index].lastRefreshAttempt = Date()
    locations[index].refreshIssue = nil
    do {
      let result = try await PlaceRefreshService.refresh(location)
      try Task.checkCancellation()
      guard let current = locations.firstIndex(where: { $0.id == id }) else { return }
      switch result {
      case .updated(let reference, let data):
        locations[current].googlePlace = reference
        locations[current].busyness = data
        locations[current].refreshIssue = nil
        matches[id] = nil
        lastVerifiedAt = data.fetchedAt
      case .choose(let options):
        matches[id] = options
        locations[current].refreshIssue =
          options.isEmpty ? "No matching listing" : "Choose Google listing"
      }
    } catch {
      guard let current = locations.firstIndex(where: { $0.id == id }) else { return }
      locations[current].refreshIssue =
        Task.isCancelled
        ? "Update interrupted" : PlaceRefreshService.issue(for: error)
    }
  }

  func select(_ match: MapsSearchMatch, for id: UUID) {
    guard matches[id]?.contains(where: { $0.id == match.id }) == true,
      let index = locations.firstIndex(where: { $0.id == id })
    else { return }
    locations[index].googlePlace = match.place
    locations[index].busyness = match.popularTimes
    locations[index].lastRefreshAttempt = Date()
    locations[index].refreshIssue = match.popularTimes == nil ? "No popular times" : nil
    if let data = match.popularTimes { lastVerifiedAt = data.fetchedAt }
    matches[id] = nil
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(locations.map { SavedLocation($0) }) else { return }
    defaults.set(data, forKey: Self.storageKey)
    guard publishesWidgets else { return }
    WidgetStorage.publish(locations.map { widgetPlace($0) })
    WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.kind)
  }
}

enum RefreshCadence {
  case foreground, daily, hourly
  var interval: TimeInterval {
    switch self {
    case .foreground: return 5 * 60
    case .daily: return 24 * 60 * 60
    case .hourly: return 60 * 60
    }
  }

  func isDue(_ location: Location, now: Date = Date()) -> Bool {
    guard location.coordinate != nil else { return false }
    if location.refreshIssue == "Update interrupted" { return true }
    return now.timeIntervalSince(location.lastRefreshAttempt ?? .distantPast) >= interval
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
  let address: String?
  let googlePlace: PlaceReference?
  let busyness: PlacePopularTimes?
  let lastRefreshAttempt: Date?
  let refreshIssue: String?

  init(_ location: Location) {
    id = location.id
    name = location.name
    color = SavedColor(location.tint)
    popularTimes = location.popularTimes
    latitude = location.coordinate?.latitude
    longitude = location.coordinate?.longitude
    sourceName = location.sourceName
    address = location.address
    googlePlace = location.googlePlace
    busyness = location.busyness
    lastRefreshAttempt = location.lastRefreshAttempt
    refreshIssue = location.refreshIssue
  }

  var location: Location {
    let coordinate: CLLocationCoordinate2D?
    if let latitude, let longitude {
      coordinate = .init(latitude: latitude, longitude: longitude)
    } else {
      coordinate = nil
    }
    return Location(
      id: id, name: name, tint: color.color, popularTimes: popularTimes,
      coordinate: coordinate, sourceName: sourceName, address: address, googlePlace: googlePlace,
      busyness: busyness, lastRefreshAttempt: lastRefreshAttempt, refreshIssue: refreshIssue)
  }
}

private struct SavedColor: Codable {
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
