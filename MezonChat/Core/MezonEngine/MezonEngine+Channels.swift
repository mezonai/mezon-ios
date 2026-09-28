import Foundation
import SwiftProtobuf

extension MezonEngine {

    @MainActor
    final class Channels {
        private let engine: MezonEngine
        private var network: MezonHTTPClient { engine.account.network }
        private var postbox: Postbox { engine.account.postbox }
        private var voiceAccess = VoiceChannelAccessState()
        private var accessRefreshTasks: [Int64: Task<Void, Never>] = [:]
        private(set) var activeVoiceChannel: Mezon_Api_ChannelDescription?
        private var activeVoiceTrackingId: UUID?

        var accessSnapshot: VoiceChannelAccessState { voiceAccess }
        func accessRevision(clanId: Int64) -> UInt64 { voiceAccess.revision(clanId: clanId) }
        func isAccessRevoked(channelId: Int64) -> Bool { voiceAccess.revokedChannelIds.contains(channelId) }

        func mergingVoiceAccess(_ channels: [Mezon_Api_ChannelDescription], since snapshot: VoiceChannelAccessState) -> [Mezon_Api_ChannelDescription] {
            voiceAccess.mergingVoiceChannels(
                incoming: channels, cached: engine.clanData.getAllChannelsByUser()?.channeldesc ?? [], since: snapshot,
                id: { $0.channelID }, clanId: { $0.clanID },
                isVoice: { $0.type == MezonConstants.ChannelType.mezonVoice.rawValue })
        }

        func trackVoiceChannel(_ channel: Mezon_Api_ChannelDescription) -> UUID {
            let id = UUID()
            activeVoiceChannel = channel
            activeVoiceTrackingId = id
            return id
        }
        func stopTrackingVoiceChannel(channelId: Int64, trackingId: UUID? = nil) {
            guard activeVoiceChannel?.channelID == channelId,
                  trackingId == nil || trackingId == activeVoiceTrackingId else { return }
            activeVoiceChannel = nil
            activeVoiceTrackingId = nil
        }

        func resetForLogout() {
            accessRefreshTasks.values.forEach { $0.cancel() }
            accessRefreshTasks.removeAll()
            voiceAccess = VoiceChannelAccessState()
            activeVoiceChannel = nil
            activeVoiceTrackingId = nil
        }

        func grantVoiceChannelAccess(_ channel: Mezon_Api_ChannelDescription) {
            guard channel.type == MezonConstants.ChannelType.mezonVoice.rawValue else { return }
            voiceAccess.grant(clanId: channel.clanID, channelId: channel.channelID)
        }

      
        func removeVoiceChannelAccess(clanId: Int64, channelId: Int64) {
            guard clanId != 0, channelId != 0 else { return }
            voiceAccess.revoke(clanId: clanId, channelId: channelId)
            postbox.writeSync { tx in
                tx.updateChannels(tx.getChannels(clanId: clanId).filter { $0.id != channelId }, clanId: clanId)
            }
            if let data = postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)) {
                let channels = ChannelPreferenceListCodec.decode(data).filter { $0.channelID != channelId }
                postbox.setPreferenceDataSync(key: PreferencesKeys.channelList(clanId: clanId), value: ChannelPreferenceListCodec.encode(channels))
            }
          
            postbox.setPreferenceDataSync(key: PreferencesKeys.channelListCategories(clanId: clanId), value: nil)
            postbox.setPreferenceDataSync(key: PreferencesKeys.channelListDisplay(clanId: clanId), value: nil)
            if let data = postbox.getPreferenceData(key: PreferencesKeys.favoriteChannelIds(clanId: clanId)),
               var favorites = try? Mezon_Api_ListFavoriteChannelResponse(serializedBytes: data) {
                favorites.channelIds.removeAll { $0 == channelId }
                postbox.setPreferenceDataSync(key: PreferencesKeys.favoriteChannelIds(clanId: clanId), value: try? favorites.serializedData())
            }
            if var list = engine.clanData.getAllChannelsByUser() {
                list.channeldesc.removeAll { $0.channelID == channelId }
                postbox.setPreferenceDataSync(key: PreferencesKeys.allChannelsByUser, value: try? list.serializedData())
            }
            NotificationCenter.default.post(name: .mezonVoiceChannelAccessLost, object: nil,
                userInfo: ["clanId": clanId, "channelId": channelId])
        }

       
        @discardableResult
        func reconcileVoiceChannelAccess(_ channels: [Mezon_Api_ChannelDescription], clanId: Int64, revision: UInt64) -> Bool {
            guard voiceAccess.accept(channelIds: channels.map(\.channelID), clanId: clanId, revision: revision) else { return false }
            guard !channels.isEmpty else { return true }
            let ids = Set(channels.map(\.channelID))
            var previous = engine.clanData.getAllChannelsByUser()?.channeldesc.filter { $0.clanID == clanId } ?? []
            if let data = postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)) {
                previous += ChannelPreferenceListCodec.decode(data)
            }
            if let active = activeVoiceChannel, active.clanID == clanId { previous.append(active) }
            let removed = Set(previous.filter {
                $0.type == MezonConstants.ChannelType.mezonVoice.rawValue && !ids.contains($0.channelID)
            }.map(\.channelID))
            for id in removed { removeVoiceChannelAccess(clanId: clanId, channelId: id) }
            return true
        }

        func refreshVoiceChannelAccess(clanId: Int64, context: AccountContext) {
            guard clanId != 0 else { return }
            voiceAccess.invalidate(clanId: clanId)
            guard accessRefreshTasks[clanId] == nil else { return }
            let epoch = context.sessionEpoch
            accessRefreshTasks[clanId] = Task { @MainActor [weak self, weak context] in
                guard let self, let context else { return }
                defer { if context.isStillCurrentSession(epoch: epoch) { self.accessRefreshTasks[clanId] = nil } }
             
                while !Task.isCancelled && context.isStillCurrentSession(epoch: epoch) {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled, let token = await context.getToken() else { return }
                    let revision = self.accessRevision(clanId: clanId)
                    do {
                        let channels = try await self.network.listChannelDescs(clanId: clanId, token: token, force: true, accessRevision: revision)
                        guard !Task.isCancelled, context.isStillCurrentSession(epoch: epoch) else { return }
                        guard self.reconcileVoiceChannelAccess(channels, clanId: clanId, revision: revision) else { continue }
                        for channel in channels where channel.type == MezonConstants.ChannelType.mezonVoice.rawValue {
                            if self.postbox.resolvedChannelDescription(clanId: clanId, channelId: channel.channelID) == channel { continue }
                            self.engine.clanData.applyLocallyCreatedChannel(channel, skipChannelListFetch: true)
                        }
                        return
                    } catch {
                        if revision == self.accessRevision(clanId: clanId) { return }
                    }
                }
            }
        }

        func handleVoiceChannelUpdated(_ event: Mezon_Realtime_ChannelUpdatedEvent, context: AccountContext) -> Bool {
            let previous = postbox.resolvedChannelDescription(clanId: event.clanID, channelId: event.channelID)
            guard event.channelType == MezonConstants.ChannelType.mezonVoice.rawValue ||
                    previous?.type == MezonConstants.ChannelType.mezonVoice.rawValue else { return false }
            guard event.clanID != 0, event.channelID != 0, !event.isError else { return true }
            let privacyChanged = previous?.channelPrivate != (event.channelPrivate ? 1 : 0)
            let needsAuthoritativeDescription = previous == nil || privacyChanged ||
                (event.topic.isEmpty && previous?.topic.isEmpty == false) || event.categoryID != previous?.categoryID
            if needsAuthoritativeDescription {
                refreshVoiceChannelAccess(clanId: event.clanID, context: context)
            } else {
                voiceAccess.invalidate(clanId: event.clanID)
            }
            if event.channelPrivate && previous?.channelPrivate != 1 {
                let userId = Int64(context.currentUser?.id ?? "") ?? 0
                let roleIds = postbox.read { $0.getClanMembers(clanId: event.clanID).first { $0.userId == userId }?.roleIds }
                let access = PrivateVoiceChannelAccess.afterPrivacyUpdate(
                    userId: userId, creatorId: event.creatorID, memberIds: event.userIds, roleIds: event.roleIds,
                    selfRoleIds: roleIds,
                    isOwnerOrAdmin: context.rolePermissions.hasClanPermission(.administrator, clanId: event.clanID),
                    permissionsLoaded: engine.clanData.getUserPermissions(clanId: event.clanID) != nil && engine.clanData.getAllPermissions() != nil)
                if access == false {
                    removeVoiceChannelAccess(clanId: event.clanID, channelId: event.channelID)
                    return true
                }
                if access == nil { return true }
            }
            var channel = previous ?? Mezon_Api_ChannelDescription()
            channel.clanID = event.clanID
            channel.channelID = event.channelID
            channel.type = MezonConstants.ChannelType.mezonVoice.rawValue
            channel.channelPrivate = event.channelPrivate ? 1 : 0
            if event.creatorID != 0 { channel.creatorID = event.creatorID }
            if !event.channelLabel.isEmpty { channel.channelLabel = event.channelLabel }
            if !event.topic.isEmpty { channel.topic = event.topic }
            if event.categoryID != 0 { channel.categoryID = event.categoryID }
            channel.active = event.active == 0 ? 1 : event.active
            if !event.channelPrivate {
                engine.clanData.clearChannelRoleGrants(clanId: event.clanID, channelId: event.channelID)
            }
            guard !isAccessRevoked(channelId: channel.channelID) || !event.channelPrivate else { return true }
            if !event.channelPrivate, isAccessRevoked(channelId: channel.channelID) { grantVoiceChannelAccess(channel) }
            engine.clanData.applyLocallyCreatedChannel(channel, skipChannelListFetch: true)
            return true
        }

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

            let prevCh = self.postbox.resolvedChannelDescription(clanId: clanId, channelId: channelId)
            let prevCatName = prevCh?.categoryName ?? ""
            var fallbackCategoryName = prevCatName
            if prevCh?.type == MezonConstants.ChannelType.mezonVoice.rawValue,
               let categoryData = postbox.getPreferenceData(key: PreferencesKeys.channelListMeta(clanId: clanId)),
               let categoryName = ChannelListMetaCodec.decode(categoryData)?.categoryDescs.first(where: { $0.categoryID == categoryId })?.categoryName {
                fallbackCategoryName = categoryName
            }
            let newCatName = categoryId == 0 ? "" : (result.categoryName.isEmpty ? fallbackCategoryName : result.categoryName)


            self.postbox.write { tx in
                tx.updateChannelDescription(
                    clanId: clanId,
                    channelId: channelId,
                    name: name,
                    topic: topic,
                    channelAvatar: channelAvatar,
                    categoryId: categoryId,
                    categoryName: newCatName
                )
            }
            
            if let blob = self.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)), !blob.isEmpty {
                var arr = ChannelPreferenceListCodec.decode(blob)
                if let idx = arr.firstIndex(where: { $0.channelID == channelId }) {
                    if let name { arr[idx].channelLabel = name }
                    if let topic { arr[idx].topic = topic }
                    if let categoryId {
                        arr[idx].categoryID = categoryId
                        arr[idx].categoryName = newCatName
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
                        list.channeldesc[idx].categoryName = newCatName
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
