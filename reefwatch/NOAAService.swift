import Foundation
import SwiftUI

/// Fetches DHW + SST anomaly time series from NOAA Coral Reef Watch via ERDDAP.
///
/// Endpoint reference: NOAA CoastWatch ERDDAP serves the CRW 5 km daily product.
/// We sample the gridded dataset at a single lat/lon over an explicit time range
/// and return a daily series. For very high-frequency use, switch to weekly stats
/// or the pre-computed Regional Virtual Station text files at
/// https://coralreefwatch.noaa.gov/product/vs/data.php
actor NOAAService {

    /// PacIOOS ERDDAP node hosting NOAA Coral Reef Watch's 5 km daily product.
    /// `coastwatch.pfeg.noaa.gov` 302-redirects here, and URLSession can drop
    /// the query string on cross-host redirects — so we hit PacIOOS directly.
    private let griddedBase = URL(string: "https://pae-paha.pacioos.hawaii.edu/erddap/griddap")!

    /// Per-station text files for NOAA's Regional Virtual Stations.
    private let virtualStationsBase = URL(string: "https://coralreefwatch.noaa.gov/product/vs/data")!

    private let datasetID  = "dhw_5km"

    private let session: URLSession
    private let isoFormatter: ISO8601DateFormatter

    init(session: URLSession = .shared) {
        self.session = session
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime]
    }

    /// Source-aware entry point. Picks the right fetcher based on
    /// `station.source`. For VS-source stations the `from/to` window is
    /// applied client-side (the text file contains the full history).
    func fetchHistory(for station: VirtualStation, daysBack: Int = 120) async throws -> [DHWSample] {
        let start = Calendar(identifier: .gregorian).date(byAdding: .day, value: -daysBack, to: Date())!
        return try await fetchHistory(for: station, from: start, to: nil)
    }

    /// Fetches daily samples between `from` and `to` (or "now" if `to` is nil).
    /// Dispatches to the right backend based on `station.source`.
    func fetchHistory(for station: VirtualStation, from start: Date, to end: Date?) async throws -> [DHWSample] {
        switch station.source {
        case .gridded5km:
            return try await fetchGridded(station: station, from: start, to: end)
        case .regionalVirtualStations:
            return try await fetchVirtualStation(station: station, from: start, to: end)
        }
    }

    // MARK: - Gridded fetcher (ERDDAP CSV)

    private func fetchGridded(station: VirtualStation, from start: Date, to end: Date?) async throws -> [DHWSample] {
        let url = try buildGriddedURL(lat: station.latitude, lon: station.longitude, start: start, end: end)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw NOAAServiceError.badResponse(-1)
        }
        if http.statusCode == 503 || http.statusCode == 429 {
            throw NOAAServiceError.rateLimited
        }
        if http.statusCode == 404 {
            return []
        }
        guard http.statusCode == 200 else {
            throw NOAAServiceError.badResponse(http.statusCode)
        }
        return try parseERDDAPCSV(data)
    }

    // MARK: - Virtual Station fetcher (NOAA text file)

    private func fetchVirtualStation(station: VirtualStation, from start: Date, to end: Date?) async throws -> [DHWSample] {
        let url = virtualStationsBase.appendingPathComponent("\(station.rawID).txt")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw NOAAServiceError.badResponse(-1)
        }
        if http.statusCode == 503 || http.statusCode == 429 {
            throw NOAAServiceError.rateLimited
        }
        if http.statusCode == 404 {
            return []
        }
        guard http.statusCode == 200 else {
            throw NOAAServiceError.badResponse(http.statusCode)
        }
        let allSamples = try parseVirtualStationText(data)
        // Apply window client-side: NOAA's text file contains the full record
        // (1985–present), so we trim to [start, end ?? .distantFuture].
        return allSamples.filter { sample in
            if sample.date < start { return false }
            if let end, sample.date > end { return false }
            return true
        }
    }

    // MARK: - URL construction

    private func buildGriddedURL(lat: Double, lon: Double, start: Date, end: Date?) throws -> URL {
        // ERDDAP griddap CSV query:
        // {base}/{dataset}.csv?CRW_DHW[(start):1:(end)|last][(lat)][(lon)],CRW_SSTANOMALY[…]
        let startStr = isoFormatter.string(from: start)
        let endStr   = end.map { isoFormatter.string(from: $0) }
        let timeEnd  = endStr.map { "(\($0))" } ?? "last"
        let latStr   = String(format: "%.3f", lat)
        let lonStr   = String(format: "%.3f", lon)

        let query = """
        CRW_DHW[(\(startStr)):1:\(timeEnd)][(\(latStr))][(\(lonStr))],\
        CRW_SSTANOMALY[(\(startStr)):1:\(timeEnd)][(\(latStr))][(\(lonStr))]
        """

        var comps = URLComponents(url: griddedBase.appendingPathComponent("\(datasetID).csv"),
                                  resolvingAgainstBaseURL: false)!
        comps.percentEncodedQuery = query
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        guard let url = comps.url else { throw NOAAServiceError.invalidURL }
        return url
    }

    // MARK: - VS text-file parser

    /// NOAA's VS text format. Skips the human-readable header block, finds the
    /// column-name row that begins with "YYYY", then parses each subsequent
    /// whitespace-delimited daily row.
    ///
    ///   YYYY MM DD SST_MIN SST_MAX SST@90th_HS SSTA@90th_HS 90th_HS DHW BAA
    ///       0  1  2       3       4           5            6       7   8   9
    ///
    /// We extract date (cols 0-2), SSTA@90th_HS (col 6), and DHW (col 8). The
    /// "DHW" column is NOAA's official polygon-aggregated DHW from the 90th
    /// percentile HotSpot — what their public reports use.
    private func parseVirtualStationText(_ data: Data) throws -> [DHWSample] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw NOAAServiceError.parse("non-UTF8 body")
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        var samples: [DHWSample] = []
        var seenHeader = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !seenHeader {
                if line.hasPrefix("YYYY") { seenHeader = true }
                continue
            }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 9,
                  let yr = Int(parts[0]), let mo = Int(parts[1]), let dy = Int(parts[2]),
                  let ssta = Double(parts[6]),
                  let dhw  = Double(parts[8])
            else { continue }
            let comps = DateComponents(year: yr, month: mo, day: dy, hour: 12)
            guard let date = cal.date(from: comps) else { continue }
            samples.append(DHWSample(date: date, dhw: dhw, sstAnomaly: ssta))
        }
        return samples
    }

    // MARK: - Parsing

    /// ERDDAP CSV format is two header rows (names, units) then data rows:
    /// time,latitude,longitude,CRW_DHW,CRW_SSTANOMALY
    /// UTC,degrees_north,degrees_east,Celsius_weeks,Celsius
    /// 2026-01-01T12:00:00Z,-14.500,145.500,3.2,1.1
    private func parseERDDAPCSV(_ data: Data) throws -> [DHWSample] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw NOAAServiceError.parse("non-UTF8 body")
        }
        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.count > 2 else { return [] }

        var samples: [DHWSample] = []
        samples.reserveCapacity(lines.count - 2)

        for line in lines.dropFirst(2) {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 5,
                  let date = isoFormatter.date(from: cols[0]),
                  let dhw  = Double(cols[3]),
                  let ssta = Double(cols[4])
            else { continue }
            samples.append(DHWSample(date: date, dhw: dhw, sstAnomaly: ssta))
        }
        return samples.sorted { $0.date < $1.date }
    }
}

enum NOAAServiceError: LocalizedError {
    case invalidURL
    case badResponse(Int)
    case rateLimited
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "Couldn't build NOAA request URL."
        case .badResponse(let code):return "NOAA returned HTTP \(code)."
        case .rateLimited:          return "NOAA throttled the request (HTTP 503/429)."
        case .parse(let reason):    return "Couldn't parse NOAA response: \(reason)"
        }
    }
}

// MARK: - Disk cache

/// Persists the last successful set of station histories to `Documents/reef_cache.json`.
/// Enables stale-while-revalidate: on launch, the UI seeds from cache instantly while
/// fresh data fetches in the background.
enum ReefCache {
    private struct Payload: Codable {
        let cachedAt: Date
        let version: Int
        let samplesByStationID: [String: [DHWSample]]
    }
    /// Bumped to v2 after the source-aware refactor changed `VirtualStation.id`
    /// from a raw NOAA id ("florida_keys") to a composite ("…regional…:florida_keys").
    /// Anything written under v1 has unmatchable keys and would force a full
    /// refetch every launch — this version gate discards it cleanly.
    private static let currentVersion = 2

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("reef_cache.json")
    }

    /// Returns (cachedAt, samplesByStationID) or nil if no usable cache exists.
    static func load() -> (cachedAt: Date, samples: [String: [DHWSample]])? {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == currentVersion
        else { return nil }
        return (payload.cachedAt, payload.samplesByStationID)
    }

    /// Persist a fresh snapshot. Empty histories are dropped to keep the file small.
    static func save(_ samples: [String: [DHWSample]]) {
        let nonEmpty = samples.filter { !$0.value.isEmpty }
        let payload = Payload(cachedAt: Date(), version: currentVersion, samplesByStationID: nonEmpty)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - App settings store

/// User-tunable knobs persisted in UserDefaults. Not an ObservableObject —
/// views that need to react to changes should use `@AppStorage` directly with
/// the same keys defined below.
enum SortMode: String, CaseIterable {
    case byDHW    = "dhw"
    case byStreak = "streak"

    var label: String {
        switch self {
        case .byDHW:    return "Current DHW"
        case .byStreak: return "Streak length"
        }
    }
}

enum AppSettings {
    enum Key {
        static let daysBack                = "settings.daysBack"
        static let autoExtendCapDays       = "settings.autoExtendCapDays"
        static let preferredMaxConcurrency = "noaa.preferredMaxConcurrency"
        static let sortMode                = "settings.sortMode"
        static let enabledDataSources      = "settings.enabledDataSources"
    }

    /// Which data sources the app actively fetches from. Persisted as a
    /// comma-separated list of DataSource.rawValue. Default = NOAA's
    /// Regional Virtual Stations only (the authoritative polygon-aggregated
    /// 90th-percentile HotSpot product). Users can flip on the gridded
    /// estimate as an additional / alternative source in Settings.
    static var enabledDataSources: Set<DataSource> {
        get {
            let raw = UserDefaults.standard.string(forKey: Key.enabledDataSources) ?? ""
            if raw.isEmpty { return [.regionalVirtualStations] }
            let parsed = raw.split(separator: ",")
                .compactMap { DataSource(rawValue: String($0)) }
            return parsed.isEmpty ? [.regionalVirtualStations] : Set(parsed)
        }
        set {
            let joined = newValue.map(\.rawValue).sorted().joined(separator: ",")
            UserDefaults.standard.set(joined, forKey: Key.enabledDataSources)
        }
    }

    static var sortMode: SortMode {
        let raw = UserDefaults.standard.string(forKey: Key.sortMode) ?? SortMode.byDHW.rawValue
        return SortMode(rawValue: raw) ?? .byDHW
    }

    /// How far back to fetch history (days).
    static var daysBack: Int {
        let v = UserDefaults.standard.integer(forKey: Key.daysBack)
        return v == 0 ? 120 : v
    }

    /// Soft ceiling on auto-extension when a streak stays maxed.
    static var autoExtendCapDays: Int {
        let v = UserDefaults.standard.integer(forKey: Key.autoExtendCapDays)
        return v == 0 ? 730 : v
    }

    /// Preferred concurrent ERDDAP requests; adaptively halved on observed 503/429.
    static var preferredMaxConcurrency: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: Key.preferredMaxConcurrency)
            return v == 0 ? 16 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.preferredMaxConcurrency) }
    }

    /// How long the disk cache stays "fresh enough" to skip the automatic refresh
    /// on launch. NOAA publishes the 5 km product roughly once per day, so 6 h
    /// is a reasonable balance between catching new releases and saving data.
    static let cacheTTLSeconds: TimeInterval = 6 * 3600
}
