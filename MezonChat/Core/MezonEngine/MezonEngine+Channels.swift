import Foundation
import SwiftProtobuf

extension MezonEngine {

    @MainActor
    final class Channels {
        private let engine: MezonEngine
        private var network: MezonHTTPClient { engine.account.network }
        private var postbox: Postbox { engine.account.postbox }

        init(engine: MezonEngine) { self.engine = engine }

        func listChannelDescs(clanId: Int64, token: String) async throws -> [Mezon_Api_ChannelDescription] {
            try await network.listChannelDescs(clanId: clanId, token: token)
        }

        func listDirectMessageChannels(token: String) async throws -> [Mezon_Api_ChannelDescription] {
            try await network.listDirectMessageChannels(token: token)
        }

        func channelListView(clanId: Int64) -> Signal<ChannelListView, NoError> {
            postbox.channelListView(clanId: clanId)
        }

        func updateChannelDescription(
            clanId: Int64,
            channelId: Int64,
            name: String?,
            topic: String?,
            categoryId: Int64?,
            channelAvatar: String? = nil,
            token: String
        ) async throws {
            let result = try await network.updateChannelDesc(
                clanId: clanId,
                channelId: channelId,
                channelLabel: name,
                channelAvatar: channelAvatar,
                topic: topic,
                categoryId: categoryId,
                token: token
            )

            self.postbox.write { tx in
                tx.updateChannelDescription(
                    clanId: clanId,
                    channelId: channelId,
                    name: name,
                    topic: topic,
                    channelAvatar: channelAvatar,
                    categoryId: categoryId,
                    categoryName: result.categoryName
                )
            }
            
            if let blob = self.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)), !blob.isEmpty {
                var arr = ChannelPreferenceListCodec.decode(blob)
                if let idx = arr.firstIndex(where: { $0.channelID == channelId }) {
                    if let name { arr[idx].channelLabel = name }
                    if let topic { arr[idx].topic = topic }
                    if let categoryId {
                        arr[idx].categoryID = categoryId
                        arr[idx].categoryName = result.categoryName
                    }
                    if let data = ChannelPreferenceListCodec.encode(arr) {
                        self.postbox.setPreferenceDataSync(
                            key: PreferencesKeys.channelList(clanId: clanId), value: data)
                    }
                }
            }
            
            if let blob = self.postbox.getPreferenceData(key: PreferencesKeys.allChannelsByUser), !blob.isEmpty,
               var list = try? Mezon_Api_ChannelDescList(serializedBytes: blob) {
                if let idx = list.channeldesc.firstIndex(where: { $0.channelID == channelId }) {
                    if let name { list.channeldesc[idx].channelLabel = name }
                    if let topic { list.channeldesc[idx].topic = topic }
                    if let categoryId {
                        list.channeldesc[idx].categoryID = categoryId
                        list.channeldesc[idx].categoryName = result.categoryName
                    }
                    if let data = try? list.serializedData() {
                        self.postbox.setPreferenceDataSync(
                            key: PreferencesKeys.allChannelsByUser, value: data)
                    }
                }
            }

            NotificationCenter.default.post(
                name: .mezonChannelDescriptionDidUpdate,
                object: nil,
                userInfo: ["clanId": clanId, "channelId": channelId]
            )
        }
    }
}
