import XCTest

/// Page object: keep selectors and UI actions out of test scenarios.
struct LoginScreen {
    enum Mode: String {
        case sms = "0", emailOTP = "1", password = "2"
    }

    let app: XCUIApplication
    var email: XCUIElement { app.textFields["auth.login.email"] }
    var phone: XCUIElement { app.textFields["auth.login.phone"] }
    var password: XCUIElement { app.secureTextFields["auth.login.password"] }
    // App language may be persisted independently of the simulator locale.
    var invalidOTPMessage: XCUIElement {
        app.staticTexts.matching(NSPredicate(
            format: "label IN %@", ["OTP invalid", "Mã OTP không hợp lệ"]
        )).firstMatch
    }
    var otpSubmit: XCUIElement { app.buttons["auth.otp.submit"] }
    var authenticatedRoot: XCUIElement { app.otherElements["main.root"] }
    func otpDigit(_ index: Int) -> XCUIElement { app.textFields["auth.otp.digit.\(index)"] }
    var submit: XCUIElement { app.buttons["auth.login.submit"] }

    func launch(mode: Mode, resetSession: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        app.launchArguments = [
            UITestLaunch.loginArgument,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        if resetSession {
            app.launchArguments.append(UITestLaunch.resetSessionArgument)
        }
        app.launchEnvironment[UITestLaunch.loginModeEnvironmentKey] = mode.rawValue
        app.launch()
        guard app.wait(for: .runningForeground, timeout: 15) else {
            XCTFail("Mezon did not stay in foreground after launch (state: \(app.state.rawValue)). Check app crash logs and the test runner log.", file: file, line: line)
            return
        }
        XCUIDevice.shared.orientation = .portrait
        let start = app.buttons["auth.welcome.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "Welcome did not appear", file: file, line: line)
        start.tap()
        XCTAssertTrue(submit.waitForExistence(timeout: 15), "Login did not appear", file: file, line: line)
    }

    func enter(_ text: String, into field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), file: file, line: line)
        field.tap()
        field.typeText(text)
    }

    /// Tap the trailing edge so the cursor is at the end, then type.
    /// A normal tap can land in the middle of existing text.
    func typeAtEnd(_ text: String, in field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), file: file, line: line)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        field.typeText(text)
    }
}
