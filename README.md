# GoBirdie

A golf GPS and shot tracking app for iPhone and Apple Watch, with desktop sync via [GoBirdie Desktop](../../desktop/GoBirdie-Desktop).

Course data is sourced from OpenStreetMap (Overpass API) and enriched with yardage/handicap from GolfCourseAPI. Rounds sync to the desktop companion over MultipeerConnectivity (Bluetooth + WiFi peer-to-peer).

## Screenshots

### iPhone

| Start Round | Search by Name | Select Start Hole |
|:-:|:-:|:-:|
| ![](screenshots/start-round.png) | ![](screenshots/search-by-name.png) | ![](screenshots/select-start-hole.png) |

| Round View | Map View | Tap to Measure |
|:-:|:-:|:-:|
| ![](screenshots/rounding-view.png) | ![](screenshots/map-view.png) | ![](screenshots/map-view-tap-to-distance.png) |

| Club Selection | Round Initial | |
|:-:|:-:|:-:|
| ![](screenshots/select-club.png) | ![](screenshots/round-initial.png) | |

| Scorecards | Scorecard Detail | Shot Map |
|:-:|:-:|:-:|
| ![](screenshots/score-cards-view.png) | ![](screenshots/score-card-detail.png) | ![](screenshots/score-card-shot-map.png) |

| Swipe to Delete | | |
|:-:|:-:|:-:|
| ![](screenshots/scorecard-view-swipe-delete.png) | | |

### Apple Watch

| Waiting for iPhone | Rounding | Second Page | Round Saved |
|:-:|:-:|:-:|:-:|
| ![](screenshots/watch-waiting-for-iphone.png) | ![](screenshots/watch-rounding.png) | ![](screenshots/watch-second-page.png) | ![](screenshots/watch-saved.png) |

## Features

### Course Discovery
- Search courses by name via Overpass API
- Saved courses shown first, sorted by distance
- Download and manage courses offline (Settings → Manage Courses)
- Hole geometry: fairways, bunkers, water, rough rendered on map

### During a Round
- Live GPS distances to front, pin, and back of green
- Tap anywhere on the map to measure distance from player and to green
- Mark shots with GPS location, club selection, altitude, heart rate, and temperature
- Shot lines with distance labels between consecutive shots
- Line from last shot to green with distance
- Auto-detect on-green (≤ 30 yards to pin) for putt entry
- Mini scorecard with running total
- Orientation lock (portrait) during rounds
- Idle prompt after 30 minutes of inactivity
- Auto-save every 30 seconds + on background for crash recovery
- Resume interrupted rounds

### Shot Map & Scorecards
- Per-hole shot map with club-colored dots and distance lines
- Tee-to-green rotated view for consistent orientation
- Putt count displayed at green
- Swipe to delete rounds
- Historical round review with full shot maps

### Apple Watch
- WatchConnectivity streams hole coordinates from iPhone
- Front / Pin / Back distance display, updated live from Watch GPS
- Mark Shot button (GPS pin) and +1 Stroke button
- Digital Crown navigation between holes
- On-green putt entry with +/− buttons and confirm
- End Round / Cancel Round on second page
- HKWorkoutSession for background GPS and always-on display

### Desktop Sync
- MultipeerConnectivity (Bluetooth + WiFi P2P) — works across different networks
- Toggle sync server on/off in Settings
- Rounds include shot positions, club data, heart rate, altitude, green centers
- Desktop companion shows timeline charts, shot analysis, course stats

## Architecture

```
GoBirdie/
├── GoBirdieCore/          # Swift Package — shared models, storage, API clients
│   └── Sources/
│       ├── Models/        # Round, HoleScore, Shot, Course, Hole, GpsPoint, ClubType
│       ├── Storage/       # RoundStore, CourseStore, InProgressStore (JSON files)
│       ├── API/           # GolfCourseAPIClient
│       ├── OSM/           # OverpassClient, OverpassCache
│       └── Distance/      # DistanceEngine
├── GoBirdie/              # iPhone app
│   ├── AppState.swift     # Round lifecycle, auto-save, idle detection
│   ├── RoundSession.swift # Active round state machine
│   ├── SyncServer.swift   # MultipeerConnectivity advertiser
│   ├── LocationService.swift
│   ├── ConnectivityService.swift  # WatchConnectivity bridge
│   ├── ClubBag.swift      # Customizable club list
│   └── Views/
│       ├── Map/           # MapLibreView, MapOverlayView, MapViewModel
│       ├── Round/         # StartRoundView, MiniScorecardView, HoleControlsView
│       ├── Scorecards/    # ScorecardsTab, ShotMapView
│       └── Settings/      # SettingsView, CourseManagerView
└── GoBirdie Watch App/    # watchOS target
    ├── WatchRoundSession.swift  # Watch-side round state + HKWorkoutSession
    └── WatchRoundView.swift     # Distance, putt, end-round UI
```

## Requirements

- iOS 18+ / watchOS 11+
- Xcode 26+
- Swift 6 (GoBirdieCore uses strict concurrency)

## Build

```bash
open GoBirdie.xcodeproj
```

Select the `GoBirdie` scheme for iPhone or `GoBirdie Watch App` for watchOS. The `GoBirdieCore` Swift Package is resolved automatically.

## Data Storage

All data is stored as JSON files under `Documents/GoBirdie/`:

| Directory | Contents |
|-----------|----------|
| `rounds/` | Completed round data (shots, scores, heart rate timeline) |
| `courses/` | Downloaded course definitions (holes, geometry, tee/green positions) |
| `overpass_cache/` | Cached Overpass API responses |
| `in_progress/` | Auto-saved round state for crash recovery |

## Desktop Sync

1. Open Settings on the iPhone app
2. Toggle "Desktop Sync" on — starts MultipeerConnectivity advertising
3. On the desktop app, click "Sync from iPhone"
4. The desktop discovers the iPhone via Bluetooth/WiFi P2P and pulls round data

No network configuration needed — MultipeerConnectivity works across different WiFi networks and VPNs.
