//
//  PopularTimeChart.swift
//  PopularTimeWidget
//
//  Created by xbox on 10/27/26.
//

import SwiftUI

struct PopularTimesChart: View {
  let tint: Color
  let values: [Double]

  @State private var selectedDay = 1
  @State private var selectedHour = 21

  private let days = [
    "MON", "TUE", "WED", "THU",
    "FRI", "SAT", "SUN",
  ]

  // chart starts at 6 AM.
  // each index 1 hr
  private let timeTicks: [(index: Int, label: String)] = [
    (0, "6a"),
    (3, "9a"),
    (6, "12p"),
    (9, "3p"),
    (12, "6p"),
    (15, "9p"),
    (18, "12a"),
    (21, "3a"),
  ]

  private var chartColor: Color {
    GlassPalette(tint).foreground
  }

  private var adjustedValues: [Double] {
    let multipliers: [Double] = [
      0.8, 1.0, 1.1, 0.95,
      1.2, 1.35, 0.9,
    ]

    let multiplier = multipliers[selectedDay]

    return values.map {
      min(100, max(0, $0 * multiplier))
    }
  }

  private var selectedIndex: Int {
    (selectedHour - 6 + 24) % 24
  }

  private var selectedValue: Double {
    guard adjustedValues.indices.contains(selectedIndex)
    else { return 0 }
    return adjustedValues[selectedIndex]
  }

  private var selectedTimeText: String {
    let hour = selectedHour % 24
    let displayHour =
      hour % 12 == 0
      ? 12
      : hour % 12

    return "\(displayHour) \(hour >= 12 ? "PM" : "AM")"
  }

  private var activityDescription: String {
    switch selectedValue {
    case ..<20:
      return "Not too busy"
    case ..<45:
      return "Usually a little busy"
    case ..<75:
      return "Usually busy"
    default:
      return "Usually very busy"
    }
  }

  var body: some View {
    VStack(spacing: 15) {
      HStack(spacing: 2) {
        ForEach(0..<7, id: \.self) { index in
          Button {
            withAnimation(.easeInOut(duration: 0.2)) {
              selectedDay = index
            }
          } label: {
            Text(days[index])
              .font(.system(size: 11, weight: .bold, design: .rounded))
              .foregroundStyle(selectedDay == index ? .white : GlassPalette.ink.opacity(0.7))
              .frame(maxWidth: .infinity, minHeight: 36)
              .background {
                if selectedDay == index {
                  Capsule().fill(GlassPalette.ink)
                }
              }
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(selectedDay == index ? .isSelected : [])
        }
      }

      HStack(spacing: 6) {
        Image(systemName: "person.2.fill")
          .foregroundStyle(chartColor)

        Text("\(selectedTimeText):")
          .fontWeight(.semibold)
          .foregroundStyle(chartColor)

        Text(activityDescription)
          .foregroundStyle(.black.opacity(0.7))
          .lineLimit(1)
          .minimumScaleFactor(0.75)

        Spacer(minLength: 0)
      }
      .font(.system(.footnote, design: .rounded))
      .padding(.top, 3)

      GeometryReader { geometry in
        let width = geometry.size.width
        let chartHeight: CGFloat = 114
        let axisY: CGFloat = chartHeight
        let step = width / 24
        let barWidth = step * 0.64

        ZStack(alignment: .topLeading) {

          // grid
          ForEach(1..<4, id: \.self) { line in
            Path { path in
              let y = chartHeight * CGFloat(line) / 4

              path.move(
                to: CGPoint(x: 0, y: y)
              )
              path.addLine(
                to: CGPoint(x: width, y: y)
              )
            }
            .stroke(
              .black.opacity(0.07),
              lineWidth: 0.5
            )
          }

          // bars
          ForEach(

            Array(adjustedValues.prefix(24).enumerated()),
            id: \.offset
          ) { index, value in
            let hour = (index + 6) % 24
            let isSelected = selectedHour == hour

            let x = (CGFloat(index) + 0.5) * step
            let barHeight = max(
              4,
              chartHeight * CGFloat(value / 100)
            )

            Button {
              withAnimation(

                .easeInOut(duration: 0.2)
              ) {
                selectedHour = hour
              }
            } label: {
              RoundedRectangle(cornerRadius: 5)
                .fill(
                  chartColor.opacity(
                    isSelected ? 1 : 0.58
                  )
                )
                .frame(
                  width: barWidth,
                  height: barHeight
                )
            }
            .buttonStyle(.plain)
            .frame(
              width: step,
              height: chartHeight,
              alignment: .bottom
            )
            .position(
              x: x,
              y: chartHeight / 2
            )
          }

          // dotted guide
          Path { path in
            let x = (CGFloat(selectedIndex) + 0.5) * step

            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(
              to: CGPoint(x: x, y: axisY)
            )
          }
          .stroke(
            chartColor.opacity(0.4),
            style: StrokeStyle(
              lineWidth: 1,
              dash: [2, 3]
            )
          )
          .allowsHitTesting(false)

          // bottom axis
          Path { path in

            path.move(
              to: CGPoint(x: 0, y: axisY)
            )
            path.addLine(
              to: CGPoint(x: width, y: axisY)
            )
          }
          .stroke(
            .black.opacity(0.5),
            lineWidth: 1
          )

          // ticks and labels
          ForEach(timeTicks, id: \.index) { tick in
            let x = (CGFloat(tick.index) + 0.5) * step

            Path { path in
              path.move(
                to: CGPoint(x: x, y: axisY)
              )
              path.addLine(
                to: CGPoint(x: x, y: axisY + 4)
              )
            }
            .stroke(
              .black.opacity(0.5),
              lineWidth: 1
            )

            Text(tick.label)
              .font(.system(size: 11, weight: .medium, design: .rounded))
              .foregroundStyle(.black.opacity(0.6))
              .fixedSize()
              .position(
                x: x,
                y: axisY + 19
              )
          }
        }
      }
      .frame(height: 145)
    }
  }
}

#Preview {
  PopularTimesChart(tint: .red, values: [12, 12, 12])
}
