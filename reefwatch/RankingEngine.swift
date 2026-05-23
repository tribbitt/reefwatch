import Foundation

/// Ranks reefs by current DHW (or streak length), with the other key as
/// tiebreaker. Reefs whose latest sample contains NaN values sink to the
/// bottom regardless of sort mode.
enum RankingEngine {

    /// Rank stations by the chosen primary key. Stations with no samples are dropped.
    static func rank(_ histories: [(VirtualStation, [DHWSample])],
                     sortBy: SortMode = .byDHW) -> [RankedReef] {
        let reefs: [RankedReef] = histories.compactMap { (station, samples) in
            guard let latest = samples.last else { return nil }
            let s = streakInfo(samples: samples)
            return RankedReef(
                id: station.id,
                station: station,
                currentDHW: latest.dhw,
                currentSSTAnomaly: latest.sstAnomaly,
                streakWeeks: s.weeks,
                streakLevel: s.level,
                streakIsMaxed: s.isMaxed,
                alertLevel: .classify(dhw: latest.dhw, sstAnomaly: latest.sstAnomaly),
                history: samples
            )
        }

        let valid  = reefs.filter { !$0.hasNaN }
        let nanned = reefs.filter {  $0.hasNaN }

        let sortedValid: [RankedReef]
        switch sortBy {
        case .byDHW:
            sortedValid = valid.sorted {
                if $0.currentDHW != $1.currentDHW { return $0.currentDHW > $1.currentDHW }
                return $0.streakWeeks > $1.streakWeeks
            }
        case .byStreak:
            sortedValid = valid.sorted {
                if $0.streakWeeks != $1.streakWeeks { return $0.streakWeeks > $1.streakWeeks }
                return $0.currentDHW > $1.currentDHW
            }
        }

        // Alphabetize NaN reefs so their order is stable across refreshes.
        let sortedNaN = nanned.sorted { $0.station.name < $1.station.name }
        return sortedValid + sortedNaN
    }

    struct StreakInfo {
        let weeks: Int
        let level: NOAAAlertLevel  // level of the most recent weekly bucket
        let bucketCount: Int
        /// True when the streak equals the loaded history window AND the level
        /// is meaningful (not No Stress). Triggers auto-extension.
        var isMaxed: Bool { weeks > 0 && weeks == bucketCount && level != .noStress }
    }

    /// Backwards-compatible wrapper for tests / callers that only want the count.
    static func currentStreakWeeks(in samples: [DHWSample]) -> Int {
        streakInfo(samples: samples).weeks
    }

    /// Bucket samples into ISO weeks (mean DHW + mean SST anomaly per week,
    /// skipping NaN samples within each bucket), classify each bucket, then
    /// count consecutive trailing weeks at the same alert level.
    static func streakInfo(samples: [DHWSample]) -> StreakInfo {
        guard !samples.isEmpty else { return StreakInfo(weeks: 0, level: .noStress, bucketCount: 0) }
        let cal = Calendar(identifier: .iso8601)

        struct WeeklyBucket {
            let key: DateComponents
            let dhw: Double
            let ssta: Double
            var level: NOAAAlertLevel { .classify(dhw: dhw, sstAnomaly: ssta) }
        }
        var weekly: [WeeklyBucket] = []
        var bucket: [DHWSample] = []
        var currentKey: DateComponents? = nil

        func flush() {
            guard let key = currentKey, !bucket.isEmpty else { return }
            let valid = bucket.filter { !$0.dhw.isNaN && !$0.sstAnomaly.isNaN }
            guard !valid.isEmpty else { return }
            let meanDHW  = valid.map(\.dhw).reduce(0, +)         / Double(valid.count)
            let meanSSTA = valid.map(\.sstAnomaly).reduce(0, +)  / Double(valid.count)
            weekly.append(WeeklyBucket(key: key, dhw: meanDHW, ssta: meanSSTA))
        }

        for s in samples {
            let key = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: s.date)
            if key != currentKey {
                flush()
                bucket.removeAll(keepingCapacity: true)
                currentKey = key
            }
            bucket.append(s)
        }
        flush()

        guard let latest = weekly.last else {
            return StreakInfo(weeks: 0, level: .noStress, bucketCount: 0)
        }

        // Walk backwards counting consecutive weeks with any thermal stress
        // (mean DHW > 0). Crossing an Alert Level boundary mid-streak no
        // longer resets the count — only a return to No Stress / Watch does.
        var streak = 0
        for w in weekly.reversed() {
            if w.dhw > 0 { streak += 1 } else { break }
        }
        return StreakInfo(weeks: streak, level: latest.level, bucketCount: weekly.count)
    }
}
