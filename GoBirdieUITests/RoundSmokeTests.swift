import XCTest
import CoreLocation

/// Quick smoke test: plays only the first 3 holes then ends the round via menu.
/// Useful for fast CI validation without running all 18 holes.
final class RoundSmokeTests: XCTestCase {

    var app: XCUIApplication!
    var roundData: RoundData!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITest"]
        app.launch()

        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "test_round", withExtension: "json") else {
            throw XCTSkip("test_round.json not in test bundle")
        }
        roundData = try JSONDecoder().decode(RoundData.self, from: Data(contentsOf: url))
    }

//    func testThreeHoleSmokeRound() throws {
//        // Start round
//        app.tabBars.buttons["Round"].tap()
//
//        let startBtn = app.buttons["startRoundButton"]
//        XCTAssertTrue(startBtn.waitForExistence(timeout: 10))
//        startBtn.tap()
//
//        // Search for course, then tap the first result
//        let searchField = app.textFields["Search by name"]
//        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
//        searchField.tap()
//        searchField.typeText(roundData.course_name + "\n")
//
//        let firstCourse = app.scrollViews.buttons.firstMatch
//        XCTAssertTrue(firstCourse.waitForExistence(timeout: 20))
//        firstCourse.tap()
//
//        // Start on hole 1
//        let startOnHole = app.buttons.matching(
//            NSPredicate(format: "label CONTAINS[c] 'Start on Hole'")
//        ).firstMatch
//        if startOnHole.waitForExistence(timeout: 10) {
//            startOnHole.tap()
//        }
//
//        XCTAssertTrue(app.staticTexts["holeLabel"].waitForExistence(timeout: 10))
//
//        // Play 3 holes
//        let holesToPlay = Array(roundData.holes.prefix(1))
//        for (i, hole) in holesToPlay.enumerated() {
//            // Mark shots
//            for (si, shot) in hole.shots.enumerated() {
//                setLocation(hole: hole.hole_number, shot: si + 1)
//                sleep(1)
//
//                app.buttons["markShotButton"].tap()
//                selectClub(shot.club_display)
//            }
//
//            // Putts
//            let puttPlus = app.buttons["puttPlus"]
//            for _ in 0..<hole.putts {
//                puttPlus.tap()
//                usleep(300_000)
//            }
//
//            // Switch to map and back on hole 2
//            if i == 1 {
//                app.tabBars.buttons["Map"].tap()
//                sleep(2)
//                app.tabBars.buttons["Round"].tap()
//                sleep(1)
//            }
//
//            // Next hole
//            app.buttons["nextHoleButton"].tap()
//            sleep(1)
//        }
//
//        // End round via menu -> End Round -> confirm
//        let menuBtn = app.buttons["roundMenu"]
//        menuBtn.tap()
//
//        // 2. Find and Tap "End Round" using a coordinate to avoid idling hangs
//        let endRound = app.descendants(matching: .any)["endRoundMenu"]
//        XCTAssertTrue(endRound.waitForExistence(timeout: 5))
//        // This taps the center of the element without waiting for the app to be "idle"
//        endRound.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
//
//        // 3. Confirm the Alert
//        // Using 'firstMatch' can sometimes bypass hierarchy depth issues
//        let confirm = app.alerts.buttons["confirmEndRound"].firstMatch
//        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
//        confirm.tap()
//        
//        // Verify round ended
//        let startAgain = app.buttons["startRoundButton"]
//        XCTAssertTrue(startAgain.waitForExistence(timeout: 20), "Should return to start state")
//        sleep(5)
//
//        // Verify scorecard was saved
//        app.tabBars.buttons["Scorecards"].tap()
//        let scorecardCell = app.staticTexts.containing(
//            NSPredicate(format: "label CONTAINS[c] 'Hansen Dam'")
//        ).firstMatch
//        XCTAssertTrue(scorecardCell.waitForExistence(timeout: 10), "Saved round should appear in Scorecards")
//    }

    // MARK: - Helpers

    private func selectClub(_ garminName: String) {
        let nameMap: [String: String] = [
            "Driver": "Driver", "3-Wood": "3 Wood", "5-Wood": "5 Wood",
            "3-Hybrid": "3 Hybrid", "4-Hybrid": "4 Hybrid",
            "5-Hybrid": "5 Hybrid", "Hybrid": "5 Hybrid",
            "4-Iron": "4 Iron", "5-Iron": "5 Iron", "6-Iron": "6 Iron",
            "7-Iron": "7 Iron", "8-Iron": "8 Iron", "9-Iron": "9 Iron",
            "PW": "Pitching Wedge", "GW": "Gap Wedge",
            "SW": "Sand Wedge", "LW": "Lob Wedge",
        ]
        let display = nameMap[garminName] ?? garminName

        guard app.navigationBars["Select Club"].waitForExistence(timeout: 5) else {
            if app.buttons["Skip"].exists { app.buttons["Skip"].tap() }
            return
        }

        let cell = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", display)).firstMatch
        if cell.waitForExistence(timeout: 3) {
            cell.tap()
        } else if app.buttons["Skip"].exists {
            app.buttons["Skip"].tap()
        }
    }

    private func setLocation(hole: Int, shot: Int) {
        guard let holeData = roundData.holes.first(where: { $0.hole_number == hole }),
              shot - 1 < holeData.shots.count else { return }
        let s = holeData.shots[shot - 1]
        let cl = CLLocation(latitude: s.lat, longitude: s.lon)
        XCUIDevice.shared.location = XCUILocation(location: cl)
    }
}
