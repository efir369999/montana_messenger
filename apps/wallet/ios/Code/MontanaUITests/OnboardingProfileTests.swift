import XCTest

// End-to-end check of the first run: a profile filled in before the identity exists
// must survive its coming into being and be readable afterwards.
// Written because two "fixes by reasoning" failed to cure an empty profile.
final class OnboardingProfileTests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    func testProfileFilledDuringFirstRunSurvivesIdentityBirth() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        // 1. intro -> Create
        let create = app.buttons["Create"]
        XCTAssertTrue(create.waitForExistence(timeout: 20), "intro screen did not appear")
        create.tap()

        // 2. profile step: type a name, then Done
        let first = app.textFields["First name"]
        XCTAssertTrue(first.waitForExistence(timeout: 20), "profile step did not appear right after Create")
        first.tap(); first.typeText("Alik")

        let last = app.textFields["Last name"]
        if last.exists { last.tap(); last.typeText("Montana") }

        app.buttons["Done"].tap()

        // 3. responsibility -> seed -> the identity screen
        let understood = app.switches.firstMatch
        if understood.waitForExistence(timeout: 10) { understood.tap() }
        if app.buttons["Show Words"].waitForExistence(timeout: 10) { app.buttons["Show Words"].tap() }

        let saved = app.switches.firstMatch
        if saved.waitForExistence(timeout: 20) { saved.tap() }
        let mine = app.buttons["Your identity in Montana"]
        XCTAssertTrue(mine.waitForExistence(timeout: 20), "seed screen did not appear")
        mine.tap()

        // 4. the name must be visible in the app once the identity is in place
        let name = app.staticTexts["Alik"]
        let found = name.waitForExistence(timeout: 40) || app.staticTexts["Alik Montana"].waitForExistence(timeout: 5)
        XCTAssertTrue(found, "the profile filled in during the first run is gone once the identity is in place")
    }
}
