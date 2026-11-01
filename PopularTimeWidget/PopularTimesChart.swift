import Charts
import SwiftUI

struct PopularTimesChart: View {
  let tint: Color
  let data: PlacePopularTimes
  let showsLive: Bool
  @State private var selectedDay: Weekday
  @State private var selectedPosition: Double?

  init(tint: Color, data: PlacePopularTimes, showsLive: Bool = true) {
    self.tint = tint
    self.data = data
    self.showsLive = showsLive
    _selectedDay = State(initialValue: data.weekday())
  }

  private var chartColor: Color { GlassPalette(tint).foreground }
  private var selectedHour: Int {
    if let selectedPosition { return (min(23, max(0, Int(selectedPosition.rounded()))) + 6) % 24 }
    return data.calendar.component(.hour, from: Date())
  }

  var body: some View {
    VStack(spacing: 15) {
      HStack(spacing: 2) {
        ForEach(Weekday.allCases, id: \.rawValue) { day in
          Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedDay = day }
          } label: {
            Text(String(day.displayName.prefix(3)).uppercased())
              .font(.system(size: 11, weight: .bold, design: .rounded))
              .foregroundStyle(selectedDay == day ? .white : GlassPalette.ink.opacity(0.7))
              .frame(maxWidth: .infinity, minHeight: 36)
              .background {
                if selectedDay == day { Capsule().fill(GlassPalette.ink) }
              }
          }
          .buttonStyle(.plain)
          .accessibilityLabel(day.displayName)
          .accessibilityAddTraits(selectedDay == day ? .isSelected : [])
        }
      }

      TimelineView(.periodic(from: .now, by: 60)) { context in
        HStack(spacing: 6) {
          Image(systemName: "person.2.fill")
          Text(BusynessLabels.hour(selectedHour) + ":").fontWeight(.semibold)
          Text(
            data.busynessSummary(
              for: selectedDay, hour: selectedHour, at: context.date, includeLive: showsLive)
          )
          .foregroundStyle(GlassPalette.ink)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
          Spacer(minLength: 0)
        }
        .font(.system(.footnote, design: .rounded))
        .foregroundStyle(chartColor)
      }

      TimelineView(.periodic(from: .now, by: 60)) { context in
        PopularTimesBars(
          data: data, day: selectedDay, selectedHour: selectedHour, color: chartColor,
          liveReading: showsLive ? data.chartLiveReading(for: selectedDay, at: context.date) : nil
        )
        .chartXSelection(value: $selectedPosition)
      }
      .frame(height: 142)
    }
  }

}

struct PopularTimesBars: View {
  @AppStorage(WidgetStorage.liveColorKey, store: WidgetStorage.defaults)
  private var liveColorData = Data()
  let data: PlacePopularTimes
  let day: Weekday
  let selectedHour: Int
  let color: Color
  var tickStride = 3
  var axisColor: Color = GlassPalette.heading
  var scalesToDay = false
  var topInset: CGFloat = 4
  var liveReading: PopularTimesLiveReading?
  var liveColor: Color?

  private var hours: [HourPopularity] { data.hours(for: day) }
  private var chartCeiling: Int {
    let current = liveReading?.value ?? 0
    if scalesToDay {
      let peak = max(current, hours.map(\.busyness).max() ?? 100)
      return max(10, Int((Double(peak) * 1.25).rounded(.up)))
    }
    return 100
  }
  private func position(_ hour: Int) -> Int { (hour - 6 + 24) % 24 }

  var body: some View {
    Chart {
      ForEach(hours, id: \.hour) { hour in
        RectangleMark(
          xStart: .value("Hour", Double(position(hour.hour)) - 0.325),
          xEnd: .value("Hour", Double(position(hour.hour)) + 0.325),
          yStart: .value("Busyness", 0),
          yEnd: .value("Busyness", hour.busyness)
        )
        .foregroundStyle(color.opacity(hour.hour == selectedHour ? 1 : 0.55))
        .cornerRadius(3)
        .accessibilityLabel(BusynessLabels.hour(hour.hour))
        .accessibilityValue("\(hour.busyness) out of 100")
      }
      RuleMark(x: .value("Selected hour", position(selectedHour)))
        .foregroundStyle(color.opacity(0.4))
        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
        .accessibilityHidden(true)

    }
    .chartXScale(domain: -0.5...23.5)
    .chartYScale(domain: 0...chartCeiling)
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartOverlay { proxy in
      GeometryReader { geometry in
        if let anchor = proxy.plotFrame {
          let plot = geometry[anchor]
          ForEach(Array(stride(from: 0, to: 24, by: tickStride)), id: \.self) { index in
            if let x = proxy.position(forX: Double(index)) {
              Text(shortHour((index + 6) % 24))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(axisColor)
                .fixedSize()
                .position(x: plot.minX + x, y: plot.maxY + 10)
            }
          }
        }
        if let reading = liveReading, let anchor = proxy.plotFrame,
          let centerX = proxy.position(forX: Double(position(reading.hour))),
          let leftX = proxy.position(forX: Double(position(reading.hour)) - 0.325),
          let rightX = proxy.position(forX: Double(position(reading.hour)) + 0.325),
          let baseY = proxy.position(forY: 0),
          let valueY = proxy.position(forY: reading.value)
        {
          let plot = geometry[anchor]
          let top = max(0, min(plot.height, valueY))
          let bottom = max(0, min(plot.height, baseY))
          let height = reading.value == 0 ? CGFloat(1.5) : max(0, bottom - top)

          RoundedRectangle(cornerRadius: 3)
            .fill((liveColor ?? WidgetStorage.liveBarColor(from: liveColorData)).opacity(0.85))
            .frame(width: max(1, rightX - leftX), height: height)
            .position(
              x: plot.minX + centerX,
              y: plot.minY + (reading.value == 0 ? bottom - height / 2 : (top + bottom) / 2)
            )
            .accessibilityLabel("Current busyness at " + BusynessLabels.hour(reading.hour))
            .accessibilityValue(
              "\(reading.value) out of 100"
                + (reading.difference.map { ", \($0) points compared with usual" } ?? ""))
        }
      }
      .allowsHitTesting(false)
    }
    .overlay {
      if hours.isEmpty && liveReading == nil {
        Text("No data for this day")
          .font(.caption)
          .foregroundStyle(axisColor)
      }
    }
    .padding(.bottom, 20)
    .padding(.horizontal, 4)
    .padding(.top, topInset)
  }

  private func shortHour(_ hour: Int) -> String {
    "\(hour % 12 == 0 ? 12 : hour % 12)\(hour < 12 ? "a" : "p")"
  }
}

struct PopularTimesLiveReading {
  let hour: Int
  let value: Int
  let usual: Int?

  var difference: Int? { usual.map { value - $0 } }
  var label: String {
    guard let difference else { return "Live \(value)" }
    if difference == 0 { return "Live · usual" }
    return "Live \(difference > 0 ? "+" : "")\(difference)"
  }
}

extension PlacePopularTimes {
  func chartLiveReading(for day: Weekday, at date: Date) -> PopularTimesLiveReading? {
    guard let value = liveScore(at: date), weekday(at: fetchedAt) == day else { return nil }
    return PopularTimesLiveReading(
      hour: calendar.component(.hour, from: fetchedAt),
      value: value, usual: usualScore(at: fetchedAt))
  }
}
