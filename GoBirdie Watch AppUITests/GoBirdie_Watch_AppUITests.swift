//
//  GoBirdie_Watch_AppUITests.swift
//  GoBirdie Watch AppUITests
//
//  Created by Kim, Chester on 5/1/26.
//

import XCTest
import CoreLocation

final class GoBirdie_Watch_AppUITests: XCTestCase {
    
//    override func setUpWithError() throws {
//        // Put setup code here. This method is called before the invocation of each test method in the class.
//        
//        // In UI tests it is usually best to stop immediately when a failure occurs.
//        continueAfterFailure = false
//        
//        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
//    }
    var watch: XCUIApplication!
    var roundData: TestRoundData!

    override func setUpWithError() throws {
        continueAfterFailure = false
        watch = XCUIApplication()
        watch.launch()
        allowLocationIfPrompted(watch)

        roundData = try loadTestRound()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
//    @MainActor
//    func testExample() throws {
//        // UI tests must launch the application that they test.
//        let app = XCUIApplication()
//        app.launch()
//        
//        // Use XCTAssert and related functions to verify your tests produce the correct results.
//    }
//    
//    @MainActor
//    func testLaunchPerformance() throws {
//        // This measures how long it takes to launch your application.
//        measure(metrics: [XCTApplicationLaunchMetric()]) {
//            XCUIApplication().launch()
//        }
//    }
    
    @MainActor
    func test02_WatchPlayAndEndRound() throws {
        sleep(30)
        // Watch should receive hole data and show Shot button
        let shotBtn = watch.buttons["watch_mark_shot"]
        XCTAssertTrue(shotBtn.waitForExistence(timeout: 20),
                      "Watch should show Shot button after receiving hole data")

        // Play each hole on the watch
        for hole in roundData.holes {
            playHoleOnWatch(hole)
        }

        // Swipe up to EndRoundPage and end round
        swipeUpOnWatch()
        sleep(1)

        let endBtn = watch.buttons["end_round_menu_item"]
        XCTAssertTrue(endBtn.waitForExistence(timeout: 5))
        endBtn.tap()
        sleep(2)

        let doneBtn = watch.buttons["watch_round_ended_done"]
        XCTAssertTrue(doneBtn.waitForExistence(timeout: 10), "Watch should show Round Saved")
        doneBtn.tap()
    }

    private func playHoleOnWatch(_ hole: TestHoleData) {
        // Mark each shot
        for (idx, shot) in hole.shots.enumerated() {
            setSimulatedLocation(lat: shot.lat, lon: shot.lon)
            sleep(1)

            let btn = watch.buttons["watch_mark_shot"]
            XCTAssertTrue(btn.waitForExistence(timeout: 5))
            btn.tap()

            // Club picker — tap first cell or wait for auto-submit (15s)
            let clubList = watch.collectionViews.firstMatch
            if clubList.waitForExistence(timeout: 3) {
                let firstCell = clubList.cells.firstMatch
                if firstCell.waitForExistence(timeout: 2) { firstCell.tap() }
            }
        }

        // Add putts
        let puttBtn = watch.buttons["watch_add_putt"]
        if puttBtn.waitForExistence(timeout: 3) {
            for _ in 0..<hole.putts { puttBtn.tap(); usleep(300_000) }
        }

        // Navigate to next hole (swipe left) — except last hole
        if hole.hole_number < roundData.holes.count {
            swipeToNextHoleOnWatch()
            sleep(1)
        }
    }

    private func swipeToNextHoleOnWatch() {
        let start = watch.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        let end   = watch.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func swipeUpOnWatch() {
        let start = watch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end   = watch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func setSimulatedLocation(lat: Double, lon: Double) {
        XCUIDevice.shared.location = XCUILocation(
            location: CLLocation(latitude: lat, longitude: lon)
        )
    }

    private func allowLocationIfPrompted(_ app: XCUIApplication) {
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
