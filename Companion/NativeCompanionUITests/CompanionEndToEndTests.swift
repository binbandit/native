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
        let name = app.textFields["hostName"]
        // A quick confirmation on the Mac can come before the code is ever looked for.
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in code.exists || name.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 30), .completed, "the phone shows the verification code")
        // Someone clicks Pair on the Mac now.
        XCTAssertTrue(name.waitForExistence(timeout: 180), "the Mac confirmed")
        if let label = environment["COMPANION_HOST_LABEL"] {
            // Pairing a host again keeps its old name in the field.
            let current = name.value as? String ?? ""
            name.tap()
            name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + label)
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
        let composer = app.descendants(matching: .any)["composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        // `COMPANION_MODEL` and `COMPANION_MODE` pick the agent's model and mode from the phone first
        // (the cheap model, and a mode that asks before running commands).
        for (category, key) in [("model", "COMPANION_MODEL"), ("mode", "COMPANION_MODE")] {
            guard let wanted = environment[key] else { continue }
            choose(wanted, in: category, app: app)
        }
        attachScreenshot(app, named: "task")
        composer.tap()
        composer.typeText(prompt)
        app.buttons["send"].tap()
        XCTAssertFalse(app.staticTexts["notSent"].waitForExistence(timeout: 3), "the message was accepted")
        let allow = app.buttons["permission-allow_once"]
        XCTAssertTrue(allow.waitForExistence(timeout: 240), "the agent asked for permission")
        sleep(2)
        attachScreenshot(app, named: "approval")
        // `COMPANION_LEAVE_PENDING=1` leaves the request for another look (in the other appearance).
        if environment["COMPANION_LEAVE_PENDING"] == "1" { return }
        allow.tap()
        XCTAssertTrue(
            app.staticTexts["Allowed from this iPhone"].waitForExistence(timeout: 30), "the answer reached the host")
        attachScreenshot(app, named: "answered")
    }

    /// Names the host currently called `COMPANION_HOST_FROM` as `COMPANION_HOST_LABEL`, from its page.
    func testLabelHost() throws {
        let from = try XCTUnwrap(environment["COMPANION_HOST_FROM"])
        let label = try XCTUnwrap(environment["COMPANION_HOST_LABEL"])
        let app = XCUIApplication()
        app.launch()
        let row = app.buttons["host-\(from)"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        let field = app.textFields["hostLabel"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(label)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["host-\(label)"].waitForExistence(timeout: 10))
    }

    /// Walks the main screens in `COMPANION_APPEARANCE` (light or dark) and attaches each one.
    func testScreens() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appearance", environment["COMPANION_APPEARANCE"] ?? "light"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 10))
        sleep(3)
        attachScreenshot(app, named: "home")
        if let label = environment["COMPANION_HOST_LABEL"] {
            app.buttons["host-\(label)"].tap()
            sleep(2)
            attachScreenshot(app, named: "host")
            app.swipeUp()
            attachScreenshot(app, named: "host-more")
            app.navigationBars.buttons.firstMatch.tap()
        }
        app.buttons["settings"].tap()
        sleep(1)
        attachScreenshot(app, named: "settings")
        app.buttons["addHost"].tap()
        sleep(2)
        attachScreenshot(app, named: "add-host")
    }

    /// Settings › App Icon and Celebrations in `COMPANION_APPEARANCE`, then turns on
    /// `COMPANION_CELEBRATION` (a celebration id showing today), accepts iOS's alert and attaches
    /// the home screen with its icon. `COMPANION_CELEBRATION_OFF=1` turns it off again afterwards.
    func testAppIconAndCelebrations() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appearance", environment["COMPANION_APPEARANCE"] ?? "light"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 10))
        app.buttons["settings"].tap()
        app.buttons["appIcon"].tap()
        XCTAssertTrue(app.navigationBars["App Icon"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "app-icon")
        app.buttons["celebrations"].tap()
        XCTAssertTrue(app.navigationBars["Celebrations"].waitForExistence(timeout: 5))
        sleep(1)
        attachScreenshot(app, named: "celebrations")
        if let id = environment["COMPANION_CELEBRATION"] {
            let toggle = app.switches["celebration-\(id)"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            toggle.switches.firstMatch.tap()
            acceptIconAlert()
            sleep(1)
            attachScreenshot(app, named: "celebration-on")
            app.navigationBars["Celebrations"].buttons.firstMatch.tap()
            sleep(1)
            attachScreenshot(app, named: "app-icon-celebration")
            if environment["COMPANION_CELEBRATION_OFF"] == "1" {
                app.buttons["celebrations"].tap()
                toggle.switches.firstMatch.tap()
                acceptIconAlert()
            }
        }
        XCUIDevice.shared.press(.home)
        sleep(2)
        attachScreenshot(XCUIApplication(bundleIdentifier: "com.apple.springboard"), named: "home-screen")
    }

    /// Picks `COMPANION_HOST_LABEL` in the home screen's host chip and attaches the chip's menu,
    /// home with the host picked, and its newest task's header. `COMPANION_HOST_COLOR` and
    /// `COMPANION_HOST_ICON` (theme ids) set its color and app icon on its page first.
    func testHostChip() throws {
        let label = try XCTUnwrap(environment["COMPANION_HOST_LABEL"])
        let app = XCUIApplication()
        app.launchArguments += ["-appearance", environment["COMPANION_APPEARANCE"] ?? "light"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 10))
        if environment["COMPANION_HOST_COLOR"] != nil || environment["COMPANION_HOST_ICON"] != nil {
            app.buttons["host-\(label)"].tap()
            if let color = environment["COMPANION_HOST_COLOR"] {
                let swatch = app.buttons["hostColor-\(color)"]
                XCTAssertTrue(swatch.waitForExistence(timeout: 5))
                swatch.tap()
            }
            if let icon = environment["COMPANION_HOST_ICON"] {
                let picker = app.buttons["hostAppIcon"]
                XCTAssertTrue(picker.waitForExistence(timeout: 5))
                picker.tap()
                sleep(1)
                attachScreenshot(app, named: "host-icon-picker")
                app.buttons["hostIcon-\(icon)"].tap()
                acceptIconAlert()
                app.navigationBars.buttons.firstMatch.tap()
            }
            sleep(1)
            attachScreenshot(app, named: "host-page")
            app.navigationBars.buttons.firstMatch.tap()
        }
        let chip = app.buttons["hostChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        sleep(1)
        attachScreenshot(app, named: "chip-menu")
        app.buttons[label].firstMatch.tap()
        acceptIconAlert()
        sleep(1)
        attachScreenshot(app, named: "home-host")
        let task = app.buttons.matching(identifier: "task-\(label)").firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.tap()
        sleep(3)
        attachScreenshot(app, named: "task")
    }

    /// Sets the home screen's host chip back to All Hosts.
    func testAllHosts() throws {
        let app = XCUIApplication()
        app.launch()
        let chip = app.buttons["hostChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()
        app.buttons["All Hosts"].firstMatch.tap()
        acceptIconAlert()
    }

    /// Opens the newest task of `COMPANION_HOST_LABEL` and attaches it, with whatever approval is
    /// waiting, without answering.
    func testTaskScreen() throws {
        let label = try XCTUnwrap(environment["COMPANION_HOST_LABEL"])
        let app = XCUIApplication()
        app.launchArguments += ["-appearance", environment["COMPANION_APPEARANCE"] ?? "light"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 10))
        sleep(2)
        attachScreenshot(app, named: "home")
        let task = app.buttons.matching(identifier: "task-\(label)").firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 30))
        task.tap()
        sleep(4)
        attachScreenshot(app, named: "task")
    }

    /// iOS confirms every icon change with an alert of its own.
    private func acceptIconAlert() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let ok = springboard.alerts.buttons["OK"]
        if ok.waitForExistence(timeout: 4) {
            attachScreenshot(springboard, named: "icon-alert")
            ok.tap()
        }
    }

    private func choose(_ wanted: String, in category: String, app: XCUIApplication) {
        let pill = app.descendants(matching: .any)["config-\(category)"]
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "the agent offers a \(category)")
        pill.tap()
        let choice = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", wanted)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "the agent offers \(wanted)")
        choice.tap()
        let chosen = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS[c] %@", "config-\(category)", wanted))
            .firstMatch
        XCTAssertTrue(chosen.waitForExistence(timeout: 15), "the host applied \(wanted)")
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
