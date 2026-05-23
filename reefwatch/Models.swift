import Foundation

struct VirtualStation: Identifiable, Hashable {
    /// NOAA-side / catalog identifier (e.g. "florida_keys"). Used for URL
    /// construction and for matching against catalog-internal sets like
    /// `priorityIDs`. Not unique across sources by itself — e.g. "gbr_central"
    /// exists in both the gridded and Virtual Stations catalogs.
    let rawID: String
    let name: String
    let region: String
    let latitude: Double
    let longitude: Double
    /// Which NOAA product / endpoint this station's time-series comes from.
    /// Drives both the fetcher used and whether the panel shows a
    /// "not directly measured" indicator.
    let source: DataSource

    /// Unique app-wide identifier — combines source + rawID so the same NOAA
    /// site can appear once per enabled source without colliding in SwiftUI's
    /// ForEach, in the cache key map, or in the ViewModel's working set.
    var id: String { "\(source.rawValue):\(rawID)" }

    /// Defaulted-source initializer so the existing 156 hand-picked gridded
    /// stations don't need every call-site updated. The `id:` parameter is
    /// the NOAA-side raw ID, *not* the composite SwiftUI id.
    init(id rawID: String, name: String, region: String,
         latitude: Double, longitude: Double,
         source: DataSource = .gridded5km) {
        self.rawID = rawID; self.name = name; self.region = region
        self.latitude = latitude; self.longitude = longitude
        self.source = source
    }
}

/// Which NOAA data product is being used to populate a station's history.
enum DataSource: String, Codable, CaseIterable, Hashable {
    /// NOAA Coral Reef Watch 5 km gridded daily product, sampled at a single
    /// pixel via ERDDAP. Coordinates are hand-picked, so values are NOT
    /// NOAA's published Regional Virtual Stations — they're single-pixel
    /// estimates pulled from the global grid.
    case gridded5km             = "crw5km_gridded"

    /// NOAA's published Regional Virtual Stations — per-region polygon
    /// aggregates with the 90th-percentile HotSpot methodology. This is
    /// the authoritative "this reef is bleaching" measurement NOAA reports.
    case regionalVirtualStations = "regional_virtual_stations"

    /// Display name for Settings UI and source badges.
    var displayName: String {
        switch self {
        case .gridded5km:              return "NOAA Coral Reef Watch 5 km (ERDDAP)"
        case .regionalVirtualStations: return "NOAA Regional Virtual Stations"
        }
    }

    /// True if this source samples a single grid pixel rather than using
    /// NOAA's polygon-aggregated measurements. Used to flag cards with a
    /// "not directly measured" indicator.
    var isGriddedEstimate: Bool {
        switch self {
        case .gridded5km:              return true
        case .regionalVirtualStations: return false
        }
    }
}

struct DHWSample: Hashable, Codable {
    let date: Date
    let dhw: Double          // °C-weeks
    let sstAnomaly: Double   // °C
}

struct RankedReef: Identifiable, Hashable {
    let id: String
    let station: VirtualStation
    let currentDHW: Double
    let currentSSTAnomaly: Double
    let streakWeeks: Int
    let streakLevel: NOAAAlertLevel  // alert level of the most recent week (= what the streak counts)
    let streakIsMaxed: Bool          // true when streak equals the number of weeks loaded
    let alertLevel: NOAAAlertLevel
    let history: [DHWSample]         // most-recent-last

    /// True when the current snapshot has unusable readings — used to push these
    /// reefs to the bottom of the list regardless of sort mode.
    var hasNaN: Bool { currentDHW.isNaN || currentSSTAnomaly.isNaN }
}

enum NOAAAlertLevel: String, CaseIterable {
    case noStress       = "No Stress"
    case watch          = "Bleaching Watch"
    case warning        = "Bleaching Warning"
    case alert1         = "Alert Level 1"
    case alert2         = "Alert Level 2"
    case alert3         = "Alert Level 3"
    case alert4         = "Alert Level 4"
    case alert5         = "Alert Level 5"

    /// Shorter labels for compact UI surfaces (metric blocks, streak line).
    var shortLabel: String {
        switch self {
        case .noStress: return "No Stress"
        case .watch:    return "Watch"
        case .warning:  return "Warning"
        case .alert1:   return "Alert 1"
        case .alert2:   return "Alert 2"
        case .alert3:   return "Alert 3"
        case .alert4:   return "Alert 4"
        case .alert5:   return "Alert 5"
        }
    }

    /// Lower bound of DHW (°C-weeks) for this level. Watch is handled separately
    /// (driven by HotSpot, not DHW), but we treat 0 < HS < 1 as "watch-like" here.
    var dhwLowerBound: Double {
        switch self {
        case .noStress: return 0
        case .watch:    return 0      // SST anomaly triggered, DHW still 0
        case .warning:  return 0.001  // any DHW > 0
        case .alert1:   return 4
        case .alert2:   return 8
        case .alert3:   return 12
        case .alert4:   return 16
        case .alert5:   return 20
        }
    }

    static func classify(dhw: Double, sstAnomaly: Double) -> NOAAAlertLevel {
        if dhw >= 20 { return .alert5 }
        if dhw >= 16 { return .alert4 }
        if dhw >= 12 { return .alert3 }
        if dhw >= 8  { return .alert2 }
        if dhw >= 4  { return .alert1 }
        if dhw > 0   { return .warning }
        if sstAnomaly >= 1.0 { return .watch }
        return .noStress
    }
}
