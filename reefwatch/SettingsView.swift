import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var viewModel: ReefRankingViewModel

    @AppStorage(AppSettings.Key.daysBack)                private var daysBack: Int = 120
    @AppStorage(AppSettings.Key.autoExtendCapDays)       private var autoExtendCapDays: Int = 730
    @AppStorage(AppSettings.Key.preferredMaxConcurrency) private var preferredMaxConcurrency: Int = 16
    @AppStorage(AppSettings.Key.sortMode)                private var sortModeRaw: String = SortMode.byDHW.rawValue
    @AppStorage(AppSettings.Key.enabledDataSources)      private var enabledSourcesCSV: String = DataSource.regionalVirtualStations.rawValue

    private let thresholdOptions: [(label: String, value: Double)] = [
        ("Warning (any DHW)",  0.01),
        ("Alert Level 1 (≥ 4)",  4),
        ("Alert Level 2 (≥ 8)",  8),
        ("Alert Level 3 (≥ 12)", 12),
        ("Alert Level 4 (≥ 16)", 16),
        ("Alert Level 5 (≥ 20)", 20)
    ]

    private let daysBackOptions: [Int] = [60, 90, 120, 180, 365]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Threshold alerts", isOn: Binding(
                        get: { notifications.isEnabled },
                        set: { newValue in Task { await notifications.setEnabled(newValue) } }
                    ))

                    if notifications.isEnabled {
                        Picker("When passing", selection: $notifications.thresholdDHW) {
                            ForEach(thresholdOptions, id: \.value) { opt in
                                Text(opt.label).tag(opt.value)
                            }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text(footerText)
                }

                Section {
                    Picker("Sort by", selection: $sortModeRaw) {
                        ForEach(SortMode.allCases, id: \.rawValue) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .onChange(of: sortModeRaw) { _, _ in viewModel.reSort() }
                } header: {
                    Text("Ranking")
                } footer: {
                    Text("DHW = degree heating weeks, a way to measure the conditions that cause thermal stress. Streak = consecutive weeks with thermal stress.")
                }

                Section {
                    Picker("Data history", selection: $daysBack) {
                        ForEach(daysBackOptions, id: \.self) { d in
                            Text("\(d) days").tag(d)
                        }
                    }
                    LabeledContent("Concurrent requests", value: "\(preferredMaxConcurrency)")
                } header: {
                    Text("Data fetching")
                } footer: {
                    Text("Each refresh first \(daysBack/2) days, then the remaining \(daysBack - daysBack/2) days. Streaks are auto-extended in 60-day chunks (up to \(autoExtendCapDays) days). Concurrency starts at 16 and halves automatically if NOAA decides to throttle.")
                }

                Section {
                    ForEach(DataSource.allCases, id: \.rawValue) { source in
                        Toggle(isOn: bindingFor(source: source)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.displayName)
                                Text(sourceDescription(source))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Data sources")
                } footer: {
                    Text("Virtual Stations are NOAA's published per-region time series using the 90th-percentile HotSpot methodology. The gridded source samples NOAA's 5 km global grid at hand-picked points, not NOAA's official polygon-aggregated measurements. ")
                }

                Section("Sources") {
                    Link("NOAA Coral Reef Watch 5km Product",
                         destination: URL(string: "https://coralreefwatch.noaa.gov/product/5km/")!)
                    Link("NOAA Regional Virtual Stations",
                         destination: URL(string: "https://coralreefwatch.noaa.gov/product/vs/")!)
                }
            }
            .navigationTitle("Settings")
            .task { await notifications.refreshAuthorizationStatus() }
        }
    }

    /// Two-way binding for a single data-source toggle. Backed by the CSV stored
    /// in UserDefaults via @AppStorage so the view re-renders when the set changes.
    private func bindingFor(source: DataSource) -> Binding<Bool> {
        Binding(
            get: {
                Self.parseSources(enabledSourcesCSV).contains(source)
            },
            set: { isOn in
                var set = Self.parseSources(enabledSourcesCSV)
                if isOn { set.insert(source) } else { set.remove(source) }
                // Never let the user turn off every source — fall back to the
                // authoritative VS dataset, which is the app's default.
                if set.isEmpty { set = [.regionalVirtualStations] }
                enabledSourcesCSV = set.map(\.rawValue).sorted().joined(separator: ",")
            }
        )
    }

    private static func parseSources(_ csv: String) -> Set<DataSource> {
        if csv.isEmpty { return [.regionalVirtualStations] }
        let parsed = csv.split(separator: ",")
            .compactMap { DataSource(rawValue: String($0)) }
        return parsed.isEmpty ? [.regionalVirtualStations] : Set(parsed)
    }

    private func sourceDescription(_ s: DataSource) -> String {
        switch s {
        case .gridded5km:
            return "Single-pixel sample of NOAA's 5 km global grid at hand-picked reefs (156 sites). Quick and lightweight; values are estimates."
        case .regionalVirtualStations:
            return "NOAA's official 90th-percentile polygon aggregates (214 named sites). More authoritative; larger initial sync."
        }
    }

    private var footerText: String {
        if !notifications.isEnabled {
            return "Off by default. When enabled, you'll receive a local notification each time a tracked reef crosses your selected DHW threshold upward between data refreshes."
        }
        switch notifications.authorizationStatus {
        case .denied:
            return "Notifications are disabled in iOS Settings. Enable them under Settings → Notifications → Coral Reef Watch."
        case .authorized, .provisional, .ephemeral:
            return "You'll receive a local notification each time a tracked reef crosses your selected DHW threshold upward."
        default:
            return "Tap to grant notification permission."
        }
    }
}
