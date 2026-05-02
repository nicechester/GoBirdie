import XCTest
import CoreLocation

/// Test Plan 1 of 3 — iPhone: Start a round and stop.
/// Leaves the app on the active round view so Plan 2 (Watch) can take over.
final class Plan1_PhoneStartRound: XCTestCase {

    var app: XCUIApplication!
    var roundData: TestRoundData!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITest"]
        app.activate()
        allowLocationIfPrompted()
        roundData = try loadTestRound()
    }

    override func tearDownWithError() throws {
        // Do not terminate — app must stay alive for Plan 2
    }

    func test01_StartAndPlayRound() throws {
        app.tabBars.buttons["Round"].tap()

        let startBtn = app.buttons["startRoundButton"]
        XCTAssertTrue(startBtn.waitForExistence(timeout: 10))
        startBtn.tap()

        let searchField = app.textFields["Search by name"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText(roundData.course_name + "\n")

        let firstCourse = app.scrollViews.buttons.firstMatch
        XCTAssertTrue(firstCourse.waitForExistence(timeout: 20))
        firstCourse.tap()

        let startOnHole = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Start on Hole'")
        ).firstMatch
        if startOnHole.waitForExistence(timeout: 60) {
            startOnHole.tap()
        }

        // Verify active round view is showing — hand off to watch from here
        XCTAssertTrue(app.staticTexts["holeLabel"].waitForExistence(timeout: 10),
                      "iPhone should show active round on hole 1")
    }

    private func allowLocationIfPrompted() {
        addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            let whileUsing = alert.buttons["Allow While Using App"]
            if whileUsing.exists { whileUsing.tap(); return true }
            let allow = alert.buttons["Allow"]
            if allow.exists { allow.tap(); return true }
            return false
        }
        app.tap()
    }

    private func loadTestRound() throws -> TestRoundData {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "test_round", withExtension: "json") else {
            throw XCTSkip("test_round.json not found")
        }
        return try JSONDecoder().decode(TestRoundData.self, from: Data(contentsOf: url))
    }
}
