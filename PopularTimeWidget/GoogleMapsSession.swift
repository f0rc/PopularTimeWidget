import Combine
import CoreLocation
import Foundation

@MainActor
final class GoogleMapsSession: GoogleMapsCookieSession {
  @Published private(set) var revision = UUID()

  override func didSaveSession() {
    revision = UUID()
  }
}

struct SelectedMapPlace: Codable, Equatable, Sendable {
  let appleID: String?
  let name: String
  let address: String
  let latitude: Double
  let longitude: Double

  var searchQuery: String { "\(name) \(address)" }
  var isValid: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !address.isEmpty
      && latitude.isFinite && longitude.isFinite
      && (-90...90).contains(latitude) && (-180...180).contains(longitude)
  }
}

struct MapPlaceAssessment: Sendable {
  let distanceMeters: Double
  let isNearby: Bool
  let isConfident: Bool
}

enum MapPlaceMatching {
  static func assess(_ match: MapsSearchMatch, against apple: SelectedMapPlace)
    -> MapPlaceAssessment
  {
    let distance = CLLocation(latitude: apple.latitude, longitude: apple.longitude)
      .distance(from: CLLocation(latitude: match.place.latitude, longitude: match.place.longitude))
    let nameMatches = normalizedName(apple.name) == normalizedName(match.place.name)
    let appleNumber = streetNumber(apple.address)
    let googleNumber = streetNumber(match.address)
    let numbersAgree = appleNumber == nil || googleNumber == nil || appleNumber == googleNumber
    return MapPlaceAssessment(
      distanceMeters: distance, isNearby: distance <= 750,
      isConfident: distance <= 150 && nameMatches && numbersAgree)
  }

  private static func normalizedName(_ value: String) -> String {
    var text = value.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    if text.hasPrefix("the ") { text = String(text.dropFirst(4)) }
    return String(text.filter { $0.isLetter || $0.isNumber })
  }
  private static func streetNumber(_ value: String) -> String? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let range = text.range(of: #"^\d+[A-Za-z]?(?=\s|,|$)"#, options: .regularExpression)
    else { return nil }
    return String(text[range]).lowercased()
  }
}

enum PlaceRefreshResult {
  case updated(PlaceReference, PlacePopularTimes)
  case choose([MapsSearchMatch])
}

enum PlaceRefreshService {
  static func refresh(_ record: Location) async throws -> PlaceRefreshResult {
    let originalCookies = try MapsSessionKeychain.load()
    let session = try makeAuthenticatedMapsSession(cookies: originalCookies)
    defer { session.invalidateAndCancel() }
    let result: PlaceRefreshResult
    if let reference = record.googlePlace {
      var request = try makePopularTimesRequest(for: reference)
      try attachMapsCookies(to: &request, from: session)
      let data = try await downloadMapsResponse(request, session: session)
      result = .updated(reference, try parsePopularTimesResponse(data, for: reference))
    } else {
      guard let coordinate = record.coordinate else {
        throw PopularTimesError.invalidPlace
      }
      let latitude = coordinate.latitude
      let longitude = coordinate.longitude
      let apple = SelectedMapPlace(
        appleID: nil, name: record.sourceName ?? record.name,
        address: record.address ?? "", latitude: latitude, longitude: longitude)
      let suffix = record.address ?? "\(latitude), \(longitude)"
      let found = try await searchMaps(query: "\(apple.name) \(suffix)", session: session)
      let nearby = found.filter { MapPlaceMatching.assess($0, against: apple).isNearby }
        .sorted {
          MapPlaceMatching.assess($0, against: apple).distanceMeters
            < MapPlaceMatching.assess($1, against: apple).distanceMeters
        }
      let confident = nearby.filter { MapPlaceMatching.assess($0, against: apple).isConfident }
      if confident.count == 1, let match = confident.first {
        guard let data = match.popularTimes else { throw PopularTimesError.unavailable }
        result = .updated(match.place, data)
      } else {
        result = .choose(nearby)
      }
    }
    try Task.checkCancellation()
    let current = try MapsSessionKeychain.load()
    if try MapsSessionKeychain.encodeCookies(current)
      == MapsSessionKeychain.encodeCookies(originalCookies)
    {
      let updated = applicableMapsCookies(session.configuration.httpCookieStorage?.cookies ?? [])
      if hasMapsSessionCookies(updated) { try MapsSessionKeychain.save(updated) }
    }
    return result
  }

  static func issue(for error: Error) -> String {
    switch error {
    case MapsSessionError.missingSession: return "Connect Google in Settings"
    case PopularTimesError.unavailable: return "No popular times"
    case PopularTimesError.rateLimited: return "Try again later"
    case PopularTimesError.httpStatus(let code)
    where code == 401 || code == 403 || (300..<400).contains(code):
      return "Reconnect Google in Settings"
    default: return "Update unavailable"
    }
  }
}
