import SwiftUI

struct ReefPanelView: View {
    let rank: Int
    let reef: RankedReef
    /// Minimum tile height. The panel grows above this when its content (stacked
    /// bars or the huge-number layout) needs more room.
    var minPanelHeight: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme
    @State private var showInfoSheet = false

    var body: some View {
        Group {
            if reef.currentDHW > 50 {
                hugeNumberContent
            } else {
                standardContent
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: minPanelHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tileBackground)
        )
        .overlay(borderOverlay)
        // .drawingGroup() flattens the panel — gradients, text, border — into a
        // single GPU bitmap so the .shadow() blur doesn't have to re-render the
        // whole view tree every scroll frame. Applied only when there's an
        // actual glow, since drawingGroup has its own memory + first-render
        // cost and standard panels don't need it.
        .glow(color: glowColor, radius: glowRadius)
        .foregroundStyle(textForegroundStyle)
        .sheet(isPresented: $showInfoSheet) {
            AlertLevelReferenceSheet()
        }
    }

    // MARK: - Content variants

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                RankBadge(rank: rank)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(reef.station.name)
                            .font(.headline)
                            .lineLimit(1)
                        if reef.station.source.isGriddedEstimate {
                            IndirectDataDot(blackTile: isBlackTile)
                        }
                    }
                    Text(reef.station.region)
                        .font(.caption)
                        .foregroundStyle(secondaryStyle)
                }
                Spacer()
                AlertChip(level: reef.alertLevel, blackTile: isBlackTile) {
                    showInfoSheet = true
                }
            }

            HStack(alignment: .top, spacing: 16) {
                MetricBlock(label: "DHW",  value: formatDHW(reef.currentDHW),       unit: "°C·wks", secondaryStyle: secondaryStyle)
                MetricBlock(label: "SSTA", value: formatSSTA(reef.currentSSTAnomaly), unit: "°C",   secondaryStyle: secondaryStyle)
                StreakBlock(reef: reef, secondaryStyle: secondaryStyle)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("NOAA Bleaching Alert Scale")
                    .font(.caption2)
                    .foregroundStyle(secondaryStyle)
                DHWGradientScaleView(currentDHW: reef.currentDHW)
            }
        }
    }

    private var hugeNumberContent: some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(alignment: .top) {
                RankBadge(rank: rank)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reef.station.name).font(.headline).lineLimit(1)
                    Text(reef.station.region).font(.caption).foregroundStyle(secondaryStyle)
                }
                Spacer()
                Button { showInfoSheet = true } label: {
                    Image(systemName: "info.circle").font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.orange)
            }
            Text(reef.currentDHW.isNaN ? "—" : String(format: "%.0f", reef.currentDHW))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(Color.red)
                .padding(.top, 6)
            Text("Degree Heating Weeks")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.orange)
            Text("Streak: \(streakDescription)")
                .font(.system(size: 12))
                .foregroundStyle(Color.orange.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Streak text

    /// Used by the DHW > 50 layout; the metric row uses StreakBlock directly.
    private var streakDescription: String {
        if reef.hasNaN { return "No data" }
        let weeks = reef.streakWeeks
        let suffix = reef.streakIsMaxed ? "+" : ""
        if weeks == 0 || reef.streakLevel == .noStress {
            return "No active stress"
        }
        let unit = weeks == 1 ? "week" : "weeks"
        return "\(weeks)\(suffix) \(unit) w/ thermal stress"
    }

    // MARK: - Value formatters

    private func formatDHW(_ v: Double) -> String {
        v.isNaN ? "—" : String(format: "%.1f", v)
    }

    private func formatSSTA(_ v: Double) -> String {
        v.isNaN ? "—" : String(format: "%+.1f", v)
    }

    // MARK: - Tile styling

    private var isBlackTile: Bool { reef.currentDHW >= 30 }
    private var isOrangeTile: Bool { reef.currentDHW >= 20 && !isBlackTile }

    private var tileBackground: Color {
        if isBlackTile { return Color.black }
        // Alert 5 with DHW < 30 keeps the standard background; the alert is
        // signaled by the glowing border instead of a colored fill.
        return Color(.secondarySystemBackground)
    }

    private var textForegroundStyle: Color {
        if isBlackTile { return Color.orange }
        return Color.primary
    }

    private var secondaryStyle: Color {
        if isBlackTile { return Color.orange.opacity(0.75) }
        return Color.secondary
    }

    /// Border color for Alert 1-4 tiles, plus an orange accent for the black tile
    /// and for Alert 5 reefs with DHW < 30 (which use a glowing border in place
    /// of a colored background).
    private var borderOverlay: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if let color = borderColor {
            return AnyView(shape.stroke(color, lineWidth: borderWidth))
        }
        return AnyView(shape.stroke(Color.black.opacity(0.06), lineWidth: 1))
    }

    private var borderColor: Color? {
        if isBlackTile  { return Color.orange }
        if isOrangeTile { return Color.orange }  // glowing border for 20 ≤ DHW < 30
        switch reef.alertLevel {
        case .alert1: return Color(red: 1.00, green: 0.90, blue: 0.20)   // yellow
        case .alert2: return Color(red: 1.00, green: 0.65, blue: 0.10)   // yellow-orange
        case .alert3: return Color(red: 1.00, green: 0.45, blue: 0.05)   // orange
        case .alert4: return Color(red: 0.95, green: 0.10, blue: 0.10)   // red
        default:      return nil
        }
    }

    private var borderWidth: CGFloat {
        // ~1.5 pt for Alert 1-4. Heavier 2.5 pt for the high-stress cases
        // (Alert 5 / DHW ≥ 30) so the orange edge reads strongly.
        (isBlackTile || isOrangeTile) ? 2.5 : 1.5
    }

    private var glowColor: Color {
        // Faint orange glow for the black-tile case in dark mode (so the panel
        // doesn't disappear into OLED) and for Alert 5 / DHW < 30 in either mode
        // (so the orange edge has visible spill instead of just a hairline).
        if isBlackTile && colorScheme == .dark {
            return Color.orange.opacity(0.45)
        }
        if isOrangeTile {
            return Color.orange.opacity(0.40)
        }
        return Color.clear
    }

    private var glowRadius: CGFloat {
        if isBlackTile && colorScheme == .dark { return 6 }
        if isOrangeTile { return 5 }
        return 0
    }
}

// MARK: - Subviews

private struct RankBadge: View {
    let rank: Int
    var body: some View {
        Text("#\(rank)")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(rankColor))
    }
    private var rankColor: Color {
        switch rank {
        case 1:  return Color(red: 0.75, green: 0.10, blue: 0.10)
        case 2:  return Color(red: 0.85, green: 0.35, blue: 0.10)
        case 3:  return Color(red: 0.90, green: 0.55, blue: 0.10)
        default: return Color(.systemGray)
        }
    }
}

private struct MetricBlock: View {
    let label: String
    let value: String
    let unit: String
    let secondaryStyle: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(secondaryStyle)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(unit).font(.caption2).foregroundStyle(secondaryStyle)
            }
        }
    }
}

/// Inline streak metric: shows "{rounded DHW} DHW for {weeks} wks" in a compact
/// MetricBlock-style layout. Falls back to "—" for NaN reefs or No Stress.
private struct StreakBlock: View {
    let reef: RankedReef
    let secondaryStyle: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Streak")
                .font(.caption2)
                .foregroundStyle(secondaryStyle)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(headValue)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(tailText)
                    .font(.caption2)
                    .foregroundStyle(secondaryStyle)
            }
        }
    }

    private var hasStreak: Bool {
        !reef.hasNaN && reef.streakWeeks > 0 && reef.streakLevel != .noStress
    }

    private var headValue: String {
        if reef.hasNaN { return "—" }
        if !hasStreak  { return "—" }
        let suffix = reef.streakIsMaxed ? "+" : ""
        return "\(reef.streakWeeks)\(suffix)"
    }

    private var tailText: String {
        if reef.hasNaN { return "no data" }
        if !hasStreak  { return "no streak" }
        let unit = reef.streakWeeks == 1 ? "week" : "weeks"
        return "\(unit) w/ thermal stress"
    }
}

/// Tiny gray circle shown next to the station name when its source samples a
/// single grid pixel rather than using NOAA's polygon aggregation. Signals
/// "this number is estimated, not directly measured."
private struct IndirectDataDot: View {
    let blackTile: Bool
    var body: some View {
        Circle()
            .fill(blackTile ? Color.orange.opacity(0.85) : Color.secondary)
            .frame(width: 7, height: 7)
            .help("Estimated from a single 5 km grid pixel — not a NOAA polygon-aggregated measurement.")
            .accessibilityLabel("Estimated value")
    }
}

private struct AlertChip: View {
    let level: NOAAAlertLevel
    let blackTile: Bool
    var onInfoTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onInfoTap?()
        } label: {
            HStack(spacing: 4) {
                Text(level.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(level == .noStress ? Color.primary : Color.white)
            .background(chipColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(onInfoTap == nil)
    }
    private var chipColor: Color {
        level == .noStress ? Color(.systemGray5) : level.color
    }
}

// MARK: - Alert-level reference sheet

/// Shown when the user taps the (i) button next to the streak line.
/// Mirrors NOAA Coral Reef Watch's published stress-level table.
struct AlertLevelReferenceSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let id = UUID()
        let level: NOAAAlertLevel
        let definition: String
        let risk: String
    }

    private let rows: [Row] = [
        .init(level: .noStress, definition: "HotSpot ≤ 0",                          risk: "No Bleaching"),
        .init(level: .watch,    definition: "0 < HotSpot < 1",                      risk: "—"),
        .init(level: .warning,  definition: "HotSpot ≥ 1 and 0 < DHW < 4",          risk: "Risk of Possible Bleaching"),
        .init(level: .alert1,   definition: "HotSpot ≥ 1 and 4 ≤ DHW < 8",          risk: "Risk of Reef-Wide Bleaching"),
        .init(level: .alert2,   definition: "HotSpot ≥ 1 and 8 ≤ DHW < 12",         risk: "Risk of Reef-Wide Bleaching with Mortality of Heat-Sensitive Corals"),
        .init(level: .alert3,   definition: "HotSpot ≥ 1 and 12 ≤ DHW < 16",        risk: "Risk of Multi-Species Mortality"),
        .init(level: .alert4,   definition: "HotSpot ≥ 1 and 16 ≤ DHW < 20",        risk: "Risk of Severe, Multi-Species Mortality (> 50%)"),
        .init(level: .alert5,   definition: "HotSpot ≥ 1 and DHW ≥ 20",             risk: "Risk of Near-Complete Mortality (> 80%)")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Rectangle()
                                    .fill(row.level.color)
                                    .frame(width: 14, height: 14)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                Text(row.level.rawValue)
                                    .font(.headline)
                            }
                            Text(row.definition)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(row.risk)
                                .font(.footnote)
                        }
                        .padding(.bottom, 4)
                        Divider()
                    }
                    Text("DHW = Degree Heating Weeks (°C·weeks). HotSpot = SST above the local Maximum Monthly Mean. Definitions follow NOAA Coral Reef Watch's published bleaching-alert scale.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .navigationTitle("NOAA Stress Levels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Wow") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Glow modifier

private extension View {
    /// Apply an orange glow shadow only when `radius > 0`, and rasterize the
    /// view into a single GPU bitmap before the shadow runs. Without this, the
    /// shadow has to re-render the whole gradient-and-text view tree every
    /// scroll frame, which tanks scroll performance on Alert 5 panels.
    @ViewBuilder
    func glow(color: Color, radius: CGFloat) -> some View {
        if radius > 0 {
            self
                .drawingGroup()
                .shadow(color: color, radius: radius)
        } else {
            self
        }
    }
}
