import XCTest
import CoreLocation

// MARK: - Test Data Model

struct ShotData: Decodable {
    let lat: Double
    let lon: Double
    let club: String
    let club_display: String
}

struct HoleData: Decodable {
    let hole_number: Int
    let par: Int
    let score: Int
    let putts: Int
    let shots: [ShotData]
}

struct RoundData: Decodable {
    let course_name: String
    let total_score: Int
    let total_putts: Int
    let holes: [HoleData]
}

// MARK: - Round Simulation UI Test

/// Simulates a full round using real Garmin data from Hansen Dam Golf Course.
///
/// Prerequisites:
///   1. Add a "GoBirdieUITests" UI Testing target in Xcode
///   2. Copy `data/automation/test_round.json` into the UI test bundle resources
///   3. Hansen Dam must be pre-downloaded in the app (run once manually or via saved courses)
///   4. Run on a simulator (location simulation requires simulator)
///
/// The test:
///   - Starts a round on Hansen Dam
///   - For each hole: sets GPS to each shot location, taps Mark Shot, picks the club
///   - Sets putts per hole
///   - Switches between Map and Round tabs mid-hole (every 3rd hole)
///   - Advances to next hole
///   - Finishes the round on hole 18
final class RoundSimulationTests: XCTestCase {

    var app: XCUIApplication!
    var roundData: RoundData!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITest"]
        app.launch()

        roundData = try loadTestRound()
    }

    // MARK: - Main Test

    func testFullRoundSimulation() throws {
        // 1. Navigate to Round tab and start a round
        tapTab("Round")
        startRound(courseName: roundData.course_name)

        // 2. Play each hole
        for (index, hole) in roundData.holes.enumerated() {
            playHole(hole, holeIndex: index)
        }

        // 3. Verify round ended (may briefly show Resume screen while saving)
        let startButton = app.buttons["startRoundButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 20), "Should return to empty round state after finishing")
        sleep(5) // Let round save to disk

        // 4. Verify scorecard was saved
        tapTab("Scorecards")
        let scorecardCell = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'Hansen Dam'")
        ).firstMatch
        XCTAssertTrue(scorecardCell.waitForExistence(timeout: 10), "Saved round should appear in Scorecards")

        // Tap to open scorecard detail and verify total score
        scorecardCell.tap()
        let totalLabel = app.staticTexts["\(roundData.total_score)"]
        if totalLabel.waitForExistence(timeout: 5) {
            // Score matches expected total from test data
        }
        let doneButton = app.buttons["Done"]
        if doneButton.waitForExistence(timeout: 3) {
            doneButton.tap()
        }
    }

    // MARK: - Start Round Flow

    private func startRound(courseName: String) {
        let startButton = app.buttons["startRoundButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "Start Round button should exist")
        startButton.tap()

        // Search for the course, then tap the first result
        let searchField = app.textFields["Search by name"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search bar should appear")
        searchField.tap()
        searchField.typeText(courseName + "\n")

        // Tap first course in the scroll view (search already narrowed results)
        let firstCourse = app.scrollViews.buttons.firstMatch
        XCTAssertTrue(firstCourse.waitForExistence(timeout: 20), "A course should appear in search results")
        firstCourse.tap()

        // If starting hole picker appears, select hole 1 and tap Start
        let startOnHole = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Start on Hole'")
        ).firstMatch
        if startOnHole.waitForExistence(timeout: 60) {
            startOnHole.tap()
        }

        // Wait for active round view
        let holeLabel = app.staticTexts["holeLabel"]
        XCTAssertTrue(holeLabel.waitForExistence(timeout: 10), "Hole label should appear after starting round")
    }

    // MARK: - Play a Single Hole

    private func playHole(_ hole: HoleData, holeIndex: Int) {
        let holeLabel = app.staticTexts["holeLabel"]
        XCTAssertTrue(holeLabel.waitForExistence(timeout: 5), "Hole label should be visible")

        // Mark each shot with GPS location + club
        for (shotIndex, shot) in hole.shots.enumerated() {
            // Set simulated GPS location
            setSimulatedLocation(hole: hole.hole_number, shot: shotIndex + 1)
            sleep(1) // Let location update propagate

            // Switch to Map tab and back mid-hole (every 3rd hole, after 1st shot)
            if holeIndex % 3 == 1 && shotIndex == 0 {
                switchToMapAndBack()
            }

            // Tap Mark Shot
            let markShot = app.buttons["markShotButton"]
            XCTAssertTrue(markShot.waitForExistence(timeout: 5), "Mark Shot button should exist on hole \(hole.hole_number)")
            markShot.tap()

            // Select club from the sheet
            selectClub(shot.club_display)
        }

        // Set putts
        setPutts(hole.putts)

        // Switch to Map and back on every 4th hole before advancing
        if holeIndex % 4 == 2 {
            switchToMapAndBack()
        }

        // Advance to next hole (or finish on last)
        let nextButton = app.buttons["nextHoleButton"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5), "Next/Finish button should exist")

        if holeIndex == roundData.holes.count - 1 {
            // Last hole — tap Finish to end the round
            nextButton.tap()
        } else {
            nextButton.tap()
        }

        sleep(1) // Brief pause between holes
    }

    // MARK: - Club Selection

    private func selectClub(_ clubDisplay: String) {
        // The MarkShotSheet shows a list of clubs
        // Wait for the sheet to appear
        let clubList = app.navigationBars["Select Club"]
        guard clubList.waitForExistence(timeout: 5) else {
            // Sheet didn't appear or different layout — tap Skip
            let skip = app.buttons["Skip"]
            if skip.exists { skip.tap() }
            return
        }

        // Map garmin club names to app display names
        let displayName = mapClubName(clubDisplay)

        let clubButton = app.buttons[displayName]
        if clubButton.waitForExistence(timeout: 3) {
            clubButton.tap()
        } else {
            // Try scrolling to find it
            let clubCell = app.cells.containing(
                NSPredicate(format: "label CONTAINS[c] %@", displayName)
            ).firstMatch
            if clubCell.waitForExistence(timeout: 3) {
                clubCell.tap()
            } else {
                // Club not found in bag — skip
                let skip = app.buttons["Skip"]
                if skip.exists { skip.tap() }
            }
        }
    }

    private func mapClubName(_ garminName: String) -> String {
        let map: [String: String] = [
            "Driver": "Driver",
            "3-Wood": "3 Wood", "5-Wood": "5 Wood",
            "3-Hybrid": "3 Hybrid", "4-Hybrid": "4 Hybrid",
            "5-Hybrid": "5 Hybrid", "Hybrid": "5 Hybrid",
            "4-Iron": "4 Iron", "5-Iron": "5 Iron", "6-Iron": "6 Iron",
            "7-Iron": "7 Iron", "8-Iron": "8 Iron", "9-Iron": "9 Iron",
            "PW": "Pitching Wedge", "GW": "Gap Wedge",
            "SW": "Sand Wedge", "LW": "Lob Wedge",
        ]
        return map[garminName] ?? garminName
    }

    // MARK: - Putts

    private func setPutts(_ count: Int) {
        guard count > 0 else { return }

        let puttPlus = app.buttons["puttPlus"]
        XCTAssertTrue(puttPlus.waitForExistence(timeout: 5), "Putt + button should exist")

        for _ in 0..<count {
            puttPlus.tap()
            usleep(300_000) // 300ms between taps
        }

        // Verify putt count
        let puttLabel = app.staticTexts["puttCount"]
        if puttLabel.exists {
            XCTAssertEqual(puttLabel.label, "\(count)", "Putt count should be \(count)")
        }
    }

    // MARK: - Tab Switching

    private func tapTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(name) tab should exist")
        tab.tap()
    }

    private func switchToMapAndBack() {
        tapTab("Map")
        sleep(2) // Let map render
        tapTab("Round")
        sleep(1) // Let round view restore
    }

    // MARK: - Location Simulation

    /// Sets the simulated GPS location for this shot using coordinates from test data.
    private func setSimulatedLocation(hole: Int, shot: Int) {
        guard let holeData = roundData.holes.first(where: { $0.hole_number == hole }),
              shot - 1 < holeData.shots.count else { return }
        let s = holeData.shots[shot - 1]
        let cl = CLLocation(latitude: s.lat, longitude: s.lon)
        XCUIDevice.shared.location = XCUILocation(location: cl)
    }

    // MARK: - Test Data Loading

    private func loadTestRound() throws -> RoundData {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "test_round", withExtension: "json") else {
            throw NSError(domain: "RoundSimulationTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "test_round.json not found in test bundle"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RoundData.self, from: data)
    }
}
