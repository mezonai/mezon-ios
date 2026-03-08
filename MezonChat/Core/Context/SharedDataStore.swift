import Foundation
import Combine

@MainActor
final class SharedDataStore: ObservableObject {

    let authStore = AuthStore()
    let clansStore = ClansStore()
    let channelsStore = ChannelsStore()
    let messagesStore = MessagesStore()

    init() {}

    func clear() {
        authStore.logout()
        clansStore.clear()
        channelsStore.clear()
        messagesStore.clear()
        MezonPostbox.shared.clear()
    }

    func hydrateFromPostbox() {
        if let account = MezonPostbox.shared.loadAccount() {
            authStore.restoreAccount(account)
        }
        let (clans, selClanId) = MezonPostbox.shared.loadClans()
        if !clans.isEmpty {
            clansStore.restoreClans(clans, selectedClanId: selClanId)
        }
        for clanId in MezonPostbox.shared.loadChannelClanIds() {
            let (channels, selChannelId) = MezonPostbox.shared.loadChannels(clanId: clanId)
            if !channels.isEmpty {
                channelsStore.restoreChannels(channels, clanId: clanId, selectedChannelId: selChannelId)
            }
        }
    }
}
