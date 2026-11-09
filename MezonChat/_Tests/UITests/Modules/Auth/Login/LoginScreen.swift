import XCTest

/// Page object: keep selectors and UI actions out of test scenarios.
struct LoginScreen {
    enum Mode: String {
        case sms = "0", emailOTP = "1", password = "2"
    }

    let app: XCUIApplication
    var email: XCUIElement { app.textFields[AccessibilityID.Auth.email] }
    var phone: XCUIElement { app.textFields[AccessibilityID.Auth.phone] }
    var password: XCUIElement { app.secureTextFields[AccessibilityID.Auth.password] }
    // App language may be persisted independently of the simulator locale.
    var invalidOTPMessage: XCUIElement {
        app.staticTexts.matching(NSPredicate(
            format: "label IN %@", ["OTP invalid", "Mã OTP không hợp lệ"]
        )).firstMatch
    }
    var otpSubmit: XCUIElement { app.buttons[AccessibilityID.Auth.otpSubmit] }
    var authenticatedRoot: XCUIElement { app.otherElements[AccessibilityID.Main.root] }
    func otpDigit(_ index: Int) -> XCUIElement { app.textFields[AccessibilityID.Auth.otpDigit(index)] }
    var submit: XCUIElement { app.buttons[AccessibilityID.Auth.submit] }

    func launch(mode: Mode, resetSession: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        let chatMetadataArguments = app.launchArguments.filter { $0 == UITestLaunch.chatMetadataArgument }
        app.launchArguments = [
            UITestLaunch.loginArgument,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ] + chatMetadataArguments
        if resetSession {
            app.launchArguments.append(UITestLaunch.resetSessionArgument)
        }
        app.launchEnvironment[UITestLaunch.loginModeEnvironmentKey] = mode.rawValue
        app.launch()
        guard app.wait(for: .runningForeground, timeout: 15) else {
            XCTFail("Mezon did not stay in foreground after launch (state: \(app.state.rawValue)). Check app crash logs and the test runner log.", file: file, line: line)
            return
        }
        let start = app.buttons[AccessibilityID.Auth.welcomeStart]
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
