import XCTest

/// Drives the companion against real Native hosts on this Mac (`docs/companion.md`, "Verifying").
/// The Mac side (confirming pairings, starting the Codex session) is done by the person or script
/// running these; values come in as `TEST_RUNNER_*` environment variables from `xcodebuild test`.
final class CompanionEndToEndTests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    /// Opens a pairing link (`COMPANION_INVITE`), waits while the Mac confirms, and names the host
    /// `COMPANION_HOST_LABEL`. `COMPANION_FORGET=1` starts from a phone that never paired.
    func testPairWithInvite() throws {
        let invite = try XCTUnwrap(environment["COMPANION_INVITE"].flatMap(URL.init(string:)))
        let app = XCUIApplication()
        if environment["COMPANION_FORGET"] == "1" { app.launchArguments.append("-companionForgetPairings") }
        app.launch()
        app.open(invite)
        // iOS asks before a link opens an app.
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if open.waitForExistence(timeout: 5) { open.tap() }
        let code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Confirm on'")).firstMatch
        if !code.waitForExistence(timeout: 30) { print("HIERARCHY\n\(app.debugDescription)") }
        XCTAssertTrue(code.exists, "the phone shows the verification code")
        // Someone clicks Pair on the Mac now.
        let name = app.textFields["hostName"]
        XCTAssertTrue(name.waitForExistence(timeout: 180), "the Mac confirmed")
        if let label = environment["COMPANION_HOST_LABEL"] {
            name.tap()
            name.typeText(label)
        }
        app.buttons["pairingDone"].tap()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 10))
    }

    /// Lists the tasks of `COMPANION_HOST_LABEL`, opens the newest, sends `COMPANION_PROMPT`, and
    /// allows the permission request the agent makes for it.
    func testSendPromptAndApprove() throws {
        let label = try XCTUnwrap(environment["COMPANION_HOST_LABEL"])
        let prompt = try XCTUnwrap(environment["COMPANION_PROMPT"])
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 10))
        let task = app.buttons.matching(identifier: "task-\(label)").firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 30), "the host's tasks are listed")
        task.tap()
        let composer = app.textViews["composer"].exists ? app.textViews["composer"] : app.textFields["composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        composer.tap()
        composer.typeText(prompt)
        app.buttons["send"].tap()
        XCTAssertFalse(app.staticTexts["notSent"].waitForExistence(timeout: 3), "the message was accepted")
        let allow = app.buttons["permission-allow_once"]
        XCTAssertTrue(allow.waitForExistence(timeout: 240), "the agent asked for permission")
        attachScreenshot(app, named: "approval")
        allow.tap()
        XCTAssertTrue(app.staticTexts["Allowed from this iPhone"].waitForExistence(timeout: 30), "the answer reached the host")
        attachScreenshot(app, named: "answered")
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
