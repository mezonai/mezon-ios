import XCTest

final class ChannelMessageUITests: BaseUITestCase {
    func testSendTextMessage() throws {
        try launchAndEnsureLoggedIn()

        let channel = ChannelScreen(app: app)
        try channel.openChannel(
            id: UITestConfiguration.Channel.id,
            name: UITestConfiguration.Channel.name
        )

        let text = "automation test \(UUID().uuidString)"
        try channel.sendText(text)
        channel.assertMessageSent(text)
    }
    
    func testReplyTextMessage() throws {
        try launchAndEnsureLoggedIn()
        
        let channel = ChannelScreen(app: app)
        try channel.openChannel(
            id: UITestConfiguration.Channel.id,
            name: UITestConfiguration.Channel.name
        )
        
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
        try launchAndEnsureLoggedIn()
        
        let channel = ChannelScreen(app: app)
        try channel.openChannel(
            id: UITestConfiguration.Channel.id,
            name: UITestConfiguration.Channel.name
        )
        
        let source = "reaction source \(UUID().uuidString)"
        try channel.sendText(source)
        channel.assertMessageSent(source)

        try channel.react(toText: source, emojiID: "7227274405304181951")
    }
}
