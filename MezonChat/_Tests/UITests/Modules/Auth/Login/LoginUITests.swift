import XCTest

final class LoginUITests: BaseUITestCase {
    /// Integration test: requires the backend test account and its fixed OTP.
    func testEmailOTPLoginSucceeds() throws {
        guard let email = UITestConfiguration.Login.email, let otp = UITestConfiguration.Login.otp else {
            throw XCTSkip("Set UITEST_EMAIL and UITEST_OTP in MezonChat/_Tests/uitest.env")
        }
        let screen = LoginScreen(app: app)
        screen.launch(mode: .emailOTP)
        screen.enter(email, into: screen.email)
        assertEnabled(screen.submit, true)
        screen.submit.tap()

        XCTAssertTrue(screen.otpDigit(0).waitForExistence(timeout: 30),
                      "OTP screen did not appear after requesting a code. Check the backend/network.")
        for (index, digit) in otp.enumerated() {
            screen.enter(String(digit), into: screen.otpDigit(index))
        }
        // The app automatically verifies as soon as the sixth digit is entered.
        // Wait for the result instead of querying/tapping a button on the departing screen.
        XCTAssertTrue(screen.authenticatedRoot.waitForExistence(timeout: 60),
                      "Login did not reach the main screen. Check OTP acceptance and whether the test account needs username setup.")
        XCTAssertFalse(screen.otpDigit(0).exists, "OTP screen should close after login")
        XCTAssertFalse(screen.email.exists, "Login screen should close after login")
    }

    /// Integration test: the backend must reject the configured invalid OTP.
    func testEmailOTPLoginRejectsIncorrectCode() throws {
        guard let email = UITestConfiguration.Login.email else {
            throw XCTSkip("Set UITEST_EMAIL in MezonChat/_Tests/uitest.env")
        }
        let screen = LoginScreen(app: app)
        screen.launch(mode: .emailOTP)
        screen.enter(email, into: screen.email)
        assertEnabled(screen.submit, true)
        screen.submit.tap()

        XCTAssertTrue(screen.otpDigit(0).waitForExistence(timeout: 30),
                      "OTP screen did not appear after requesting a code. Check the backend/network.")
        XCTAssertFalse(screen.invalidOTPMessage.exists, "No OTP error should appear before verification")
        for (index, digit) in UITestConfiguration.Login.invalidOTP.enumerated() {
            screen.enter(String(digit), into: screen.otpDigit(index))
        }

        // Entering the sixth digit automatically submits. Observe the rejection first
        // so the test cannot pass merely because the request is still in flight.
        XCTAssertTrue(screen.invalidOTPMessage.waitForExistence(timeout: 30),
                      "Expected an invalid OTP message after submitting the incorrect code")
        XCTAssertTrue(screen.otpDigit(0).exists, "OTP entry should remain available after rejection")
        XCTAssertTrue(screen.otpSubmit.exists, "OTP action should remain available after rejection")
        XCTAssertFalse(screen.authenticatedRoot.exists, "Incorrect OTP must not open the main screen")
    }

    func testEmailOTPRejectsInvalidEmail() {
        let screen = LoginScreen(app: app)
        screen.launch(mode: .emailOTP)
        let address = "ui-test@example.com"
        screen.enter(address, into: screen.email)
        XCTAssertEqual(screen.email.value as? String, address)
        assertEnabled(screen.submit, true)
        screen.typeAtEnd(" ", in: screen.email)
        XCTAssertEqual(screen.email.value as? String, address + " ")
        assertEnabled(screen.submit, false)
    }

    func testEmailOTPEnablesSubmitForValidEmailAndDisablesAfterClearing() {
        let screen = LoginScreen(app: app)
        screen.launch(mode: .emailOTP)
        let address = "ui-test@example.com"
        screen.enter(address, into: screen.email)
        assertEnabled(screen.submit, true)
        screen.email.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: address.count))
        assertEnabled(screen.submit, false)
    }

    func testSMSRequiresValidVietnamesePhoneLength() {
        let screen = LoginScreen(app: app)
        screen.launch(mode: .sms)
        assertEnabled(screen.submit, false)
        screen.enter("09123", into: screen.phone)
        assertEnabled(screen.submit, false)
        screen.phone.typeText("45678")
        assertEnabled(screen.submit, true)
        screen.phone.typeText("9")
        assertEnabled(screen.submit, false)
    }

    func testPasswordLoginRequiresEmailAndPassword() {
        let screen = LoginScreen(app: app)
        screen.launch(mode: .password)
        assertEnabled(screen.submit, false)
        XCTAssertTrue(screen.password.exists)
        screen.enter("ui-test@example.com", into: screen.email)
        assertEnabled(screen.submit, false)
        screen.enter("test-password", into: screen.password)
        assertEnabled(screen.submit, true)
    }

    func testPasswordLoginRejectsInvalidEmailEvenWithPassword() {
        let screen = LoginScreen(app: app)
        screen.launch(mode: .password)
        let address = "ui-test@example.com"
        screen.enter(address, into: screen.email)
        XCTAssertEqual(screen.email.value as? String, address)
        screen.enter("test-password", into: screen.password)
        assertEnabled(screen.submit, true)
        screen.typeAtEnd(" ", in: screen.email)
        XCTAssertEqual(screen.email.value as? String, address + " ")
        assertEnabled(screen.submit, false)
    }
}
