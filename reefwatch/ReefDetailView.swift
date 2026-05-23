import SwiftUI
import Charts

struct ReefDetailView: View {
    let reef: RankedReef

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statRow
                Divider()
                chartSection
                Divider()
                scaleSection
            }
            .padding(16)
        }
        .navigationTitle(reef.station.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reef.station.region)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Text(reef.alertLevel.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .foregroundStyle(.white)
                    .background(reef.alertLevel.color)
                    .clipShape(Capsule())
                Spacer()
                Text(String(format: "%.4f°, %.4f°", reef.station.latitude, reef.station.longitude))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Stat row

    private var statRow: some View {
        HStack(spacing: 16) {
            stat("DHW",    reef.currentDHW.isNaN ? "—" : String(format: "%.1f", reef.currentDHW),       "°C·wks")
            stat("Streak", streakValueText, reef.streakWeeks == 1 ? "wk" : "wks")
            stat("SSTA",   reef.currentSSTAnomaly.isNaN ? "—" : String(format: "%+.2f", reef.currentSSTAnomaly), "°C")
        }
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var streakValueText: String {
        let suffix = reef.streakIsMaxed ? "+" : ""
        if reef.streakWeeks == 0 || reef.streakLevel == .noStress {
            return "—"
        }
        return "\(reef.streakWeeks)\(suffix)"
    }

    // MARK: - Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("120-day history")
                .font(.headline)

            Chart {
                ForEach(reef.history, id: \.date) { sample in
                    LineMark(
                        x: .value("Date", sample.date),
                        y: .value("DHW",  sample.dhw)
                    )
                    .foregroundStyle(by: .value("Series", "DHW (°C·wks)"))
                    .interpolationMethod(.monotone)
                }

                ForEach(reef.history, id: \.date) { sample in
                    LineMark(
                        x: .value("Date",  sample.date),
                        y: .value("SSTA",  sample.sstAnomaly)
                    )
                    .foregroundStyle(by: .value("Series", "SST anomaly (°C)"))
                    .interpolationMethod(.monotone)
                }

                // NOAA alert-level threshold reference lines.
                ForEach([4.0, 8.0, 12.0, 16.0, 20.0], id: \.self) { y in
                    RuleMark(y: .value("Threshold", y))
                        .foregroundStyle(.gray.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .trailing, alignment: .leading) {
                            Text("Alert \(alertIndex(for: y))")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .chartForegroundStyleScale([
                "DHW (°C·wks)":     Color.red,
                "SST anomaly (°C)": Color.blue
            ])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 240)
        }
    }

    private func alertIndex(for dhw: Double) -> Int {
        switch dhw {
        case 4:  return 1
        case 8:  return 2
        case 12: return 3
        case 16: return 4
        case 20: return 5
        default: return 0
        }
    }

    // MARK: - Scale

    private var scaleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current position on NOAA scale")
                .font(.headline)
            DHWGradientScaleView(currentDHW: reef.currentDHW)
                .frame(height: 56)
        }
    }
}
