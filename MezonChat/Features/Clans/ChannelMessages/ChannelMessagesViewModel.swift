import Foundation
import Combine
import SwiftProtobuf

struct ChannelMessageDisplay: Identifiable {
    let message: Message
    let senderDisplayName: String
    let avatarURL: String?
    let isCombine: Bool
    var id: String { message.id }

    static func isCombineWithPrevious(current: Message, previous: Message?) -> Bool {
        guard let prev = previous else { return false }
        guard current.senderId == prev.senderId else { return false }
        let diff = current.createdAt.timeIntervalSince(prev.createdAt)
        return diff < 120 && diff >= 0
    }
}

private extension ChannelMessagesViewModel {
    static func applyCombine(to displays: [ChannelMessageDisplay]) -> [ChannelMessageDisplay] {
        displays.enumerated().map { i, d in
            let prev = i > 0 ? displays[i - 1].message : nil
            return ChannelMessageDisplay(
                message: d.message,
                senderDisplayName: d.senderDisplayName,
                avatarURL: d.avatarURL,
                isCombine: ChannelMessageDisplay.isCombineWithPrevious(current: d.message, previous: prev)
            )
        }
    }
}

@MainActor
final class ChannelMessagesViewModel: BaseViewModel {

    @Published private(set) var messages: [ChannelMessageDisplay] = []
    @Published private(set) var channelLabel: String = ""
    @Published private(set) var hasMoreOlder: Bool = true
    @Published private(set) var isLoadingMore: Bool = false

    private var cachedClanAvatar: String = ""
    private var storeCancellable: AnyCancellable?

    private let clanId: Int64
    private let channel: Mezon_Api_ChannelDescription
    private let sharedContext: SharedAccountContext

    init(clanId: Int64, channel: Mezon_Api_ChannelDescription, sharedContext: SharedAccountContext) {
        self.clanId = clanId
        self.channel = channel
        self.sharedContext = sharedContext
        super.init()
        self.channelLabel = channel.channelLabel.isEmpty ? "channel" : channel.channelLabel
    }

    func start() {
        subscribeToStore()
        fetchMessages()
        joinChat()
        fetchClanAvatar()
    }

    private func subscribeToStore() {
        let store = sharedContext.sharedDataStore.messagesStore
        storeCancellable = store.messagesPublisher(clanId: clanId, channelId: channel.channelID)
            .receive(on: RunLoop.main)
            .map { [weak self] apis in
                guard let self else { return [] }
                return apis.map { api in
                    ChannelMessageDisplay(
                        message: self.mapApiMessageToDomain(api),
                        senderDisplayName: self.senderDisplayName(from: api),
                        avatarURL: self.avatarURL(from: api),
                        isCombine: false
                    )
                }
            }
            .map { Self.applyCombine(to: $0) }
            .sink { [weak self] displays in
                self?.messages = displays
            }
    }

    private func fetchClanAvatar() {
        guard clanId != 0 else { return }
        guard let token = sharedContext.session?.token else { return }
        Task { @MainActor in
            do {
                let profile = try await MezonHTTPClient.shared.getUserProfileOnClan(clanId: clanId, token: token)
                if !profile.avatar.isEmpty {
                    cachedClanAvatar = profile.avatar
                }
            } catch {
                AppLogger.network.debug("[ChannelMessages] fetchClanAvatar: \(error)")
            }
        }
    }

    private func joinChat() {
        AppLogger.app.debug("[ChannelMessages] joinChat clanId=\(self.clanId) channelId=\(self.channel.channelID) channelLabel=\(self.channel.channelLabel) type=\(self.channel.type) parentID=\(self.channel.parentID) channelPrivate=\(self.channel.channelPrivate)")

        MezonSocket.shared.joinClanChat(clanId: clanId)

        let channelType: Int32 = clanId == 0
            ? (channel.type != 0 ? channel.type : 3)
            : (channel.type != 0 ? channel.type : 1)
        let isPublic = clanId == 0 ? false : (channel.parentID != 0 ? false : (channel.channelPrivate == 0))

        MezonSocket.shared.joinChannel(
            clanId: clanId,
            channelId: channel.channelID,
            channelType: channelType,
            isPublic: isPublic
        )
    }

    func fetchMessages() {
        guard let token = sharedContext.session?.token else {
            AppLogger.app.warning("[ChannelMessages] fetchMessages: no session token")
            return
        }

        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            defer { isLoading = false }
            do {
                var response = try await MezonHTTPClient.shared.listChannelMessages(
                    clanId: clanId,
                    channelId: channel.channelID,
                    messageId: 0,
                    direction: 2,
                    limit: 50,
                    topicId: 0,
                    token: token
                )
                if response.messages.isEmpty {
                    response = try await MezonHTTPClient.shared.listChannelMessages(
                        clanId: clanId,
                        channelId: channel.channelID,
                        messageId: 0,
                        direction: 3,
                        limit: 50,
                        topicId: 0,
                        token: token
                    )
                }
                AppLogger.app.debug("[ChannelMessages] fetched \(response.messages.count) messages")
                hasMoreOlder = response.messages.count >= 50
                sharedContext.sharedDataStore.messagesStore.setMessages(response.messages, clanId: clanId, channelId: channel.channelID)
                sharedContext.sharedDataStore.messagesStore.setHasMoreOlder(response.messages.count >= 50, clanId: clanId, channelId: channel.channelID)
            } catch {
                errorMessage = error.localizedDescription
                AppLogger.network.error("[ChannelMessages] fetchMessages: \(error)")
            }
        }
    }

    func fetchMoreMessages() {
        guard hasMoreOlder, !isLoadingMore else { return }
        guard let token = sharedContext.session?.token else { return }
        guard let oldestId = messages.first?.message.id, let msgId = Int64(oldestId) else { return }

        isLoadingMore = true
        Task { @MainActor in
            defer { isLoadingMore = false }
            do {
                let response = try await MezonHTTPClient.shared.listChannelMessages(
                    clanId: clanId,
                    channelId: channel.channelID,
                    messageId: msgId,
                    direction: 3,
                    limit: 50,
                    topicId: 0,
                    token: token
                )
                hasMoreOlder = response.messages.count >= 50
                sharedContext.sharedDataStore.messagesStore.appendMessages(response.messages, clanId: clanId, channelId: channel.channelID)
                sharedContext.sharedDataStore.messagesStore.setHasMoreOlder(response.messages.count >= 50, clanId: clanId, channelId: channel.channelID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func sendMessage(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let token = sharedContext.session?.token else {
            AppLogger.app.warning("[ChannelMessages] sendMessage: no session token")
            return
        }
        let contentJSON = ["t": trimmed]
        guard let data = try? JSONSerialization.data(withJSONObject: contentJSON),
              let contentStr = String(data: data, encoding: .utf8) else { return }
        let mode: Int32 = clanId == 0
            ? (channel.type == 2 ? 4 : 3)
            : 2
       
        let isPublic = channel.parentID != 0 ? false : (channel.channelPrivate == 0)
        let avatar: String = clanId == 0
            ? (sharedContext.currentUser?.avatarURL?.absoluteString ?? "")
            : (!cachedClanAvatar.isEmpty ? cachedClanAvatar : (sharedContext.currentUser?.avatarURL?.absoluteString ?? ""))

        AppLogger.app.debug("[ChannelMessages] sendMessage → sendChannelMessage clanId=\(self.clanId) channelId=\(self.channel.channelID) mode=\(mode) isPublic=\(isPublic) content=\(contentStr) avatar=\(avatar) topicId=0")

        Task { @MainActor in
            do {
                _ = try await MezonHTTPClient.shared.sendChannelMessage(
                    clanId: clanId,
                    channelId: channel.channelID,
                    mode: mode,
                    isPublic: isPublic,
                    content: contentStr,
                    mentions: [],
                    attachments: [],
                    references: [],
                    anonymous: false,
                    mentionEveryone: false,
                    avatar: avatar,
                    topicId: 0,
                    token: token
                )
            } catch {
                errorMessage = error.localizedDescription
                AppLogger.network.error("[ChannelMessages] sendMessage: \(error)")
            }
        }
    }

    private func mapApiMessageToDomain(_ api: Mezon_Api_ChannelMessage) -> Message {
        let createdAt = Date(timeIntervalSince1970: TimeInterval(api.createTimeSeconds))
        let textContent = extractTextFromContent(api.content)
        return Message(
            id: "\(api.messageID)",
            channelId: "\(api.channelID)",
            clanId: "\(api.clanID)",
            senderId: "\(api.senderID)",
            content: .text(textContent),
            createdAt: createdAt,
            editedAt: nil,
            isDeleted: false,
            reactions: [],
            replyToId: nil,
            mentionedUserIds: [],
            isPinned: false
        )
    }

    private func senderDisplayName(from api: Mezon_Api_ChannelMessage) -> String {
        if !api.clanNick.isEmpty { return api.clanNick }
        if !api.displayName.isEmpty { return api.displayName }
        if !api.username.isEmpty { return api.username }
        return "\(api.senderID)"
    }

    private func avatarURL(from api: Mezon_Api_ChannelMessage) -> String? {
        if !api.clanAvatar.isEmpty { return api.clanAvatar }
        if !api.avatar.isEmpty { return api.avatar }
        return nil
    }

    private func extractTextFromContent(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return content }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return content
        }
        if let t = json["t"] as? String { return t }
        if let text = json["text"] as? String { return text }
        return content
    }
}
