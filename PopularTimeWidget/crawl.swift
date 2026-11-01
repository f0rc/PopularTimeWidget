import Foundation

struct PlaceReference: Codable, Sendable {
  let placeID: String
  let featureID: String
  let name: String
  let latitude: Double
  let longitude: Double
  let knowledgeGraphID: String?

  init(
    placeID: String, featureID: String, name: String, latitude: Double, longitude: Double,
    knowledgeGraphID: String? = nil
  ) throws {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !name.contains(where: { $0.isNewline }),
      placeID.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil,
      featureID.range(of: #"^0x[0-9a-fA-F]+:0x[0-9a-fA-F]+$"#, options: .regularExpression) != nil,
      latitude.isFinite, (-90...90).contains(latitude),
      longitude.isFinite, (-180...180).contains(longitude)
    else {
      throw PopularTimesError.invalidPlace
    }
    if let knowledgeGraphID {
      guard
        knowledgeGraphID.range(of: #"^/(g|m)/[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
      else {
        throw PopularTimesError.invalidPlace
      }
    }
    self.placeID = placeID
    self.featureID = featureID
    self.name = name
    self.latitude = latitude
    self.longitude = longitude
    self.knowledgeGraphID = knowledgeGraphID
  }
}

struct PlacePopularTimes: Codable, Sendable {
  let placeID: String
  let name: String
  let address: String
  let timeZoneIdentifier: String?
  let days: [PopularTimesDay]
  let currentBusyness: Int?  // nil = unavailable; 0 is a valid score
  let currentDescription: String?
  let fetchedAt: Date

  var hasEveryHour: Bool { days.count == 7 && days.allSatisfy { $0.hours.count == 24 } }
}

struct PopularTimesDay: Codable, Sendable {
  let weekday: Weekday
  let hours: [HourPopularity]  // Sorted 0...23
}

struct HourPopularity: Codable, Sendable {
  let hour: Int
  let busyness: Int  // Google's relative 0...100 score
  let description: String
}

enum Weekday: Int, Codable, CaseIterable, Sendable {
  case monday = 1
  case tuesday, wednesday, thursday, friday, saturday, sunday
}

enum PopularTimesError: LocalizedError {
  case invalidURL
  case invalidPlace
  case httpStatus(Int)
  case rateLimited(retryAfter: String?)
  case unexpectedResponse
  case responseTooLarge
  case wrongPlace
  case unavailable
  case malformedResponse(String)

  var errorDescription: String? {
    switch self {
    case .invalidPlace: return "Provide valid place identifiers, a name, and coordinates."
    case .invalidURL: return "Could not build the Google Maps URL."
    case .httpStatus(let status): return "Google returned HTTP \(status)."
    case .rateLimited(let delay):
      return "Google limited this request." + (delay.map { " Retry-After: \($0)." } ?? "")
    case .unexpectedResponse:
      return "Google returned a page or challenge instead of place-details JSON."
    case .responseTooLarge: return "Google's response exceeded the 5 MB limit."
    case .wrongPlace: return "The response does not identify the requested place."
    case .unavailable: return "Google identified the place but omitted its popular-times data."
    case .malformedResponse(let field): return "Google's response format was unexpected: \(field)."
    }
  }
}

func downloadMapsResponse(_ request: URLRequest, session: URLSession) async throws -> Data {
  try Task.checkCancellation()
  let (bytes, response) = try await session.bytes(for: request)
  guard let http = response as? HTTPURLResponse else { throw PopularTimesError.unexpectedResponse }
  if http.statusCode == 429 {
    throw PopularTimesError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
  }
  guard (200..<300).contains(http.statusCode) else {
    throw PopularTimesError.httpStatus(http.statusCode)
  }
  guard response.expectedContentLength <= Int64(maximumResponseBytes) else {
    throw PopularTimesError.responseTooLarge
  }
  var data = Data()
  for try await byte in bytes {
    if data.count % 4096 == 0 { try Task.checkCancellation() }
    guard data.count < maximumResponseBytes else { throw PopularTimesError.responseTooLarge }
    data.append(byte)
  }
  try Task.checkCancellation()
  return data
}

func makePopularTimesRequest(for place: PlaceReference) throws -> URLRequest {
  var url = URLComponents()
  url.scheme = "https"
  url.host = "www.google.com"
  url.path = "/maps/preview/place"
  url.queryItems = [
    URLQueryItem(name: "authuser", value: "0"),
    URLQueryItem(name: "hl", value: "en"),
    URLQueryItem(name: "gl", value: "us"),
    URLQueryItem(name: "q", value: place.name),
    URLQueryItem(name: "pb", value: makePlacePB(for: place)),
  ]
  guard let address = url.url else { throw PopularTimesError.invalidURL }
  var request = URLRequest(
    url: address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
  request.setValue(
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:158.0) Gecko/20100101 Firefox/158.0",
    forHTTPHeaderField: "User-Agent")
  request.setValue("*/*", forHTTPHeaderField: "Accept")
  request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
  request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
  request.setValue(
    "https://www.google.com/maps/",
    forHTTPHeaderField: "Referer")
  return request
}

func parsePopularTimesResponse(_ data: Data, for place: PlaceReference) throws -> PlacePopularTimes
{
  guard data.count <= maximumResponseBytes else { throw PopularTimesError.responseTooLarge }
  guard let text = String(data: data, encoding: .utf8), text.hasPrefix(")]}'") else {
    throw PopularTimesError.unexpectedResponse
  }
  let root: JSONValue

  do { root = try JSONDecoder().decode(JSONValue.self, from: Data(text.dropFirst(4).utf8)) } catch {
    throw PopularTimesError.malformedResponse("invalid JSON")
  }
  guard let info = root[6], info.array != nil else {
    throw PopularTimesError.malformedResponse("missing place record at [6]")
  }
  return try parsePlaceInfo(info, for: place)
}

private func parsePlaceInfo(_ info: JSONValue, for place: PlaceReference) throws
  -> PlacePopularTimes
{
  guard info[78]?.string == place.placeID,
    info[10]?.string?.lowercased() == place.featureID.lowercased()
  else {
    throw PopularTimesError.wrongPlace
  }
  guard let name = info[11]?.string, !name.isEmpty,
    let address = info[39]?.string, !address.isEmpty

  else {
    throw PopularTimesError.malformedResponse("missing business name or address")
  }
  guard let busyness = info[84], !busyness.isNull else { throw PopularTimesError.unavailable }
  guard let weekly = busyness[0], !weekly.isNull else { throw PopularTimesError.unavailable }

  guard let days = weekly.array, days.count == 7 else {
    throw PopularTimesError.malformedResponse("expected seven weekdays")
  }
  var byDay = Array(repeating: [Int: HourPopularity](), count: 7)
  var seen = Set<Weekday>()

  for day in days {
    guard let number = day[0]?.integer, let weekday = Weekday(rawValue: number),
      seen.insert(weekday).inserted, let rawEntries = day[1]
    else {
      throw PopularTimesError.malformedResponse("invalid or duplicate weekday")
    }
    let entries: [JSONValue]
    if rawEntries.isNull {
      entries = []
    } else if let array = rawEntries.array {
      entries = array

    } else {
      throw PopularTimesError.malformedResponse("invalid hourly entries")
    }
    var previousHour: Int?
    var offset = 0
    for entry in entries {
      guard let rawHour = entry[0]?.integer, (0...47).contains(rawHour),
        let score = entry[1]?.integer, (0...100).contains(score),
        let description = entry[2]?.string

      else {
        throw PopularTimesError.malformedResponse("invalid hour, score, or description")
      }

      if rawHour < 24, let previousHour, rawHour + offset * 24 < previousHour { offset += 1 }

      let absoluteHour = rawHour < 24 ? rawHour + offset * 24 : rawHour

      guard absoluteHour < 48, previousHour.map({ absoluteHour > $0 }) ?? true else {
        throw PopularTimesError.malformedResponse("duplicate or out-of-order hour")
      }
      previousHour = absoluteHour
      let index = (weekday.rawValue - 1 + absoluteHour / 24) % 7
      let hour = absoluteHour % 24
      guard byDay[index][hour] == nil else {
        throw PopularTimesError.malformedResponse("overlapping hours")
      }
      byDay[index][hour] = HourPopularity(hour: hour, busyness: score, description: description)
    }
  }
  guard byDay.contains(where: { !$0.isEmpty }) else { throw PopularTimesError.unavailable }
  let current = busyness[7]

  var currentScore: Int?

  if let current, !current.isNull {
    guard current.array != nil else {
      throw PopularTimesError.malformedResponse("invalid live busyness")
    }
    if let score = current[1], !score.isNull {
      guard let integer = score.integer, (0...100).contains(integer) else {
        throw PopularTimesError.malformedResponse("invalid live score")
      }
      currentScore = integer
    }
  }
  let normalized = Weekday.allCases.map { day in
    PopularTimesDay(
      weekday: day, hours: byDay[day.rawValue - 1].values.sorted { $0.hour < $1.hour })
  }
  return PlacePopularTimes(

    placeID: place.placeID, name: name, address: address,
    timeZoneIdentifier: try optionalString(info[30]), days: normalized,
    currentBusyness: currentScore, currentDescription: try optionalString(busyness[6]),
    fetchedAt: Date())
}

private func optionalString(_ value: JSONValue?) throws -> String? {
  guard let value, !value.isNull else { return nil }
  guard let text = value.string else {
    throw PopularTimesError.malformedResponse("expected optional text")
  }
  return text
}

private indirect enum JSONValue: Decodable {
  case array([JSONValue])
  case object([String: JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() {
      self = .null
    } else if let boolean = try? value.decode(Bool.self) {
      self = .bool(boolean)
    } else if let text = try? value.decode(String.self) {
      self = .string(text)
    } else if let array = try? value.decode([JSONValue].self) {
      self = .array(array)
    } else if let object = try? value.decode([String: JSONValue].self) {
      self = .object(object)
    } else {
      self = .number(try value.decode(Double.self))
    }
  }
  subscript(_ index: Int) -> JSONValue? {
    guard case .array(let values) = self, values.indices.contains(index) else { return nil }
    return values[index]
  }
  var array: [JSONValue]? {
    if case .array(let values) = self { return values }
    return nil
  }
  var string: String? {
    if case .string(let value) = self { return value }
    return nil
  }
  var number: Double? {
    if case .number(let value) = self { return value }
    return nil
  }
  var integer: Int? {
    if case .number(let value) = self { return Int(exactly: value) }
    return nil
  }
  var isNull: Bool {
    if case .null = self { return true }
    return false
  }
}

func parseMapsSearchResponse(_ data: Data) throws -> [MapsSearchMatch] {
  guard data.count <= maximumResponseBytes else { throw PopularTimesError.responseTooLarge }
  guard var text = String(data: data, encoding: .utf8) else {
    throw PopularTimesError.unexpectedResponse
  }
  text = String(text.components(separatedBy: "/*\"\"*/")[0])
  guard let end = text.lastIndex(of: "}") else { throw PopularTimesError.unexpectedResponse }
  text = String(text[...end])
  struct Envelope: Decodable { let d: String }
  let envelope: Envelope
  do { envelope = try JSONDecoder().decode(Envelope.self, from: Data(text.utf8)) } catch {
    throw PopularTimesError.unexpectedResponse
  }
  let inner = envelope.d.trimmingCharacters(in: .whitespacesAndNewlines)
  guard inner.hasPrefix(")]}'") else { throw PopularTimesError.unexpectedResponse }
  let root: JSONValue
  do { root = try JSONDecoder().decode(JSONValue.self, from: Data(inner.dropFirst(4).utf8)) } catch
  { throw PopularTimesError.malformedResponse("invalid search JSON") }

  guard let rows = root[0]?[1]?.array else {
    throw PopularTimesError.malformedResponse("missing search results")
  }
  var matches: [MapsSearchMatch] = []
  var seen = Set<String>()
  for row in rows {
    guard let info = row[14], let feature = info[10]?.string,
      let placeID = info[78]?.string, let name = info[11]?.string,
      let address = info[39]?.string, !address.isEmpty,

      let latitude = info[9]?[2]?.number, let longitude = info[9]?[3]?.number,
      let reference = try? PlaceReference(
        placeID: placeID, featureID: feature, name: name,
        latitude: latitude, longitude: longitude), seen.insert(feature.lowercased()).inserted
    else { continue }
    let result: PlacePopularTimes?
    var issue: String?
    do { result = try parsePlaceInfo(info, for: reference) } catch PopularTimesError.unavailable {
      result = nil
    } catch {
      result = nil
      issue = error.localizedDescription
    }
    matches.append(
      MapsSearchMatch(
        place: reference, address: address, popularTimes: result,
        parsingIssue: issue))
  }
  return matches
}

private let maximumResponseBytes = 5 * 1_024 * 1_024
private let placeOptionsPB = """
  !12m4!2m3!1i360!2i120!4i8!13m57!2m2!1i203!2i100!3m2!2i4!5b1!6m6!1m2!1i86!2i86!1m2!1i408!2i240!7m33!1m3!1e1!2b0!3e3!1m3!1e2!2b1!3e2!1m3!1e2!2b0!3e3!1m3!1e8!2b0!3e3!1m3!1e10!2b0!3e3!1m3!1e10!2b1!3e2!1m3!1e10!2b0!3e4!1m3!1e9!2b1!3e2!2b1!9b0!15m8!1m7!1m2!1m1!1e2!2m2!1i195!2i195!3i20!14m2!7e81!15i10112!15m108!1m26!13m9!2b1!3b1!4b1!6i1!8b1!9b1!14b1!20b1!25b1!18m15!3b1!4b1!5b1!6b1!13b1!14b1!17b1!21b1!22b1!30b1!32b1!33m1!1b1!34b1!36e2!10m1!8e3!11m1!3e1!17b1!20m2!1e3!1e6!24b1!25b1!26b1!27b1!29b1!30m1!2b1!36b1!37b1!39m3!2m2!2i1!3i1!43b1!52b1!54m1!1b1!55b1!56m1!1b1!61m2!1m1!1e1!65m5!3m4!1m3!1m2!1i224!2i298!72m22!1m8!2b1!5b1!7b1!12m4!1b1!2b1!4m1!1e1!4b1!8m10!1m6!4m1!1e1!4m1!1e3!4m1!1e4!3sother_user_google_review_posts__and__hotel_and_vr_partner_review_posts!6m1!1e1!9b1!89b1!90m2!1m1!1e2!98m3!1b1!2b1!3b1!103b1!113b1!114m3!1b1!2m1!1b1!117b1!122m1!1b1!126b1!127b1!128m1!1b1!21m0!22m1!1e81!30m8!3b1!6m2!1b1!2b1!7m2!1e3!2b1!9b1!34m5!7b1!10b1!14b1!15m1!1b0!37i801
  """

private func makePlacePB(for place: PlaceReference) -> String {
  let location: [PBField] = [
    .scalar(1, "s", place.featureID),
    .scalar(2, "s", place.name.replacingOccurrences(of: "!", with: " ")),
    .message(
      3,
      [
        .message(

          1,
          [
            .scalar(1, "d", "3464.2080474321833"),
            .scalar(2, "d", String(place.longitude)), .scalar(3, "d", String(place.latitude)),
          ]),
        .message(3, [.scalar(1, "i", "1024"), .scalar(2, "i", "768")]),
        .scalar(4, "f", "13.1"),
      ]),
    .message(
      4, [.scalar(3, "d", String(place.latitude)), .scalar(4, "d", String(place.longitude))]),
  ]
  let identity =
    place.knowledgeGraphID.map {
      [PBField.message(15, [.message(1, [.scalar(4, "s", $0)])])]
    } ?? []
  return PBField.message(1, location + identity).encoded + placeOptionsPB
}

private indirect enum PBField {
  case scalar(Int, String, String)
  case message(Int, [PBField])

  var tokenCount: Int {
    switch self {
    case .scalar: return 1
    case .message(_, let fields): return 1 + fields.reduce(0) { $0 + $1.tokenCount }
    }
  }

  var encoded: String {

    switch self {
    case .scalar(let number, let type, let value): return "!\(number)\(type)\(value)"
    case .message(let number, let fields):
      return "!\(number)m\(tokenCount - 1)" + fields.map(\.encoded).joined()
    }
  }
}

struct MapsSearchMatch: Identifiable, Sendable {
  let place: PlaceReference
  let address: String
  let popularTimes: PlacePopularTimes?
  let parsingIssue: String?
  var id: String { place.featureID.lowercased() }
}

enum MapsSearchError: LocalizedError {
  case emptyQuery
  var errorDescription: String? { "Enter a business name and city or street address." }
}

func makeMapsSearchRequest(query: String) throws -> URLRequest {
  let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !query.isEmpty, query.count <= 500 else { throw MapsSearchError.emptyQuery }
  var url = URLComponents()
  url.scheme = "https"
  url.host = "www.google.com"
  url.path = "/search"

  url.queryItems = [
    URLQueryItem(name: "tbm", value: "map"),
    URLQueryItem(name: "tch", value: "1"),
    URLQueryItem(name: "hl", value: "en"),
    URLQueryItem(name: "q", value: query),
    URLQueryItem(name: "pb", value: mapsSearchPB),
  ]
  guard let address = url.url else { throw PopularTimesError.invalidURL }
  var request = URLRequest(
    url: address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
  request.setValue(
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/54.0.2840.98 Safari/537.36",
    forHTTPHeaderField: "User-Agent")
  request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
  request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
  return request
}

func searchMaps(query: String, session: URLSession) async throws -> [MapsSearchMatch] {
  var request = try makeMapsSearchRequest(query: query)
  try attachMapsCookies(to: &request, from: session)
  let data = try await downloadMapsResponse(request, session: session)
  try Task.checkCancellation()
  return try parseMapsSearchResponse(data)
}

private let mapsSearchPB = """
  !4m12!1m3!1d4005.9771522653964!2d-122.42072974863942!3d37.8077459796541!2m3!1f0!2f0!3f0!3m2!1i1125!2i976!4f13.1!7i20!10b1!12m6!2m3!5m1!6e2!20e3!10b1!16b1!19m3!2m2!1i392!2i106!20m61!2m2!1i203!2i100!3m2!2i4!5b1!6m6!1m2!1i86!2i86!1m2!1i408!2i200!7m46!1m3!1e1!2b0!3e3!1m3!1e2!2b1!3e2!1m3!1e2!2b0!3e3!1m3!1e3!2b0!3e3!1m3!1e4!2b0!3e3!1m3!1e8!2b0!3e3!1m3!1e3!2b1!3e2!1m3!1e9!2b1!3e2!1m3!1e10!2b0!3e3!1m3!1e10!2b1!3e2!1m3!1e10!2b0!3e4!2b1!4b1!9b0!22m6!1sa9fVWea_MsX8adX8j8AE:1!2zMWk6Mix0OjExODg3LGU6MSxwOmE5ZlZXZWFfTXNYOGFkWDhqOEFFOjE!7e81!12e3!17sa9fVWea_MsX8adX8j8AE:564!18e15!24m15!2b1!5m4!2b1!3b1!5b1!6b1!10m1!8e3!17b1!24b1!25b1!26b1!30m1!2b1!36b1!26m3!2m2!1i80!2i92!30m28!1m6!1m2!1i0!2i0!2m2!1i458!2i976!1m6!1m2!1i1075!2i0!2m2!1i1125!2i976!1m6!1m2!1i0!2i0!2m2!1i1125!2i20!1m6!1m2!1i0!2i956!2m2!1i1125!2i976!37m1!1e81!42b1!47m0!49m1!3b1
  """

extension PlacePopularTimes {
  var displayTimeZone: TimeZone {
    timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
  }

  var timeZoneLabel: String {
    if let id = timeZoneIdentifier, TimeZone(identifier: id) != nil { return id }
    return "Device time zone: \(displayTimeZone.identifier)"
  }

  // start on Monday start on Sunday.
  func weekday(at date: Date = Date()) -> Weekday {

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = displayTimeZone
    let number = (calendar.component(.weekday, from: date) + 5) % 7 + 1
    return Weekday(rawValue: number)!
  }

  func hours(for day: Weekday) -> [HourPopularity] {
    days.first(where: { $0.weekday == day })?.hours.sorted { $0.hour < $1.hour } ?? []
  }
}

extension Weekday {
  var displayName: String {
    Calendar(identifier: .gregorian).weekdaySymbols[rawValue % 7]
  }
}

enum BusynessLabels {
  static func hour(_ hour: Int) -> String {
    let clockHour = hour % 12 == 0 ? 12 : hour % 12
    return "\(clockHour) \(hour < 12 ? "AM" : "PM")"
  }
}

extension PlacePopularTimes {
  var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = displayTimeZone
    return calendar
  }

  func usualScore(at date: Date) -> Int? {
    hours(for: weekday(at: date)).first { $0.hour == calendar.component(.hour, from: date) }?
      .busyness
  }

  func liveScore(at date: Date) -> Int? {
    guard date >= fetchedAt, date.timeIntervalSince(fetchedAt) < 3600 else { return nil }
    return currentBusyness
  }

  func liveDescription(at date: Date) -> String? {
    guard date >= fetchedAt, date.timeIntervalSince(fetchedAt) < 3600,
      let text = currentDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
      !text.isEmpty
    else { return nil }
    return text
  }

  func busynessSummary(for day: Weekday, hour: Int, at date: Date, includeLive: Bool = true)
    -> String
  {
    let entry = hours(for: day).first { $0.hour == hour }
    let returnedText = entry?.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let usual =
      returnedText.isEmpty
      ? entry.map { BusynessText.label($0.busyness, live: false) } : returnedText
    guard includeLive, day == weekday(at: fetchedAt),
      hour == calendar.component(.hour, from: fetchedAt),
      let current = liveDescription(at: date)
    else { return usual ?? "No data" }
    return current
  }

  func isBusierThanUsual(at date: Date) -> Bool {
    guard let current = liveScore(at: date) else { return false }
    if let usual = usualScore(at: fetchedAt) { return current > usual }
    return currentDescription?.localizedCaseInsensitiveContains("busier than usual") ?? false
  }
}

enum BusynessText {
  static func label(_ score: Int, live: Bool) -> String {
    switch score {
    case ..<20: return live ? "Quiet now" : "Usually quiet"
    case ..<45: return live ? "A little busy" : "Usually a little busy"
    case ..<75: return live ? "Busy now" : "Usually busy"
    default: return live ? "Very busy now" : "Usually very busy"
    }
  }
}
