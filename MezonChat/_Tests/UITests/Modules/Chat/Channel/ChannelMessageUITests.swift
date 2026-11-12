import XCTest

final class ChannelMessageUITests: BaseUITestCase {
    func testSendTextMessage() throws {
        let channel = try openTestChannel()
        let text = "automation test \(UUID().uuidString)"
        try XCTContext.runActivity(named: "Compose and send text message") { _ in
            try channel.sendText(text)
        }
        XCTContext.runActivity(named: "Verify message is sent and composer clears") { _ in
            channel.assertMessageSent(text)
        }
    }
    
    func testReplyTextMessage() throws {
        let channel = try openTestChannel()
        let source = "reply source \(UUID().uuidString)"
        try channel.sendText(source)
        channel.assertMessageSent(source)
        let sourceID = try channel.beginReply(toText: source)

        let reply = "automation reply \(UUID().uuidString)"
        try channel.sendText(reply)
        channel.assertMessageSent(reply)
        try channel.assertReply(reply, references: sourceID)
    }
    
    func testReactTextMessage() throws {
        let channel = try openTestChannel()
        let source = "reaction source \(UUID().uuidString)"
        try channel.sendText(source)
        channel.assertMessageSent(source)

        try channel.react(toText: source, emojiID: "7227274405304181951")
    }

    func testEmptyMessageCannotBeSent() throws {
        try openTestChannel().assertCannotSend("")
    }

    func testSpacesOnlyMessageCannotBeSent() throws {
        try openTestChannel().assertCannotSend("   ")
    }

    func testNewlinesOnlyMessageCannotBeSent() throws {
        try openTestChannel().assertCannotSend("\n\n")
    }

    func testMultilineMessageRendersInChannel() throws {
        let channel = try openTestChannel()
        let text = "Line \(UUID().uuidString)\nSecond line"
        try channel.sendText(text)
        channel.assertMessageSent(text)
    }

    func testVietnameseAndCJKTextRendersInChannel() throws {
        let channel = try openTestChannel()
        let text = "Tiếng Việt 日本語 中文 한국어 \(UUID().uuidString)"
        try channel.sendText(text, verifyDraft: true)
        channel.assertMessageSent(text)
    }

    func testMessagesAppearInSendOrder() throws {
        let channel = try openTestChannel()
        let firstID = try channel.messageID(for: sendShortMessage(in: channel))
        let secondID = try channel.messageID(for: sendShortMessage(in: channel))
        let first = channel.messageContent(id: firstID)
        let second = channel.messageContent(id: secondID)

        XCTAssertTrue(first.exists && second.exists)
        XCTAssertLessThan(first.frame.midY, second.frame.midY, "Newer message should appear below the older one")
    }

    func testBoldMarkdownSendsWithoutFormattingMarkers() throws {
        let channel = try openTestChannel()
        let text = "Bold \(UUID().uuidString)"
        try channel.sendText("**\(text)**")
        channel.assertMessageSent(text)
    }

    func testInlineCodeSendsWithoutBackticks() throws {
        let channel = try openTestChannel()
        let code = "inline \(UUID().uuidString)"
        try channel.sendText("`\(code)`")
        // The inline-code renderer pads the text with thin spaces.
        channel.assertMessageSent(code, allowingInlineCodePadding: true)
    }

    func testLevelOneHeadingSendsWithoutPrefix() throws {
        let channel = try openTestChannel()
        let title = "Heading one \(UUID().uuidString)"
        try channel.sendText("# \(title)")
        channel.assertMessageSent(title)
    }

    func testLevelTwoHeadingSendsWithoutPrefix() throws {
        let channel = try openTestChannel()
        let title = "Heading two \(UUID().uuidString)"
        try channel.sendText("## \(title)")
        channel.assertMessageSent(title)
    }

    func testFencedCodeBlockPreservesCodeAndLineBreaks() throws {
        let channel = try openTestChannel()
        let code = "let value = 42\n// \(UUID().uuidString)"
        try channel.sendText("```\n\(code)\n```")
        channel.assertMessageSent(code)
    }

    func testMessageWithMultipleURLsPreservesText() throws {
        let channel = try openTestChannel()
        let text = "https://example.com/one https://example.org/two \(UUID().uuidString)"
        try channel.sendText(text)
        channel.assertMessageSent(text)
    }

    func testSentMessageRemainsAfterRelaunch() throws {
        let channel = try openTestChannel()
        let text = "persist \(UUID().uuidString)"
        try channel.sendText(text)
        channel.assertMessageSent(text)
        let id = try channel.messageID(for: text)

        app.terminate()
        let reopened = try openTestChannel()
        let restored = reopened.messageContent(id: id)
        XCTAssertTrue(restored.waitForExistence(timeout: 30))
        XCTAssertEqual(restored.label, text)
        XCTAssertEqual(restored.value as? String, "sent")
    }

    func testEditMessageKeepsItsIdentity() throws {
        let channel = try openTestChannel()
        let text = try sendShortMessage(in: channel)
        let id = try channel.messageID(for: text)

        try channel.beginEdit(text, appending: " edited")
        XCTAssertTrue(channel.sendButton.waitForExistence(timeout: 5))
        channel.sendButton.tap()
        channel.assertMessageSent(text + " edited")
        XCTAssertEqual(try channel.messageID(for: text + " edited"), id)
    }

    func testCancelEditKeepsOriginalMessage() throws {
        let channel = try openTestChannel()
        let text = try sendShortMessage(in: channel)
        let id = try channel.messageID(for: text)

        try channel.beginEdit(text, appending: " discarded")
        channel.cancelEdit()
        let original = channel.messageContent(id: id)
        XCTAssertTrue(original.exists)
        XCTAssertEqual(original.label, text)
    }

    func testDeleteMessageRemovesItFromChannel() throws {
        let channel = try openTestChannel()
        let text = try sendShortMessage(in: channel)
        let id = try channel.messageID(for: text)

        try channel.deleteMessage(text, confirm: true)
        let removed = NSPredicate { _, _ in !channel.messageContent(id: id).exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: removed, object: app)], timeout: 30),
                       .completed, "Deleted message should disappear from the channel")
    }

    func testCancelDeleteKeepsOriginalMessage() throws {
        let channel = try openTestChannel()
        let text = try sendShortMessage(in: channel)
        let id = try channel.messageID(for: text)

        try channel.deleteMessage(text, confirm: false)
        let original = channel.messageContent(id: id)
        XCTAssertTrue(original.exists)
        XCTAssertEqual(original.label, text)
    }

    func testMessageKeepsMultipleReactions() throws {
        let channel = try openTestChannel()
        let text = try sendShortMessage(in: channel)
        let id = try channel.messageID(for: text)
        let emojiIDs = ["7227274405304181951", "7227274405302432668", "7227274405305046042"]

        for emojiID in emojiIDs {
            try channel.react(toText: text, emojiID: emojiID)
        }
        for emojiID in emojiIDs {
            let count = channel.message(id: id).staticTexts[AccessibilityID.Chat.reactionCount(emojiID)]
            XCTAssertTrue(count.exists && count.isSelected && (Int(count.label) ?? 0) > 0,
                          "Reaction \(emojiID) should remain selected on the same message")
        }
    }

    private func openTestChannel() throws -> ChannelScreen {
        try XCTContext.runActivity(named: "Launch app and ensure login") { _ in
            try launchAndEnsureLoggedIn()
        }
        let channel = ChannelScreen(app: app, testCase: self)
        try XCTContext.runActivity(named: "Open configured clan and channel") { _ in
            try channel.openChannel(id: UITestConfiguration.Channel.id, name: UITestConfiguration.Channel.name)
        }
        return channel
    }

    private func sendShortMessage(in channel: ChannelScreen) throws -> String {
        let text = "UI \(UUID().uuidString.prefix(12))"
        try channel.sendText(text)
        channel.assertMessageSent(text)
        return text
    }
}
