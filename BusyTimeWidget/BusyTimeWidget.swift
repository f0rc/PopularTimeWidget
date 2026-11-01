import AppIntents
import SwiftUI
import WidgetKit

struct SavedWidgetPlace: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Location"
  static var defaultQuery = SavedWidgetPlaceQuery()
  let id: UUID
  let name: String
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct SavedWidgetPlaceQuery: EntityQuery {
  func entities(for identifiers: [UUID]) async throws -> [SavedWidgetPlace] {
    WidgetStorage.places().filter { identifiers.contains($0.id) }
      .map { SavedWidgetPlace(id: $0.id, name: $0.name) }
  }

  func suggestedEntities() async throws -> [SavedWidgetPlace] {
    WidgetStorage.places().map { SavedWidgetPlace(id: $0.id, name: $0.name) }
  }
}

struct BusyTimeConfiguration: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Location"
  static var description = IntentDescription("Choose a saved location.")
  @Parameter(title: "Location") var place: SavedWidgetPlace?
}

struct BusyTimeEntry: TimelineEntry {
  let date: Date
  let place: WidgetPlace?
  var preview = false

  var liveScore: Int? { place?.data?.liveScore(at: date) }
  var liveReading: PopularTimesLiveReading? {
    guard let data = place?.data else { return nil }
    return data.chartLiveReading(for: data.weekday(at: data.fetchedAt), at: date)
  }
  var score: Int? { liveScore ?? place?.data?.usualScore(at: date) }
  var busierThanUsual: Bool { place?.data?.isBusierThanUsual(at: date) ?? false }
  var status: String {
    guard let data = place?.data else { return "No data" }
    return data.busynessSummary(
      for: data.weekday(at: date),
      hour: data.calendar.component(.hour, from: date), at: date)
  }
}

struct BusyTimeProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> BusyTimeEntry {
    BusyTimeEntry(date: .now, place: .preview, preview: true)
  }

  func snapshot(for configuration: BusyTimeConfiguration, in context: Context) async
    -> BusyTimeEntry
  {
    BusyTimeEntry(
      date: .now, place: selected(configuration) ?? (context.isPreview ? .preview : nil))
  }

  func timeline(for configuration: BusyTimeConfiguration, in context: Context) async -> Timeline<
    BusyTimeEntry
  > {
    var place = selected(configuration)
    if let current = place, current.reference != nil,
      Date().timeIntervalSince(current.lastAttempt ?? .distantPast) >= 3600
    {
      place = await refresh(current)
    }
    let now = Date()
    let dates = timelineDates(now: now, data: place?.data)
    let refreshAt = nextRefreshDate(
      now: now, lastAttempt: place?.reference == nil ? nil : place?.lastAttempt)
    return Timeline(
      entries: dates.map { BusyTimeEntry(date: $0, place: place) },
      policy: .after(refreshAt))
  }

  func nextRefreshDate(now: Date, lastAttempt: Date?) -> Date {
    let due = (lastAttempt ?? now).addingTimeInterval(3600)
    return max(now.addingTimeInterval(300), min(due, now.addingTimeInterval(3600)))
  }

  private func selected(_ configuration: BusyTimeConfiguration) -> WidgetPlace? {
    let places = WidgetStorage.places()
    let selected: WidgetPlace?
    if let id = configuration.place?.id {
      selected = places.first { $0.id == id }
    } else {
      selected = places.first { $0.reference != nil } ?? places.first
    }
    return selected.map { WidgetStorage.cached($0) }
  }

  private func refresh(_ current: WidgetPlace) async -> WidgetPlace? {
    var updated = current
    updated.lastAttempt = .now
    do {
      guard let reference = current.reference else { return current }
      let cookies = try MapsSessionKeychain.load()
      let session = try makeAuthenticatedMapsSession(cookies: cookies)
      defer { session.invalidateAndCancel() }
      var request = try makePopularTimesRequest(for: reference)
      try attachMapsCookies(to: &request, from: session)
      let response = try await downloadMapsResponse(request, session: session)
      updated.data = try parsePopularTimesResponse(response, for: reference)
      try Task.checkCancellation()
      if try MapsSessionKeychain.encodeCookies(MapsSessionKeychain.load())
        == MapsSessionKeychain.encodeCookies(cookies)
      {
        let rotated = applicableMapsCookies(session.configuration.httpCookieStorage?.cookies ?? [])
        if hasMapsSessionCookies(rotated) { try MapsSessionKeychain.save(rotated) }
      }
    } catch {

    }
    guard let latest = WidgetStorage.places().first(where: { $0.id == current.id }) else {
      return nil
    }
    guard latest.reference?.placeID == current.reference?.placeID else {
      return WidgetStorage.cached(latest)
    }
    let newest = WidgetStorage.cached(latest)
    var merged = latest
    merged.data =
      (newest.data?.fetchedAt ?? .distantPast) > (updated.data?.fetchedAt ?? .distantPast)
      ? newest.data : updated.data
    merged.lastAttempt = max(
      newest.lastAttempt ?? .distantPast, updated.lastAttempt ?? .distantPast)
    WidgetStorage.saveCache(merged)
    return merged
  }

  func timelineDates(now: Date, data: PlacePopularTimes?) -> [Date] {
    let calendar = data?.calendar ?? Calendar.current
    let nextHour =
      calendar.nextDate(
        after: now, matching: DateComponents(minute: 0, second: 0),
        matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
    var dates = (0..<24).map { nextHour.addingTimeInterval(Double($0) * 3600) }
    if let data, data.currentBusyness != nil {
      let expiry = data.fetchedAt.addingTimeInterval(3600)
      if expiry > now {
        dates.removeAll { abs($0.timeIntervalSince(expiry)) < 300 }
        dates.append(expiry)
      }
    }
    return [now] + dates.sorted()
  }
}

struct BusyTimeWidgetView: View {
  let entry: BusyTimeEntry
  let family: WidgetFamily
  @Environment(\.widgetRenderingMode) private var renderingMode
  @Environment(\.colorScheme) private var colorScheme

  private var tint: Color { entry.place?.color.color ?? .purple }
  private var ink: Color { renderingMode == .fullColor ? GlassPalette.ink : .primary }
  private var secondaryInk: Color {
    renderingMode == .fullColor ? GlassPalette.heading : .primary.opacity(0.75)
  }
  private var isHome: Bool { family == .systemSmall || family == .systemMedium }
  private var contentInsets: EdgeInsets {
    isHome ? EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16) : EdgeInsets()
  }
  private var name: String { entry.place?.name ?? "Choose a location" }

  var body: some View {
    Group {
      switch family {
      case .accessoryCircular:
        gauge
          .accessibilityLabel(name)
      case .accessoryRectangular:
        HStack(spacing: 10) {
          gauge.frame(width: 48)
          VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.headline).lineLimit(1)
            Text(entry.status).font(.caption).lineLimit(2)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      default:
        homeChart
          .foregroundStyle(ink)
          .environment(\.colorScheme, renderingMode == .fullColor ? .light : colorScheme)
      }
    }
    .fontDesign(.rounded)
    .padding(contentInsets)
    .containerBackground(for: .widget) {
      if family == .systemSmall || family == .systemMedium {
        AutoGlassBackground(tint: tint, cornerRadius: 24)
      }
    }
    .widgetURL(URL(string: "populartime://location/\(entry.place?.id.uuidString ?? "")"))
    .redacted(reason: entry.preview ? .placeholder : [])
  }

  private var homeChart: some View {
    VStack(alignment: .leading, spacing: family == .systemSmall ? 3 : 5) {
      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(
            family == .systemSmall
              ? .system(size: 14, weight: .semibold, design: .rounded) : .headline
          )
          .lineLimit(family == .systemSmall ? 1 : 2)
          .minimumScaleFactor(0.85)
        Text(entry.place == nil ? "Open app" : entry.status)
          .font(
            family == .systemSmall
              ? .system(size: 11, weight: .medium, design: .rounded) : .footnote
          )
          .foregroundStyle(secondaryInk)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
      }
      if let data = entry.place?.data {
        PopularTimesBars(
          data: data, day: data.weekday(at: entry.date),
          selectedHour: data.calendar.component(.hour, from: entry.date),
          color: renderingMode == .fullColor ? GlassPalette(tint).foreground : .primary,
          tickStride: family == .systemSmall ? 6 : 3,
          axisColor: secondaryInk,
          scalesToDay: family == .systemSmall,
          topInset: family == .systemSmall ? 0 : 4,
          liveReading: data.chartLiveReading(for: data.weekday(at: entry.date), at: entry.date),
          liveColor: renderingMode == .fullColor ? nil : .primary
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var gauge: some View {
    Gauge(value: Double(entry.score ?? 0), in: 0...100) {
      Image(systemName: entry.liveScore == nil ? "person.2.fill" : "dot.radiowaves.left.and.right")
    } currentValueLabel: {
      VStack(spacing: 0) {
        Text(entry.score.map(String.init) ?? "—")
          .font(
            .system(size: entry.liveReading == nil ? 22 : 18, weight: .semibold, design: .rounded)
          )
          .minimumScaleFactor(0.7)
        if let reading = entry.liveReading {
          Text(reading.label)
            .font(.system(size: 7, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
      }
    }
    .gaugeStyle(.accessoryCircular)
    .tint(family == .systemMedium ? ink : .primary)
    .widgetAccentable()
    .accessibilityLabel("Busyness")
    .accessibilityValue(
      entry.score.map { "\($0) out of 100, \(entry.liveScore == nil ? "typical" : "live")" }
        ?? "Unavailable")
  }
}

private struct BusyTimeWidgetContent: View {
  let entry: BusyTimeEntry
  @Environment(\.widgetFamily) private var family

  var body: some View { BusyTimeWidgetView(entry: entry, family: family) }
}

@main
struct BusyTimeWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: WidgetStorage.kind, intent: BusyTimeConfiguration.self,
      provider: BusyTimeProvider()
    ) { entry in
      BusyTimeWidgetContent(entry: entry)
    }
    .contentMarginsDisabled()
    .configurationDisplayName("Busy time")
    .description("Your location's busy level.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
  }
}

extension WidgetPlace {
  static var preview: WidgetPlace {
    let data = PlacePopularTimes(
      placeID: "preview", name: "Coffee shop", address: "",
      timeZoneIdentifier: nil,
      days: Weekday.allCases.map { day in
        PopularTimesDay(
          weekday: day,
          hours: (0..<24).map {
            HourPopularity(
              hour: $0,
              busyness: [
                8, 6, 5, 4, 5, 10, 18, 30, 45, 55, 62, 70, 78, 84, 92, 100, 88, 72, 55, 40, 28, 20,
                15, 10,
              ][$0], description: "")
          })
      }, currentBusyness: 42, currentDescription: nil, fetchedAt: Date().addingTimeInterval(-60))
    return WidgetPlace(
      id: UUID(), name: "Coffee shop", color: WidgetColor(.purple),
      reference: nil, data: data, lastAttempt: .now)
  }
}

#Preview(as: .systemSmall) {
  BusyTimeWidget()
} timeline: {
  BusyTimeEntry(date: .now, place: .preview)
}

#Preview(as: .systemMedium) {
  BusyTimeWidget()
} timeline: {
  BusyTimeEntry(date: .now, place: .preview)
}

#Preview(as: .accessoryCircular) {
  BusyTimeWidget()
} timeline: {
  BusyTimeEntry(date: .now, place: .preview)
}

#Preview(as: .accessoryRectangular) {
  BusyTimeWidget()
} timeline: {
  BusyTimeEntry(date: .now, place: .preview)
}
