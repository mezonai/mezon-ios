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
            try testCase.acceptLicenseAgreementIfPresent(file: file, line: line)
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

        if !channelList.exists || !channelList.isHittable {
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
        try testCase.acceptLicenseAgreementIfPresent(file: file, line: line)
    }

    private func selectClan(_ id: String, in list: XCUIElement, file: StaticString, line: UInt) throws {
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in list.isHittable }, object: list)
        guard XCTWaiter.wait(for: [visible], timeout: 10) == .completed else {
            XCTFail("Clan sidebar is not visible.", file: file, line: line)
            throw InteractionError.unavailable
        }

        let clan = list.descendants(matching: .any)
            .matching(identifier: AccessibilityID.Clan.item(id)).firstMatch
        let items = list.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", AccessibilityID.Clan.item("")))
        // Do not require a visible clan before scrolling: the viewport may contain
        // only unread DMs or the trailing create/join actions.
        var observedIDs = Set<String>()
        func rememberItems() {
            observedIDs.formUnion(items.allElementsBoundByIndex.map { $0.identifier })
        }
        rememberItems()
        // Short drags overlap viewports; fast swipes can skip clans between snapshots.
        for scrollingDown in [true, false] {
            for _ in 0..<24 {
                if clan.exists && clan.isHittable { break }
                let startY: CGFloat = scrollingDown ? 0.75 : 0.25
                let endY: CGFloat = scrollingDown ? 0.25 : 0.75
                list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                    .press(forDuration: 0.1, thenDragTo:
                        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY)))
                rememberItems()
            }
            if clan.exists && clan.isHittable { break }
        }
        guard clan.exists && clan.isHittable else {
            let found = clan.exists
            let details = "Target exists: \(found)\nObserved clan identifiers: \(observedIDs.sorted().joined(separator: ", "))\n\(list.debugDescription)"
            let attachment = XCTAttachment(string: details)
            attachment.name = "Clan selection diagnostics"
            attachment.lifetime = .keepAlways
            testCase.add(attachment)
            let reason = found
                ? "is exposed but not hittable. Check overlays, accessibility frame and sidebar layout."
                : "was not exposed after scrolling. Check clan loading, account membership and accessibility identifiers."
            XCTFail("Clan \(id) \(reason)", file: file, line: line)
            throw InteractionError.unavailable
        }
        clan.tap()
    }

    /// Sends a real message. Refuses to append to an existing user draft.
    func sendText(_ text: String, verifyDraft: Bool = false, rapidTap: Bool = false, file: StaticString = #filePath, line: UInt = #line) throws {
        try testCase.acceptLicenseAgreementIfPresent(timeout: 0, file: file, line: line)
        guard input.waitForExistence(timeout: 15) else {
            attachUIHierarchy()
            XCTFail("Composer is absent from accessibility. Check the chat UIKit/Texture bridge and channel permissions.", file: file, line: line)
            throw InteractionError.unavailable
        }
        let editable = NSPredicate { _, _ in self.input.exists && self.input.isEnabled && self.input.isHittable }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: editable, object: app)], timeout: 10) == .completed else {
            attachUIHierarchy()
            let exists = input.exists
            let enabled = exists && input.isEnabled
            let hittable = exists && input.isHittable
            let frame = exists ? String(describing: input.frame) : "unavailable"
            let appAlerts = app.alerts.count
            let systemAlerts = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count
            let details = "exists=\(exists), enabled=\(enabled), hittable=\(hittable), frame=\(frame), appAlerts=\(appAlerts), systemAlerts=\(systemAlerts)"
            let attachment = XCTAttachment(string: details)
            attachment.name = "Composer interaction state"
            attachment.lifetime = .keepAlways
            testCase.add(attachment)
            XCTFail("Composer unavailable: \(details). See Failure screenshot and Chat accessibility hierarchy.", file: file, line: line)
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
        try submitDraft(rapidTap: rapidTap, file: file, line: line)
    }

    private func submitDraft(rapidTap: Bool = false, file: StaticString, line: UInt) throws {
        let ready = NSPredicate { _, _ in self.sendButton.exists && self.sendButton.isEnabled && self.sendButton.isHittable }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 10) == .completed else {
            XCTFail("Send button did not become available", file: file, line: line)
            throw InteractionError.unavailable
        }
        if rapidTap {
            sendButton.doubleTap()
        } else {
            sendButton.tap()
        }
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

    func react(toText text: String, emojiID: String, search: String? = nil,
               file: StaticString = #filePath, line: UInt = #line) throws {
        let source = try uniqueMessageText(text, file: file, line: line)
        let sourceID = String(source.identifier.dropFirst(AccessibilityID.Chat.messageText("").count))
        let reactionCounts = message(id: sourceID).staticTexts
            .matching(identifier: AccessibilityID.Chat.reactionCount(emojiID))
        XCTAssertEqual(reactionCounts.count, 0, "Expected a fresh message without the target reaction", file: file, line: line)

        if let search {
            try tapMessageAction(AccessibilityID.Chat.reactionPicker, on: source, file: file, line: line)
            let field = app.textFields[AccessibilityID.Chat.emojiSearch]
            XCTAssertTrue(field.waitForExistence(timeout: 10), "Reaction search did not appear", file: file, line: line)
            field.tap()
            field.typeText(search)
            let result = app.descendants(matching: .any)
                .matching(identifier: AccessibilityID.Chat.emojiItem(emojiID)).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 15), "Expected emoji in search results", file: file, line: line)
            result.tap()
        } else {
            try tapMessageAction(AccessibilityID.Chat.quickReaction(emojiID), on: source, file: file, line: line)
        }
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

    func copyAndResend(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let source = try uniqueMessageText(text, file: file, line: line)
        let sourceIdentifier = source.identifier
        try tapMessageAction(AccessibilityID.Chat.copyAction, on: source, file: file, line: line)
        XCTAssertEqual(input.value as? String, "", "Composer should be empty before pasting", file: file, line: line)
        input.tap()
        input.press(forDuration: 1)
        let pasteLabel = NSPredicate(format: "label IN %@", ["Paste", "Dán"])
        let menuItem = app.menuItems.matching(pasteLabel).firstMatch
        let button = app.buttons.matching(pasteLabel).firstMatch
        let ready = NSPredicate { _, _ in menuItem.isHittable || button.isHittable }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 5) == .completed else {
            XCTFail("System Paste action did not appear", file: file, line: line)
            throw InteractionError.unavailable
        }
        (menuItem.isHittable ? menuItem : button).tap()
        XCTAssertEqual(input.value as? String, text, "Paste must reproduce the copied message", file: file, line: line)
        try submitDraft(file: file, line: line)
        assertMessageSent(text, excludingIdentifier: sourceIdentifier, file: file, line: line)
    }

    func assertSingleMessage(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let matches = messages.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@",
            AccessibilityID.Chat.messageText(""), text
        ))
        let duplicate = NSPredicate { _, _ in matches.count > 1 }
        let expectation = XCTNSPredicateExpectation(predicate: duplicate, object: app)
        expectation.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed,
                       "More than one copy of the message appeared", file: file, line: line)
        XCTAssertEqual(matches.count, 1, file: file, line: line)
    }

    func assertDraftSurvivesDetailsTab(_ tabIdentifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let draft = "draft " + UUID().uuidString.prefix(8)
        XCTAssertTrue(input.waitForExistence(timeout: 15), file: file, line: line)
        XCTAssertEqual(input.value as? String, "", file: file, line: line)
        input.tap()
        input.typeText(draft)
        XCTAssertEqual(input.value as? String, draft, file: file, line: line)

        openDetailsTab(tabIdentifier, file: file, line: line)
        closeDetails(file: file, line: line)
        XCTAssertTrue(input.waitForExistence(timeout: 10), file: file, line: line)
        let actual = input.value as? String
        if actual == draft {
            input.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: draft.count))
        }
        XCTAssertEqual(actual, draft, "Draft changed after leaving the details tab", file: file, line: line)
    }

    func openDetailsTab(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let details = app.staticTexts[AccessibilityID.Chat.channelDetails]
        let ready = NSPredicate { _, _ in details.exists && details.isHittable }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 10) == .completed else {
            XCTFail("Channel details did not become tappable within 10 seconds", file: file, line: line)
            return
        }
        details.tap()
        let tab = app.staticTexts[identifier]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Channel details tab is missing", file: file, line: line)
        tab.tap()
    }

    func closeDetails(file: StaticString = #filePath, line: UInt = #line) {
        let back = app.buttons[AccessibilityID.Chat.detailsBack]
        XCTAssertTrue(back.exists && back.isHittable, file: file, line: line)
        back.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Chat did not return", file: file, line: line)
    }

    func setPinned(_ pinned: Bool, text: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let source = try uniqueMessageText(text, file: file, line: line)
        let action = pinned ? AccessibilityID.Chat.pinAction : AccessibilityID.Chat.unpinAction
        try tapMessageAction(action, on: source, file: file, line: line)
        let titles = pinned ? ["Pin Message", "Ghim tin nhắn"] : ["Unpin Message", "Bỏ ghim tin nhắn"]
        let alert = app.alerts.matching(NSPredicate(format: "label IN %@", titles)).firstMatch
        let yes = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Yes", "Đồng ý"])).firstMatch
        XCTAssertTrue(yes.waitForExistence(timeout: 5), "Pin confirmation is missing", file: file, line: line)
        yes.tap()

        let feedback = pinned ? ["Message pinned successfully", "Ghim tin nhắn thành công"] : ["Message unpinned", "Đã bỏ ghim"]
        let success = app.staticTexts.matching(NSPredicate(format: "label IN %@", feedback)).firstMatch
        guard success.waitForExistence(timeout: 10) else {
            XCTFail("App did not confirm the pin change", file: file, line: line)
            throw InteractionError.unavailable
        }
        guard success.waitForNonExistence(timeout: 10) else {
            XCTFail("Pin confirmation toast did not disappear within 10 seconds", file: file, line: line)
            throw InteractionError.unavailable
        }
    }

    func pinnedMessage(id: String) -> XCUIElement {
        app.staticTexts[AccessibilityID.Chat.pinnedMessage(id)]
    }

    func tapPinnedMessageRow(id: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let rows = app.cells.containing(.staticText, identifier: AccessibilityID.Chat.pinnedMessage(id))
        let row = rows.firstMatch
        let ready = NSPredicate { _, _ in rows.count == 1 && row.isHittable }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 15) == .completed else {
            XCTFail("Expected one tappable pinned message row for ID \(id)", file: file, line: line)
            throw InteractionError.unavailable
        }
        row.tap()
    }

    func unpinFromList(id: String, file: StaticString = #filePath, line: UInt = #line) {
        let unpin = app.buttons[AccessibilityID.Chat.pinnedMessageUnpin(id)]
        XCTAssertTrue(unpin.waitForExistence(timeout: 10), file: file, line: line)
        unpin.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label IN %@", ["Unpin", "Bỏ ghim"])).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Unpin confirmation is missing", file: file, line: line)
        confirm.tap()
        XCTAssertTrue(pinnedMessage(id: id).waitForNonExistence(timeout: 15),
                      "The pinned entry should disappear after confirming", file: file, line: line)
    }

    func checkComposerSuggestion(
        trigger: String, identifierPrefix: String, send: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertTrue(input.waitForExistence(timeout: 15), file: file, line: line)
        XCTAssertEqual(input.value as? String, "", file: file, line: line)
        input.tap()
        input.typeText(trigger)
        // Any visible suggestion of the requested kind is valid for these cases.
        let suggestions = app.staticTexts.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", identifierPrefix
        ))
        let visible = NSPredicate { _, _ in
            suggestions.allElementsBoundByIndex.contains { $0.isHittable }
        }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: app)], timeout: 15) == .completed,
              let suggestion = suggestions.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("Expected a visible composer suggestion for \(trigger)", file: file, line: line)
            throw InteractionError.unavailable
        }
        if !send {
            input.typeText(XCUIKeyboardKey.delete.rawValue)
            return
        }

        let name = suggestion.label
        suggestion.tap()
        let marker = "qa-" + UUID().uuidString.prefix(8)
        input.typeText(marker)
        try submitDraft(file: file, line: line)

        let message = messages.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            AccessibilityID.Chat.messageText(""), marker
        )).firstMatch
        let finished = NSPredicate { _, _ in
            message.exists && ["sent", "failed"].contains(message.value as? String ?? "")
        }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: finished, object: app)], timeout: 45) == .completed else {
            let reason = message.exists ? "Message never reached a final delivery state" : "Message text was not found after sending"
            XCTFail(reason, file: file, line: line)
            throw InteractionError.unavailable
        }
        XCTAssertEqual(message.value as? String, "sent", "App reports message delivery failed", file: file, line: line)
        XCTAssertTrue(message.label.contains(name), "Sent message is missing the selected suggestion '\(name)'. Actual text: \(message.label)", file: file, line: line)
        XCTAssertEqual(input.value as? String, "", file: file, line: line)
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
        _ text: String, allowingInlineCodePadding: Bool = false, excludingIdentifier: String? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let labels = allowingInlineCodePadding ? [text, "\u{2009}\(text)\u{2009}"] : [text]
        let matches = messages.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label IN %@",
            AccessibilityID.Chat.messageText(""), labels
        ))
        let sentText = excludingIdentifier.map {
            matches.matching(NSPredicate(format: "identifier != %@", $0)).firstMatch
        } ?? matches.firstMatch
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
