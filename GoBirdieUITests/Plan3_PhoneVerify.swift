import XCTest

/// Test Plan 3 of 3 — iPhone: Verify round saved by Watch appears in Scorecards.
/// Assumes Plan 2 (Watch) has already ended the round.
///
/// Run order: Plan1_PhoneStartRound → Plan2_WatchPlayRound → Plan3_PhoneVerify
/// Shell: run_watch_integration.sh
final class Plan3_PhoneVerify: XCTestCase {

    var app: XCUIApplication!
    var roundData: TestRoundData!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Attach to the already-running app instead of relaunching
        app = XCUIApplication()
        app.activate()
        addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            let whileUsing = alert.buttons["Allow While Using App"]
            if whileUsing.exists { whileUsing.tap(); return true }
            let allow = alert.buttons["Allow"]
            if allow.exists { allow.tap(); return true }
            return false
        }
        app.tap()
        roundData = try loadTestRound()
    }

    func test03_VerifyRoundSaved() throws {
        // Phone should be back to empty round state (watch ended the round)
        app.tabBars.buttons["Round"].tap()
        let startBtn = app.buttons["startRoundButton"]
        XCTAssertTrue(startBtn.waitForExistence(timeout: 15),
                      "Phone should show empty round state after watch ended round")

        // Navigate to Scorecards
        app.tabBars.buttons["Scorecards"].tap()

        // Verify round appears
        let card = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", roundData.course_name)
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10),
                      "Round from watch should appear in Scorecards")

        // Open the round and verify it has shots
        card.tap()
        sleep(2)

        // Scorecard detail should show holes played
        let holesPlayed = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'H1'")
        ).firstMatch
        XCTAssertTrue(holesPlayed.waitForExistence(timeout: 5),
                      "Scorecard should show hole data")
    }

    private func loadTestRound() throws -> TestRoundData {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "test_round", withExtension: "json") else {
            throw XCTSkip("test_round.json not found")
        }
        return try JSONDecoder().decode(TestRoundData.self, from: Data(contentsOf: url))
    }
}
