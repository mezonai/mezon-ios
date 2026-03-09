import Foundation
import Combine

@MainActor
final class SendMessageInputViewModel: ObservableObject {

    @Published var text: String = ""
    @Published var placeholder: String = ""

    var onVoiceTapped: (() -> Void)?
    var onSent: (() -> Void)?
    var onError: ((String) -> Void)?

    private let sharedContext: SharedAccountContext

    init(placeholder: String = "", sharedContext: SharedAccountContext) {
        self.placeholder = placeholder
        self.sharedContext = sharedContext
    }

    func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let channelsStore = sharedContext.sharedDataStore.channelsStore
        guard let channel = channelsStore.currentChannel else {
            AppLogger.app.warning("[SendMessageInput] send: no current channel")
            onError?("No channel selected")
            return
        }
        sendChannelMessage(text: trimmed, clanId: channelsStore.currentClanId, channel: channel)
    }

    func clearText() {
        text = ""
    }

    private func sendChannelMessage(text: String, clanId: Int64, channel: Mezon_Api_ChannelDescription) {
        guard let token = sharedContext.session?.token else {
            AppLogger.app.warning("[SendMessageInput] sendMessage: no session token")
            onError?("No session")
            return
        }

        let contentJSON = ["t": text]
        guard let data = try? JSONSerialization.data(withJSONObject: contentJSON),
              let contentStr = String(data: data, encoding: .utf8) else {
            onError?("Invalid content")
            return
        }

        let mode: Int32 = clanId == 0
            ? (channel.type == MezonConstants.ChannelType.dm.rawValue ? 4 : 3)
            : 2
        let isPublic = channel.parentID != 0 ? false : (channel.channelPrivate == 0)
        let channelsStore = sharedContext.sharedDataStore.channelsStore
        let avatar: String = clanId == 0
            ? (sharedContext.currentUser?.avatarURL?.absoluteString ?? "")
            : (channelsStore.cachedClanAvatarByClan[clanId] ?? sharedContext.currentUser?.avatarURL?.absoluteString ?? "")

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
                self.text = ""
                onSent?()
            } catch {
                onError?(error.localizedDescription)
                AppLogger.network.error("[SendMessageInput] sendChannelMessage: \(error)")
            }
        }
    }
}
