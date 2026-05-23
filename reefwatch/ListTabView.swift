import SwiftUI

struct ListTabView: View {
    @EnvironmentObject private var viewModel: ReefRankingViewModel
    @EnvironmentObject private var notifications: NotificationService

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let panelHeight = geo.size.height * 0.3

                Group {
                    if viewModel.isLoading && viewModel.rankedReefs.isEmpty {
                        ProgressView("Loading NOAA Coral Reef Watch data…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = viewModel.errorMessage, viewModel.rankedReefs.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("Couldn't load data").font(.headline)
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Retry") { Task { await viewModel.load(notifications: notifications) } }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal, 32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 18) {
                                if viewModel.loadingMore {
                                    HStack(spacing: 8) {
                                        ProgressView().controlSize(.small)
                                        Text(refreshBannerText)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                } else if let ageText = cachedAgeText {
                                    Text(ageText)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                }
                                if viewModel.failedStationCount > 0 {
                                    Text("\(viewModel.failedStationCount) station\(viewModel.failedStationCount == 1 ? "" : "s") didn't respond — showing partial results.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                }
                                ForEach(Array(viewModel.rankedReefs.enumerated()), id: \.element.id) { idx, reef in
                                    NavigationLink(value: reef) {
                                        ReefPanelView(rank: idx + 1, reef: reef, minPanelHeight: panelHeight)
                                            .padding(.horizontal, 12)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 12)
                        }
                        .refreshable { await viewModel.load(notifications: notifications, forceRefresh: true) }
                    }
                }
            }
            .navigationTitle("Reefs Under Stress")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: RankedReef.self) { reef in
                ReefDetailView(reef: reef)
            }
        }
    }

    /// "Refreshing…" when the list is already showing a full set of stations (from cache),
    /// "Loading N more reefs…" while a cold first-load is filling out.
    private var refreshBannerText: String {
        let remaining = viewModel.totalStationCount - viewModel.rankedReefs.count
        if remaining <= 0 {
            return "Refreshing from NOAA…"
        }
        return "Loading \(remaining) more reefs…"
    }

    /// "Updated 2 hours ago" — shown when not actively refreshing, so users
    /// know how fresh the cached data is. Returns nil when there's no cache yet.
    private var cachedAgeText: String? {
        guard let cachedAt = viewModel.cachedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Updated " + formatter.localizedString(for: cachedAt, relativeTo: Date())
    }
}
