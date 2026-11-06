import XCTest

struct ChannelScreen {
    let app: XCUIApplication
    private enum InteractionError: Error { case unavailable }

    var screen: XCUIElement { app.otherElements[AccessibilityID.Chat.screen] }
    var input: XCUIElement { app.textViews[AccessibilityID.Chat.input] }
    var sendButton: XCUIElement { app.buttons[AccessibilityID.Chat.send] }
    var messages: XCUIElement {
        app.descendants(matching: .any).matching(identifier: AccessibilityID.Chat.messages).firstMatch
    }

    func message(id: String) -> XCUIElement {
        messages.descendants(matching: .any)
            .matching(identifier: AccessibilityID.Chat.message(id)).firstMatch
    }

    func openChannel(id: String?, name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        // Handle app restoration into a previously opened conversation.
        let prefix = AccessibilityID.Chat.channelRow("")
        let titlePredicate: NSPredicate
        if let id {
            titlePredicate = NSPredicate(format: "identifier == %@", AccessibilityID.Chat.channelRow(id))
        } else {
            titlePredicate = NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", prefix, name)
        }
        // UITableViewCell is a Texture wrapper; its title carries the channel ID.
        let titles = app.staticTexts.matching(titlePredicate)
        let rows = app.cells.containing(titlePredicate)
        let ready = NSPredicate { _, _ in self.screen.exists || rows.count > 0 }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 20) == .completed else {
            XCTFail("Log in and select the test clan first. Channel \(name) was not found.", file: file, line: line)
            throw InteractionError.unavailable
        }
        if screen.exists {
            if let id, screen.value as? String == id { return }
            let back = app.buttons[AccessibilityID.Chat.back]
            guard back.waitForExistence(timeout: 5), back.isHittable else {
                XCTFail("Cannot return to the channel list", file: file, line: line)
                throw InteractionError.unavailable
            }
            back.tap()
        }
        guard rows.firstMatch.waitForExistence(timeout: 15), rows.count == 1 else {
            XCTFail("Expected exactly one channel. Set UITEST_CHANNEL_ID if names are duplicated, and open the correct clan.", file: file, line: line)
            throw InteractionError.unavailable
        }
        let row = rows.firstMatch
        // Capture the selected data ID so the resulting screen can be verified even with name fallback.
        let title = row.staticTexts.matching(titlePredicate).firstMatch
        guard title.waitForExistence(timeout: 5), titles.count == 1,
              title.identifier.hasPrefix(prefix) else {
            XCTFail("Expected one channel title with a data identifier inside the selected cell", file: file, line: line)
            throw InteractionError.unavailable
        }
        let selectedID = String(title.identifier.dropFirst(prefix.count))
        row.tap()
        let opened = NSPredicate { _, _ in self.screen.exists && self.screen.value as? String == selectedID }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: opened, object: app)], timeout: 15) == .completed else {
            XCTFail("The selected channel did not open", file: file, line: line)
            throw InteractionError.unavailable
        }
    }

    /// Sends a real message. Refuses to append to an existing user draft.
    func sendText(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws {
        guard input.waitForExistence(timeout: 15) else {
            attachUIHierarchy()
            XCTFail("Composer is absent from accessibility. Check the chat UIKit/Texture bridge and channel permissions.", file: file, line: line)
            throw InteractionError.unavailable
        }
        let editable = NSPredicate { _, _ in self.input.exists && self.input.isEnabled && self.input.isHittable }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: editable, object: app)], timeout: 10) == .completed else {
            attachUIHierarchy()
            XCTFail("Composer exists but is not enabled/hittable. Check overlays, permissions, and layout.", file: file, line: line)
            throw InteractionError.unavailable
        }
        guard (input.value as? String ?? "").isEmpty else {
            XCTFail("Clear the existing draft in the test channel before running", file: file, line: line)
            throw InteractionError.unavailable
        }
        input.tap()
        input.typeText(text)
        let ready = NSPredicate { _, _ in self.sendButton.exists && self.sendButton.isEnabled && self.sendButton.isHittable }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 10) == .completed else {
            XCTFail("Send button did not become available", file: file, line: line)
            throw InteractionError.unavailable
        }
        sendButton.tap()
    }

    private func uniqueMessageText(_ text: String, file: StaticString, line: UInt) throws -> XCUIElement {
        let matches = messages.staticTexts.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@",
            AccessibilityID.Chat.messageText(""), text
        ))
        guard matches.firstMatch.waitForExistence(timeout: 10), matches.count == 1 else {
            attachUIHierarchy()
            XCTFail("Expected one message text in the conversation list", file: file, line: line)
            throw InteractionError.unavailable
        }
        return matches.element(boundBy: 0)
    }

    /// Long-press the actual text leaf, not every ancestor containing that text.
    func beginReply(toText text: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let source = try uniqueMessageText(text, file: file, line: line)
        let sourceID = String(source.identifier.dropFirst(AccessibilityID.Chat.messageText("").count))
        guard source.isHittable else {
            XCTFail("Source message is not visible for long press", file: file, line: line)
            throw InteractionError.unavailable
        }
        source.press(forDuration: 0.8)
        let menus = app.scrollViews.matching(identifier: AccessibilityID.Chat.messageMenu)
        guard menus.firstMatch.waitForExistence(timeout: 10), menus.count == 1 else {
            attachUIHierarchy()
            XCTFail("Message menu did not appear in accessibility after long press", file: file, line: line)
            throw InteractionError.unavailable
        }
        let actions = menus.element(boundBy: 0).buttons.matching(identifier: AccessibilityID.Chat.replyAction)
        let ready = NSPredicate { _, _ in actions.count == 1 && actions.element(boundBy: 0).isHittable }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 10) == .completed else {
            attachUIHierarchy()
            XCTFail("Expected one visible Reply action in the message menu", file: file, line: line)
            throw InteractionError.unavailable
        }
        actions.element(boundBy: 0).tap()
        let banner = app.staticTexts.matching(identifier: AccessibilityID.Chat.replyBanner)
        let selected = NSPredicate { _, _ in
            banner.count == 1 && banner.element(boundBy: 0).value as? String == sourceID
        }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: app)], timeout: 10) == .completed else {
            XCTFail("Composer did not enter reply mode for the selected message", file: file, line: line)
            throw InteractionError.unavailable
        }
        return sourceID
    }

    func assertReply(_ text: String, references sourceID: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let replyText = try uniqueMessageText(text, file: file, line: line)
        let replyID = String(replyText.identifier.dropFirst(AccessibilityID.Chat.messageText("").count))
        let reference = message(id: replyID).staticTexts.matching(identifier: AccessibilityID.Chat.replyReference)
        let correctReference = NSPredicate { _, _ in
            reference.count == 1 && reference.element(boundBy: 0).value as? String == sourceID
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: correctReference, object: app)], timeout: 10),
                       .completed, "Sent reply must reference the original message", file: file, line: line)
        let cleared = NSPredicate { _, _ in
            self.app.staticTexts.matching(identifier: AccessibilityID.Chat.replyBanner).count == 0
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: cleared, object: app)], timeout: 5),
                       .completed, "Composer should leave reply mode after sending", file: file, line: line)
    }

    func react(toText text: String, emojiID: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let source = try uniqueMessageText(text, file: file, line: line)
        let sourceID = String(source.identifier.dropFirst(AccessibilityID.Chat.messageText("").count))
        let reactionCounts = message(id: sourceID).staticTexts
            .matching(identifier: AccessibilityID.Chat.reactionCount(emojiID))
        // This case creates a new message, so an existing reaction is unexpected.
        guard reactionCounts.count == 0 else {
            XCTFail("Expected a fresh message without the target reaction", file: file, line: line)
            throw InteractionError.unavailable
        }
        guard source.isHittable else {
            XCTFail("Source message is not visible for long press", file: file, line: line)
            throw InteractionError.unavailable
        }
        source.press(forDuration: 0.8)
        let menus = app.scrollViews.matching(identifier: AccessibilityID.Chat.messageMenu)
        guard menus.firstMatch.waitForExistence(timeout: 10), menus.count == 1 else {
            attachUIHierarchy()
            XCTFail("Expected one message action menu", file: file, line: line)
            throw InteractionError.unavailable
        }
        let buttons = menus.element(boundBy: 0).buttons
            .matching(identifier: AccessibilityID.Chat.quickReaction(emojiID))
        let ready = NSPredicate { _, _ in
            buttons.count == 1 && buttons.element(boundBy: 0).isEnabled && buttons.element(boundBy: 0).isHittable
        }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 10) == .completed else {
            attachUIHierarchy()
            XCTFail("The requested quick reaction is unavailable", file: file, line: line)
            throw InteractionError.unavailable
        }
        buttons.element(boundBy: 0).tap()
        let applied = NSPredicate { _, _ in
            guard menus.count == 0, reactionCounts.count == 1 else { return false }
            let count = reactionCounts.element(boundBy: 0)
            return count.isSelected && (Int(count.label) ?? 0) > 0
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: applied, object: app)], timeout: 30),
                       .completed, "Expected the chosen reaction on the source message, selected by the current user", file: file, line: line)
    }

    private func attachUIHierarchy() {
        XCTContext.runActivity(named: "Composer accessibility diagnostics") { activity in
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "Chat accessibility hierarchy"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    func assertMessageSent(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let sentText = messages.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@",
            AccessibilityID.Chat.messageText(""), text
        )).firstMatch
        let finished = NSPredicate { _, _ in
            sentText.exists && ["sent", "failed"].contains(sentText.value as? String ?? "")
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: finished, object: app)], timeout: 45)
        guard result == .completed else {
            XCTFail("New message did not reach sent/failed within 45 seconds (missing or still pending)", file: file, line: line)
            return
        }
        XCTAssertEqual(sentText.value as? String, "sent", "App reports message delivery failed", file: file, line: line)
        let cleared = NSPredicate { _, _ in self.input.exists && (self.input.value as? String ?? "").isEmpty }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: cleared, object: app)], timeout: 5),
                       .completed, "Composer should clear after sending", file: file, line: line)
    }
}
