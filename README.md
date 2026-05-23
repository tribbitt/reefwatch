# reefwatch

A SwiftUI iOS app that surfaces the world's coral reefs currently under thermal
stress, ranked by NOAA Coral Reef Watch's 5 km daily product.

Tap a reef to see its 120-day DHW and SST-anomaly history. Switch to the map
tab for a global overview where each reef pin is colored by its current
bleaching-alert level. Enable optional local notifications to get alerted when
any tracked reef crosses a Degree Heating Week threshold upward.

## Features

- **Ranked panel list** of ~156 reefs across every major coral biogeographic
  region (Coral Triangle, Caribbean, Red Sea, Pacific Islands, etc.). Sort by
  current DHW or by thermal-stress streak length.
- **Two-step + adaptive load** — priority reefs render first (~5 s), the rest
  stream in progressively. ERDDAP requests run with 16-way concurrency that
  auto-falls back to 8 if NOAA throttles. Disk-cached results mean subsequent
  launches under 6 hours just paint from cache — no network.
- **Per-reef detail** — Swift Charts line graph of DHW and SSTA over the
  configurable history window, with NOAA Alert Level threshold rules.
- **Map tab** — MapKit world map with stress-colored pins.
- **High-DHW visualization** — matches NOAA's expanded bleaching-alert scale:
  - Alert Levels 1-4 get colored borders (yellow → red).
  - Alert 5 (≥ 20 DHW) gets a glowing orange border.
  - DHW ≥ 30 inverts to a black tile with orange text.
  - DHW > 50 collapses to a huge red number — exceeded-scale display.
  - Stacked gradient bars extend the scale past 20 in two-bar / three-bar
    layouts at DHW 20-40 and 40-60.
- **Auto-extended streaks** — when a reef's stress streak fills the entire
  loaded history window, the app keeps fetching older 60-day chunks (up to a
  2-year cap) to surface the true streak length.
- **Local notifications** — optional, default off. Crossings of a user-chosen
  threshold (Warning, Alert 1, 2, 3, 4, 5) fire a `UNUserNotification`
  immediately after each refresh.

## Requirements

- **Xcode 16+** (uses iOS 18 SDK features for tinted app icons).
- **iOS 17.0+** deployment target (modern MapKit `Map(position:)` API,
  Swift Charts, `NavigationStack`).
- A free Personal Team in Xcode → Settings → Accounts is enough to run on
  your own physical device for testing. For distribution to others, see the
  Apple Developer Program and TestFlight.

## Running

1. Open `reefwatch.xcodeproj` in Xcode.
2. Project → target `reefwatch` → **Signing & Capabilities** → pick a Team
   from the dropdown (the committed project file leaves `DEVELOPMENT_TEAM`
   empty, so you must set this before building). Bundle identifier defaults
   to `com.tribbitt.reefwatch` — change it to something unique under your
   account.
3. Select a destination (iPhone simulator or your connected device) and ⌘R.

The first cold launch fetches ~156 daily time-series from NOAA's PacIOOS
ERDDAP node and takes 15-30 s. Subsequent launches restore from cache
instantly and only re-fetch if the cache is older than 6 hours.

## Architecture

```
CoralReefWatchApp.swift   App entry — TabView (Ranked / Map / Settings)
├── ListTabView.swift     Ranked list of reef panels with pull-to-refresh
├── MapTabView.swift      Global map with stress-colored pins
├── SettingsView.swift    Sort mode, history window, notification settings
├── ReefDetailView.swift  Per-reef Swift Charts + position on NOAA scale
└── ReefPanelView.swift   Single ranked card + alert-level reference sheet

Models.swift              VirtualStation, DHWSample, RankedReef, NOAAAlertLevel
RankingEngine.swift       Sort by DHW or streak length; weekly streak detection
NOAAService.swift         ERDDAP fetcher + ReefCache (disk) + AppSettings store
NotificationService.swift UNUserNotificationCenter wrapper, threshold crossings
ReefRankingViewModel.swift Multi-phase load, adaptive concurrency, auto-extend
VirtualStations.swift     ~156 global reef sample sites + priority subset
DHWGradientScaleView.swift Notched gradient scale (1, 2, or 3 stacked bars)
AlertLevel+UI.swift       Categorical color helpers for pins/chips
```

## Data source

All data comes from the [NOAA Coral Reef Watch 5 km Daily Global Product][crw],
served via the public [PacIOOS ERDDAP][erddap] node at
`https://pae-paha.pacioos.hawaii.edu/erddap/griddap/dhw_5km`. The CSV time
series are sampled per reef location for DHW (Degree Heating Weeks, °C·weeks)
and SST anomaly (°C). NOAA's published bleaching-alert scale and HotSpot /
DHW thresholds are mirrored verbatim in `NOAAAlertLevel.classify(dhw:sstAnomaly:)`
and `AlertLevelReferenceSheet`.

Citation: NOAA Coral Reef Watch. 2018, updated daily. NOAA Coral Reef Watch
Version 3.1 Daily Global 5 km Satellite Sea Surface Temperature and DHW
Products. College Park, Maryland, USA: NOAA Coral Reef Watch.

[crw]: https://coralreefwatch.noaa.gov/product/5km/
[erddap]: https://pae-paha.pacioos.hawaii.edu/erddap/

## Notes

- Bundle identifier (`com.tribbitt.reefwatch`) is set in the `.pbxproj`. Change
  it before publishing to App Store Connect.
- The `cinstructions/` directory holds a plain-text spec note describing the
  scale-exceeded visualization rules; safe to delete after reading.
- The app icon master is `logo1-1.png` at the project root. Three derived
  variants (`AppIcon-1024-light/dark/tinted.png`) live in the asset catalog.

## License

No license declared yet — add one before sharing publicly.
