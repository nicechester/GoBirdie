# GoBirdie UI Test Automation

## Setup

### 1. Add UI Test Target in Xcode

1. Open `GoBirdie.xcodeproj`
2. File → New → Target → **UI Testing Bundle**
3. Name: `GoBirdieUITests`
4. Target to Test: `GoBirdie`
5. Click Finish

### 2. Add Test Files to Target

Move or reference these files into the `GoBirdieUITests` group:
- `GoBirdieUITests/RoundSimulationTests.swift` (full 18-hole test)
- `GoBirdieUITests/RoundSmokeTests.swift` (quick 3-hole test)

### 3. Add Test Resources

Add these to the **UI test target's** "Copy Bundle Resources" build phase:
- `data/automation/test_round.json`
- All `data/automation/gpx/*.gpx` files (68 shot GPX + StartLocation.gpx)

In Xcode: select the files → File Inspector → Target Membership → check `GoBirdieUITests`.

### 4. Pre-download Hansen Dam

The test expects Hansen Dam Golf Course to already be saved in the app.
Run the app once on the simulator, go to Settings → Manage Courses, and download Hansen Dam.
Alternatively, the test will attempt to find and download it during the start round flow.

### 5. Simulator Location Permission

On first run, the simulator will prompt for location permission. Accept it.
For CI, add `-UITest` to launch arguments and handle the alert in setUp if needed.

## Running

```bash
# Full 18-hole simulation
xcodebuild test \
  -project GoBirdie.xcodeproj \
  -scheme GoBirdie \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:GoBirdieUITests/RoundSimulationTests

# Quick 3-hole smoke test
xcodebuild test \
  -project GoBirdie.xcodeproj \
  -scheme GoBirdie \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:GoBirdieUITests/RoundSmokeTests
```

## Test Data

- **Source**: Real round from 2026-02-14 at Hansen Dam Golf Course (18 holes, score 99)
- **`test_round.json`**: Hole-by-hole data with shot GPS coordinates, clubs, and putts
- **`gpx/H##-S##.gpx`**: Per-shot GPX files for `XCUIDevice.setSimulatedLocation()`
- **`rounds.csv`** / **`holes.csv`**: Full export of all 46 rounds from GoBirdie Desktop

## What the Tests Do

### RoundSimulationTests (full)
For each of the 18 holes:
1. Sets GPS to each shot's real coordinates via GPX
2. Taps **Mark Shot** → selects the correct club from the sheet
3. Sets putts with the +/- stepper
4. Every 3rd hole: switches to **Map tab** and back mid-hole
5. Every 4th hole: switches to **Map tab** before advancing
6. Taps **Next** (or **Finish** on hole 18)

### RoundSmokeTests (quick)
Same flow but only 3 holes, then ends via the menu → End Round.

## Accessibility Identifiers Added

| Identifier | Element | File |
|---|---|---|
| `startRoundButton` | Start Round button | RoundTab.swift |
| `holeLabel` | "Hole N" header text | RoundTab.swift |
| `markShotButton` | Mark Shot button | HoleControlsView.swift |
| `nextHoleButton` | Next / Finish button | HoleControlsView.swift |
| `puttPlus` | Putt + button | HoleControlsView.swift |
| `puttMinus` | Putt - button | HoleControlsView.swift |
| `puttCount` | Putt count label | HoleControlsView.swift |
| `confirmEndRound` | End Round alert confirm | RoundTab.swift |
| `mainTabView` | Main TabView | ContentView.swift |
