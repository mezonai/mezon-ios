import XCTest

class BaseUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if let testRun = testRun, testRun.hasSucceeded == false {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app?.terminate()
        app = nil
    }

    private enum AuthenticationError: Error { case setupFailed }

    /// Preserve an existing login. Authenticate only if normal startup shows auth UI.
    func launchAndEnsureLoggedIn(file: StaticString = #filePath, line: UInt = #line) throws {
        app.launchArguments.removeAll {
            $0 == UITestLaunch.loginArgument || $0 == UITestLaunch.resetSessionArgument
        }
        app.launch()
        let login = LoginScreen(app: app)
        let welcome = app.buttons["auth.welcome.start"]
        let resolved = NSPredicate { _, _ in
            login.authenticatedRoot.exists || welcome.exists || login.submit.exists
        }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: resolved, object: app)], timeout: 60) == .completed else {
            XCTFail("App did not reach the main or login screen during startup", file: file, line: line)
            throw AuthenticationError.setupFailed
        }
        if login.authenticatedRoot.exists { return }

        guard let email = UITestConfiguration.Login.email,
              let otp = UITestConfiguration.Login.otp else {
            throw XCTSkip("No saved login. Set UITEST_EMAIL and UITEST_OTP in MezonChat/_Tests/uitest.env or Test environment variables.")
        }
        guard otp.utf8.count == 6, otp.utf8.allSatisfy({ (48...57).contains($0) }) else {
            XCTFail("UITEST_OTP must contain exactly 6 digits", file: file, line: line)
            throw AuthenticationError.setupFailed
        }

        // Relaunch only after observing auth UI to select email OTP deterministically.
        // Do not clear persisted credentials; the dedicated login tests own that option.
        login.launch(mode: .emailOTP, resetSession: false, file: file, line: line)
        login.enter(email, into: login.email, file: file, line: line)
        assertEnabled(login.submit, true, file: file, line: line)
        login.submit.tap()
        guard login.otpDigit(0).waitForExistence(timeout: 30) else {
            XCTFail("Login setup could not request OTP", file: file, line: line)
            throw AuthenticationError.setupFailed
        }
        for (index, digit) in otp.enumerated() {
            login.enter(String(digit), into: login.otpDigit(index), file: file, line: line)
        }
        // The app verifies automatically after the sixth digit.
        guard login.authenticatedRoot.waitForExistence(timeout: 60) else {
            XCTFail("Login setup failed. Check the configured OTP, network, and account onboarding.", file: file, line: line)
            throw AuthenticationError.setupFailed
        }
    }

    func assertEnabled(_ element: XCUIElement, _ expected: Bool,
                       file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "enabled == %@", NSNumber(value: expected))
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "Expected enabled = \(expected)", file: file, line: line)
    }
}
