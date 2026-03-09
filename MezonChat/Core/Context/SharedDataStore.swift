import Combine
import Foundation
import Combine

@MainActor
final class SharedDataStore: ObservableObject {

    let authStore = AuthStore()
    let clansStore = ClansStore()
    let channelsStore = ChannelsStore()
    let messagesStore = MessagesStore()
    let notificationsStore = NotificationsStore()

    init() {}

    func clear() {
        authStore.logout()
        clansStore.clear()
        channelsStore.clear()
        messagesStore.clear()
        notificationsStore.clear()
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

            notificationsStore.loadCachedNotifications(for: clanId, categories: [0, 1, 2, 3])
        }
    }
}
