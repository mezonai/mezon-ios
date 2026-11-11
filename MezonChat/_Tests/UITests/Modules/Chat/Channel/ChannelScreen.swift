import XCTest

struct ChannelScreen {
    let app: XCUIApplication
    let testCase: BaseUITestCase
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
        guard let clanID = UITestConfiguration.Channel.clanID else {
            throw XCTSkip("Set UITEST_CLAN_ID in MezonChat/_Tests/uitest.env or Test environment variables to run channel tests.")
        }
        guard let numericClanID = Int64(clanID), numericClanID > 0 else {
            XCTFail("Set UITEST_CLAN_ID to the numeric ID of the automation clan.", file: file, line: line)
            throw InteractionError.unavailable
        }

        let clanList = app.collectionViews[AccessibilityID.Clan.list]
        let channelList = app.tables[AccessibilityID.Clan.channelList(String(numericClanID))]
        let sidebarOrChat = NSPredicate { _, _ in clanList.isHittable || self.screen.exists }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: sidebarOrChat, object: app)], timeout: 20) == .completed else {
            XCTFail("Neither the clan sidebar nor a chat screen appeared.", file: file, line: line)
            throw InteractionError.unavailable
        }

        if screen.exists {
            let back = app.buttons[AccessibilityID.Chat.back]
            guard back.waitForExistence(timeout: 5), back.isHittable else {
                XCTFail("Cannot return to the clan sidebar.", file: file, line: line)
                throw InteractionError.unavailable
            }
            back.tap()
            let sidebarReady = NSPredicate { _, _ in !self.screen.exists && clanList.isHittable }
            guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: sidebarReady, object: app)], timeout: 10) == .completed else {
                XCTFail("The clan sidebar did not become ready after returning from chat.", file: file, line: line)
                throw InteractionError.unavailable
            }
        }

        if !channelList.isHittable {
            try selectClan(String(numericClanID), in: clanList, file: file, line: line)
        }

        let prefix = AccessibilityID.Chat.channelRow("")
        let titlePredicate: NSPredicate
        if let id {
            titlePredicate = NSPredicate(format: "identifier == %@", AccessibilityID.Chat.channelRow(id))
        } else {
            titlePredicate = NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", prefix, name)
        }
        // Scope the lookup to the table bound to the target clan's state.
        let titles = channelList.staticTexts.matching(titlePredicate)
        let rows = channelList.cells.containing(titlePredicate)
        let ready = NSPredicate { _, _ in channelList.isHittable && rows.count > 0 }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 30) == .completed else {
            XCTFail("Channel \(id ?? name) was not found in clan \(clanID).", file: file, line: line)
            throw InteractionError.unavailable
        }
        guard rows.count == 1 else {
            XCTFail("Expected one channel in clan \(clanID). Set UITEST_CHANNEL_ID if names are duplicated.", file: file, line: line)
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

    private func selectClan(_ id: String, in list: XCUIElement, file: StaticString, line: UInt) throws {
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in list.isHittable }, object: list)
        guard XCTWaiter.wait(for: [visible], timeout: 10) == .completed else {
            XCTFail("Clan sidebar is not visible.", file: file, line: line)
            throw InteractionError.unavailable
        }

        let clan = list.descendants(matching: .any)
            .matching(identifier: AccessibilityID.Clan.item(id)).firstMatch
        if !clan.isHittable {
            // A restored sidebar can be scrolled to either side of the target clan.
            for _ in 0..<12 {
                if clan.isHittable { break }
                list.swipeUp()
            }
            for _ in 0..<12 {
                if clan.isHittable { break }
                list.swipeDown()
            }
        }
        guard clan.isHittable else {
            XCTFail("Clan \(id) is not visible in the sidebar. Check that the test account has joined it.", file: file, line: line)
            throw InteractionError.unavailable
        }
        clan.tap()
    }

    /// Sends a real message. Refuses to append to an existing user draft.
    func sendText(_ text: String, verifyDraft: Bool = false, file: StaticString = #filePath, line: UInt = #line) throws {
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
        registerDraftCleanup()
        input.tap()
        input.typeText(text)
        if verifyDraft, input.value as? String != text {
            XCTFail("Composer did not receive the exact message before sending", file: file, line: line)
            throw InteractionError.unavailable
        }
        let ready = NSPredicate { _, _ in self.sendButton.exists && self.sendButton.isEnabled && self.sendButton.isHittable }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 10) == .completed else {
            XCTFail("Send button did not become available", file: file, line: line)
            throw InteractionError.unavailable
        }
        sendButton.tap()
    }

    private func registerDraftCleanup() {
        let app = self.app
        let screen = self.screen
        let input = self.input
        guard let channelID = screen.value as? String else { return }
        testCase.tearDownCleanup = {
            guard app.state == .runningForeground, screen.exists,
                  screen.value as? String == channelID, input.exists,
                  let draft = input.value as? String, !draft.isEmpty else { return }

            let editable = NSPredicate { _, _ in input.isEnabled && input.isHittable }
            guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: editable, object: input)], timeout: 5) == .completed else {
                XCTFail("Cannot clear the test draft because the composer is unavailable.")
                return
            }
            input.tap()
            input.typeKey("a", modifierFlags: .command)
            input.typeText(XCUIKeyboardKey.delete.rawValue)
            guard input.value as? String == "" else {
                XCTFail("The test draft could not be cleared.")
                return
            }
            // Backgrounding flushes the draft store before the runner terminates the app.
            XCUIDevice.shared.press(.home)
        }
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
        try tapMessageAction(AccessibilityID.Chat.replyAction, on: source, file: file, line: line)
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
        try tapMessageAction(AccessibilityID.Chat.quickReaction(emojiID), on: source, file: file, line: line)
        let menus = app.scrollViews.matching(identifier: AccessibilityID.Chat.messageMenu)
        let applied = NSPredicate { _, _ in
            guard menus.count == 0, reactionCounts.count == 1 else { return false }
            let count = reactionCounts.element(boundBy: 0)
            return count.isSelected && (Int(count.label) ?? 0) > 0
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: applied, object: app)], timeout: 30),
                       .completed, "Expected the chosen reaction on the source message, selected by the current user", file: file, line: line)
    }

    private func tapMessageAction(
        _ identifier: String, on source: XCUIElement,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
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
        let menu = menus.element(boundBy: 0)
        let actions = menu.buttons.matching(identifier: identifier)
        let action = actions.firstMatch
        guard action.waitForExistence(timeout: 10) else {
            attachUIHierarchy()
            XCTFail("Message action did not appear: \(identifier)", file: file, line: line)
            throw InteractionError.unavailable
        }
        // Give the presentation animation time to finish before scrolling.
        let hittable = NSPredicate { _, _ in action.isHittable }
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: action)], timeout: 1) != .completed {
            for _ in 0..<3 {
                guard action.exists, !action.isHittable, menu.isHittable else { break }
                menu.swipeUp()
            }
        }
        let ready = NSPredicate { _, _ in actions.count == 1 && action.isEnabled && action.isHittable }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 10) == .completed else {
            attachUIHierarchy()
            XCTFail("Expected one enabled and visible action: \(identifier)", file: file, line: line)
            throw InteractionError.unavailable
        }
        action.tap()
    }

    func messageID(for text: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let element = try uniqueMessageText(text, file: file, line: line)
        return String(element.identifier.dropFirst(AccessibilityID.Chat.messageText("").count))
    }

    func messageContent(id: String) -> XCUIElement {
        messages.descendants(matching: .any).matching(identifier: AccessibilityID.Chat.messageText(id)).firstMatch
    }

    func assertCannotSend(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let editable = NSPredicate { _, _ in self.input.exists && self.input.isEnabled && self.input.isHittable }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: editable, object: app)], timeout: 10) == .completed else {
            XCTFail("Composer did not become editable", file: file, line: line)
            return
        }
        guard input.value as? String == "" else {
            XCTFail("Clear the existing draft in the test channel before running", file: file, line: line)
            return
        }
        if !text.isEmpty { registerDraftCleanup() }
        input.tap()
        let newlineOnly = !text.isEmpty && text.allSatisfy { $0.isNewline }
        let messageItems = messages.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", AccessibilityID.Chat.message(""))
        )
        let initialMessageCount = newlineOnly ? messageItems.count : 0
        if !text.isEmpty { input.typeText(text) }
        let draft = input.value as? String
        // UIKit can suppress Return while the text view is empty.
        if newlineOnly {
            XCTAssertTrue(draft == text || draft == "", "Return must not leave sendable text", file: file, line: line)
            let countChanged = NSPredicate { _, _ in messageItems.count != initialMessageCount }
            let noMessageSent = XCTNSPredicateExpectation(predicate: countChanged, object: app)
            noMessageSent.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [noMessageSent], timeout: 2), .completed,
                           "Return must leave the channel message count unchanged", file: file, line: line)
        } else {
            XCTAssertEqual(draft, text, "Expected the invalid draft to be in the composer", file: file, line: line)
        }
        let unavailable = NSPredicate { _, _ in
            !self.sendButton.exists || !self.sendButton.isHittable || !self.sendButton.isEnabled
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: unavailable, object: app)], timeout: 5),
                       .completed, "Send must be unavailable for blank text", file: file, line: line)
    }

    func beginEdit(_ original: String, appending suffix: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let source = try uniqueMessageText(original, file: file, line: line)
        try tapMessageAction(AccessibilityID.Chat.editAction, on: source, file: file, line: line)
        let loaded = NSPredicate { _, _ in self.input.exists && self.input.value as? String == original }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: app)], timeout: 10) == .completed else {
            XCTFail("Edit must load the original message", file: file, line: line)
            throw InteractionError.unavailable
        }
        // Edit focuses the composer. Move the caret to the end without tapping near the emoji button.
        input.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
        input.typeText(suffix)
        XCTAssertEqual(input.value as? String, original + suffix, file: file, line: line)
    }

    func cancelEdit(file: StaticString = #filePath, line: UInt = #line) {
        let cancel = app.buttons[AccessibilityID.Chat.editCancel]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Edit cancel button is missing", file: file, line: line)
        cancel.tap()
        let cleared = NSPredicate { _, _ in !cancel.exists && self.input.exists && self.input.value as? String == "" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: cleared, object: app)], timeout: 5),
                       .completed, "Cancel must exit edit mode and clear the composer", file: file, line: line)
    }

    func deleteMessage(_ text: String, confirm: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let source = try uniqueMessageText(text, file: file, line: line)
        try tapMessageAction(AccessibilityID.Chat.deleteAction, on: source, file: file, line: line)
        let alert = app.alerts.matching(NSPredicate(format: "label IN %@", ["Delete Message", "Xóa tin nhắn"])).firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Delete confirmation did not appear", file: file, line: line)
        let labels = confirm ? ["Yes", "Đồng ý"] : ["No", "Không"]
        let button = alert.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        XCTAssertTrue(button.exists, "Delete confirmation button is missing", file: file, line: line)
        button.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), "Delete confirmation did not close", file: file, line: line)
    }

    private func attachUIHierarchy() {
        XCTContext.runActivity(named: "Composer accessibility diagnostics") { activity in
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "Chat accessibility hierarchy"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    func assertMessageSent(
        _ text: String, allowingInlineCodePadding: Bool = false,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let labels = allowingInlineCodePadding ? [text, "\u{2009}\(text)\u{2009}"] : [text]
        let sentText = messages.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label IN %@",
            AccessibilityID.Chat.messageText(""), labels
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
