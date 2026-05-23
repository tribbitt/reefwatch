import Foundation
import Combine
import SwiftUI

@MainActor
final class ReefRankingViewModel: ObservableObject {
    @Published private(set) var rankedReefs: [RankedReef] = []
    @Published private(set) var isLoading: Bool = false        // true only while NO data is shown yet
    @Published private(set) var loadingMore: Bool = false      // true while any background phase is in flight
    @Published private(set) var errorMessage: String?
    @Published private(set) var failedStationCount: Int = 0
    @Published private(set) var totalStationCount: Int = 0
    @Published private(set) var cachedAt: Date?

    private let service = NOAAService()

    /// Re-rank the visible list every N successful extended-tier completions.
    private let rerankBatchSize = 8

    /// Auto-extension fetches additional history in chunks of this many days.
    private let autoExtendChunkDays = 60

    /// Live concurrency cap. Starts from AppSettings.preferredMaxConcurrency and
    /// is halved (and persisted) the first time we see HTTP 503/429.
    private var liveMaxConcurrent: Int = 16
    private var observedRateLimit: Bool = false

    /// Working merged history per station, keyed by station id. Mutates across phases.
    private var working: [String: [DHWSample]] = [:]

    func load(notifications: NotificationService, forceRefresh: Bool = false) async {
        let daysBack = max(30, AppSettings.daysBack)
        let initialDays = max(15, daysBack / 2)
        let enabledSources = AppSettings.enabledDataSources
        let activeStations = VirtualStationCatalog.stations(for: enabledSources)

        errorMessage = nil
        failedStationCount = 0
        totalStationCount = activeStations.count
        liveMaxConcurrent = max(2, AppSettings.preferredMaxConcurrency)
        observedRateLimit = false
        working = [:]

        let stationsByID = Dictionary(uniqueKeysWithValues:
            activeStations.map { ($0.id, $0) }
        )

        // ── Step 0: warm-load from disk cache ─────────────────────────────
        var cacheAge: TimeInterval = .infinity
        var cachedAtFromDisk: Date? = nil
        if let cached = ReefCache.load() {
            working = cached.samples
            cacheAge = Date().timeIntervalSince(cached.cachedAt)
            cachedAtFromDisk = cached.cachedAt
            let matched = working.keys.filter { stationsByID[$0] != nil }.count
            #if DEBUG
            print("[ReefCache] loaded \(working.count) station entries, age \(Int(cacheAge))s, matched \(matched) against active source(s)")
            #endif
        } else {
            #if DEBUG
            print("[ReefCache] no cache found on disk")
            #endif
        }

        let cachedRanking = currentRanking(stationsByID: stationsByID)
        if !cachedRanking.isEmpty {
            self.rankedReefs = cachedRanking
            self.cachedAt = cachedAtFromDisk
            self.isLoading = false
            self.loadingMore = true
        }

        // ── TTL gate: skip network entirely if cache is recent ─────────────
        if !forceRefresh
            && !rankedReefs.isEmpty
            && cacheAge < AppSettings.cacheTTLSeconds {
            self.isLoading = false
            self.loadingMore = false
            // Re-evaluate notifications against cached data so missed crossings
            // don't get lost just because we skipped the fetch.
            await notifications.evaluate(rankedReefs)
            return
        }
 
        if rankedReefs.isEmpty {
            isLoading = true
            loadingMore = false
        }
        defer { isLoading = false; loadingMore = false }

        // ── Phase 1a: priority × initialDays ──────────────────────────────
        await fetchAndMerge(
            stations: VirtualStationCatalog.priorityStations(for: enabledSources),
            daysBack: initialDays,
            stationsByID: stationsByID,
            rerankEvery: 999
        )

        let phase1Ranking = currentRanking(stationsByID: stationsByID)
        if !phase1Ranking.isEmpty {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.rankedReefs = phase1Ranking
            }
            self.isLoading = false
            self.loadingMore = true
        }

        if phase1Ranking.isEmpty && rankedReefs.isEmpty {
            errorMessage = "All NOAA requests failed. Check your network or try again."
            await notifications.evaluate(phase1Ranking)
            return
        }

        // ── Phase 1b: extended × initialDays (progressive) ────────────────
        await fetchAndMerge(
            stations: VirtualStationCatalog.extendedStations(for: enabledSources),
            daysBack: initialDays,
            stationsByID: stationsByID,
            rerankEvery: rerankBatchSize
        )

        // ── Phase 2: backfill the older window (initialDays → daysBack) ───
        if daysBack > initialDays {
            await fetchOlderWindow(
                stations: activeStations,
                fromDaysBack: daysBack,
                toDaysBack: initialDays,
                stationsByID: stationsByID,
                rerankEvery: rerankBatchSize
            )
        }

        // ── Phase 3: auto-extend any station still streak-maxed ───────────
        await autoExtendMaxedStreaks(
            stationsByID: stationsByID,
            startingOffset: daysBack,
            absoluteCapDays: AppSettings.autoExtendCapDays
        )

        // ── Final pass: re-rank, persist, evaluate notifications ──────────
        let finalRanking = currentRanking(stationsByID: stationsByID)
        withAnimation(.easeInOut(duration: 0.25)) {
            self.rankedReefs = finalRanking
        }
        self.failedStationCount = totalStationCount - working.filter { !$0.value.isEmpty }.count

        // Save synchronously. A detached task can be cancelled by iOS's app
        // lifecycle before the disk write completes, which silently leaves the
        // cache empty and forces a full refetch next launch.
        ReefCache.save(working)
        #if DEBUG
        print("[ReefCache] saved \(working.count) station entries")
        #endif
        self.cachedAt = Date()
        await notifications.evaluate(finalRanking)
    }

    // MARK: - Fetch primitives

    private func currentRanking(stationsByID: [String: VirtualStation]) -> [RankedReef] {
        let pairs: [(VirtualStation, [DHWSample])] = working.compactMap { (id, samples) in
            guard let station = stationsByID[id], !samples.isEmpty else { return nil }
            return (station, samples)
        }
        return RankingEngine.rank(pairs, sortBy: AppSettings.sortMode)
    }

    /// Re-rank the currently displayed reefs using the active sort mode without
    /// re-fetching. Cheap; call this when the sort setting changes.
    func reSort() {
        let stationsByID = Dictionary(uniqueKeysWithValues:
            VirtualStationCatalog.allStations.map { ($0.id, $0) }
        )
        withAnimation(.easeInOut(duration: 0.25)) {
            self.rankedReefs = currentRanking(stationsByID: stationsByID)
        }
    }

    /// Fetch `stations` going back `daysBack` from now, merging into `working`.
    /// `rerankEvery` controls how often the list re-renders during streaming.
    private func fetchAndMerge(stations: [VirtualStation],
                               daysBack: Int,
                               stationsByID: [String: VirtualStation],
                               rerankEvery: Int) async {
        let start = Calendar(identifier: .gregorian).date(byAdding: .day, value: -daysBack, to: Date())!
        await runFetchGroup(stations: stations, range: (start, nil),
                            stationsByID: stationsByID, rerankEvery: rerankEvery)
    }

    /// Fetch only the older sub-window `[-fromDaysBack, -toDaysBack)` for each station.
    private func fetchOlderWindow(stations: [VirtualStation],
                                  fromDaysBack: Int,
                                  toDaysBack: Int,
                                  stationsByID: [String: VirtualStation],
                                  rerankEvery: Int) async {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(byAdding: .day, value: -fromDaysBack, to: Date())!
        let end   = cal.date(byAdding: .day, value: -toDaysBack,   to: Date())!
        await runFetchGroup(stations: stations, range: (start, end),
                            stationsByID: stationsByID, rerankEvery: rerankEvery)
    }

    /// Walks `stations` with bounded concurrency, fetching the given range and
    /// merging each result into `working`. Re-ranks every `rerankEvery` completions.
    private func runFetchGroup(stations: [VirtualStation],
                               range: (start: Date, end: Date?),
                               stationsByID: [String: VirtualStation],
                               rerankEvery: Int) async {
        guard !stations.isEmpty else { return }

        await withTaskGroup(of: (VirtualStation, [DHWSample], Bool).self) { group in
            var iterator = stations.makeIterator()

            // Capture current concurrency to avoid actor-isolation issues inside addTask.
            let cap = self.liveMaxConcurrent

            func enqueueNext() {
                guard let station = iterator.next() else { return }
                group.addTask { [service] in
                    do {
                        let samples = try await service.fetchHistory(for: station, from: range.start, to: range.end)
                        return (station, samples, false)
                    } catch NOAAServiceError.rateLimited {
                        return (station, [], true)
                    } catch {
                        return (station, [], false)
                    }
                }
            }

            for _ in 0..<cap { enqueueNext() }

            var sinceLastRerank = 0
            for await (station, samples, wasRateLimited) in group {
                if wasRateLimited {
                    handleRateLimitObserved()
                }
                if !samples.isEmpty {
                    mergeSamples(samples, into: station.id)
                }
                sinceLastRerank += 1
                if sinceLastRerank >= rerankEvery {
                    let ranked = currentRanking(stationsByID: stationsByID)
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.rankedReefs = ranked
                    }
                    sinceLastRerank = 0
                }
                enqueueNext()
            }
        }
    }

    /// Phase 3. For every station whose current streak equals its bucket count,
    /// fetch an additional `autoExtendChunkDays` of older history and retry.
    /// Stops per-station when streak resolves or we hit the absolute cap.
    private func autoExtendMaxedStreaks(stationsByID: [String: VirtualStation],
                                        startingOffset: Int,
                                        absoluteCapDays: Int) async {
        var currentOffset = startingOffset
        while currentOffset < absoluteCapDays {
            let maxed: [VirtualStation] = working.compactMap { (id, samples) -> VirtualStation? in
                let info = RankingEngine.streakInfo(samples: samples)
                guard info.isMaxed, let station = stationsByID[id] else { return nil }
                return station
            }
            if maxed.isEmpty { break }

            let nextOffset = min(currentOffset + autoExtendChunkDays, absoluteCapDays)
            await fetchOlderWindow(
                stations: maxed,
                fromDaysBack: nextOffset,
                toDaysBack: currentOffset,
                stationsByID: stationsByID,
                rerankEvery: 4
            )
            currentOffset = nextOffset
        }
    }

    // MARK: - State mutation

    /// Merges new samples into the working set for `stationID`, deduplicating by
    /// truncated day. Sorted, oldest first.
    private func mergeSamples(_ new: [DHWSample], into stationID: String) {
        let existing = working[stationID] ?? []
        var byDay: [Date: DHWSample] = [:]
        let cal = Calendar(identifier: .gregorian)
        for s in existing + new {
            let key = cal.startOfDay(for: s.date)
            byDay[key] = s
        }
        working[stationID] = byDay.values.sorted { $0.date < $1.date }
    }

    private func handleRateLimitObserved() {
        guard !observedRateLimit else { return }
        observedRateLimit = true
        let fallback = max(2, liveMaxConcurrent / 2)
        liveMaxConcurrent = fallback
        AppSettings.preferredMaxConcurrency = fallback
    }
}
