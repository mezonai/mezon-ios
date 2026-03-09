import Foundation
import Combine
import SwiftProtobuf

@MainActor
final class ChannelsStore: ObservableObject {

    @Published private(set) var channelsByClan: [Int64: [Mezon_Api_ChannelDescription]] = [:]
    @Published var selectedChannelIdByClan: [Int64: Int64] = [:]
    @Published private(set) var currentClanId: Int64 = 0
    @Published private(set) var currentChannelId: Int64 = 0
    @Published private(set) var currentChannel: Mezon_Api_ChannelDescription?
    @Published private(set) var cachedClanAvatarByClan: [Int64: String] = [:]
    @Published private(set) var loadingClanIds: Set<Int64> = []
    @Published private(set) var errorsByClan: [Int64: String] = [:]

    init() {}

    func setChannels(_ channels: [Mezon_Api_ChannelDescription], clanId: Int64) {
        channelsByClan[clanId] = channels
        let selId = selectedChannelIdByClan[clanId]
        MezonPostbox.shared.saveChannels(channels, clanId: clanId, selectedChannelId: selId)
    }

    func restoreChannels(_ channels: [Mezon_Api_ChannelDescription], clanId: Int64, selectedChannelId selId: Int64?) {
        channelsByClan[clanId] = channels
        if let id = selId { selectedChannelIdByClan[clanId] = id }
    }

    func setLoading(_ loading: Bool, clanId: Int64) {
        if loading {
            loadingClanIds.insert(clanId)
        } else {
            loadingClanIds.remove(clanId)
        }
    }

    func setError(_ message: String?, clanId: Int64) {
        if let message {
            errorsByClan[clanId] = message
        } else {
            errorsByClan.removeValue(forKey: clanId)
        }
    }

    func setSelectedChannel(clanId: Int64, channelId: Int64) {
        selectedChannelIdByClan[clanId] = channelId
        let channels = channelsByClan[clanId] ?? []
        MezonPostbox.shared.saveChannels(channels, clanId: clanId, selectedChannelId: channelId)
    }

    func channels(for clanId: Int64) -> [Mezon_Api_ChannelDescription] {
        channelsByClan[clanId] ?? []
    }

    func setCurrentChannel(clanId: Int64, channel: Mezon_Api_ChannelDescription) {
        currentClanId = clanId
        currentChannelId = channel.channelID
        currentChannel = channel
    }

    func clearCurrentChannel() {
        currentClanId = 0
        currentChannelId = 0
        currentChannel = nil
    }

    func setCachedClanAvatar(_ avatar: String, clanId: Int64) {
        guard !avatar.isEmpty else { return }
        cachedClanAvatarByClan[clanId] = avatar
    }

    func clear() {
        channelsByClan = [:]
        selectedChannelIdByClan = [:]
        loadingClanIds = []
        errorsByClan = [:]
        clearCurrentChannel()
        cachedClanAvatarByClan = [:]
    }
}
