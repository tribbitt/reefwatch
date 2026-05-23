# reefwatch

A SwiftUI iOS app that displays the world's coral reefs currently under thermal
stress using NOAA's virtual stations.

Tap a reef to see its DHW and SST-anomaly history. Switch to the map
tab for a map view. Enable optional notifications to get know when
a reef crosses a threshold of heating.

## Features

- **Ranked panel list** of ~200+ reefs across every major coral biogeographic
  region (Coral Triangle, Caribbean, Red Sea, Pacific Islands, etc.). Sort by
  current DHW or by thermal-stress streak.
- **Per-reef details** — Line graph of DHW and SSTA over the configurable
  history window, with NOAA Alert Level threshold rules.
- **Map tab** — World map with colored pins representing reefs.
- **Optional notifications** — Default off (yay)

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
   to `com.example.reefwatch` — change it to something unique under your
   account.
3. Select a destination (iPhone simulator or your connected device) and ⌘R.

The first cold launch fetches ~156 daily time-series from NOAA's PacIOOS
ERDDAP node and takes a moment. Subsequent launches restore from cache
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

Source: NOAA Coral Reef Watch. 2018, updated daily. NOAA Coral Reef Watch
Version 3.1 Daily Global 5 km Satellite Sea Surface Temperature and DHW
Products. College Park, Maryland, USA: NOAA Coral Reef Watch.

[crw]: https://coralreefwatch.noaa.gov/product/5km/
[erddap]: https://pae-paha.pacioos.hawaii.edu/erddap/

## Notes

- Bundle identifier (`com.example.reefwatch`) is set in the `.pbxproj`. Maybe change this.
