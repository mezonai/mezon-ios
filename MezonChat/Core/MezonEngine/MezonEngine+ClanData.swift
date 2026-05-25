import Foundation
import SwiftProtobuf

enum ChannelPreferenceListCodec {
    static func decode(_ data: Data) -> [Mezon_Api_ChannelDescription] {
        guard data.count >= 4 else { return [] }
        let count = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        var result: [Mezon_Api_ChannelDescription] = []
        var offset = 4
        for _ in 0..<count {
            guard offset + 4 <= data.count else { break }
            let len = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4
            guard offset + Int(len) <= data.count else { break }
            if let m = try? Mezon_Api_ChannelDescription(serializedBytes: data.subdata(in: offset..<(offset + Int(len)))) {
                result.append(m)
            }
            offset += Int(len)
        }
        return result
    }

    static func encode(_ channels: [Mezon_Api_ChannelDescription]) -> Data? {
        var result = Data()
        var count = UInt32(channels.count)
        result.append(contentsOf: withUnsafeBytes(of: &count) { Array($0) })
        for ch in channels {
            guard let d = try? ch.serializedData() else { continue }
            var len = UInt32(d.count)
            result.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
            result.append(d)
        }
        return result
    }
}

enum EStateFriend: Int32 {
    case friend = 0
    case otherPending = 1
    case myPending = 2
    case block = 3
}

extension MezonEngine {

    @MainActor
    final class ClanData {
        private let engine: MezonEngine
        private var network: MezonHTTPClient { engine.account.network }
        private var postbox: Postbox { engine.account.postbox }

        let clanUsersUpdated = ValuePipe<Int64>()
        let clanRolesUpdated = ValuePipe<Int64>()
        let clanEventsUpdated = ValuePipe<Int64>()
        let clanPermissionsUpdated = ValuePipe<Int64>()
        let clanVoiceUsersUpdated = ValuePipe<Int64>()
        let clanStreamUsersUpdated = ValuePipe<Int64>()
        let clanBadgeCountUpdated = ValuePipe<(clanId: Int64, count: Int32)>()
        let clanNotificationUpdated = ValuePipe<Int64>()

        private var inflightFetchAllByClanId: [Int64: Task<Void, Never>] = [:]
        private var lastFetchAllAtByClanId: [Int64: Date] = [:]
        private let fetchAllCooldownInterval: TimeInterval = 2.0

        init(engine: MezonEngine) { self.engine = engine }

        func resetForLogout() {
            for (_, task) in inflightFetchAllByClanId {
                task.cancel()
            }
            inflightFetchAllByClanId.removeAll()
            lastFetchAllAtByClanId.removeAll()
        }

        func fetchAllClanData(clanId: Int64, token: String) {
            guard clanId != 0 else { return }
            if let existing = inflightFetchAllByClanId[clanId], !existing.isCancelled { return }
            if let last = lastFetchAllAtByClanId[clanId], Date().timeIntervalSince(last) < fetchAllCooldownInterval {
                return
            }
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    self.inflightFetchAllByClanId[clanId] = nil
                    self.lastFetchAllAtByClanId[clanId] = Date()
                }

                async let usersResult = self.fetchClanUsers(clanId: clanId, token: token)
                async let rolesResult = self.fetchRoles(clanId: clanId, token: token)
                async let eventsResult = self.fetchEvents(clanId: clanId, token: token)
                async let userPermsResult = self.fetchUserPermissions(clanId: clanId, token: token)
                async let allPermsResult = self.fetchAllPermissions(token: token)
                async let voiceResult = self.fetchVoiceChannelUsers(clanId: clanId, token: token)
                async let streamResult = self.fetchStreamChannelUsers(clanId: clanId, token: token)
                async let badgeResult = self.fetchBadgeCount(clanId: clanId, token: token)
                async let notifResult = self.fetchDefaultNotification(clanId: clanId, token: token)
                async let catNotifResult = self.fetchCategoryNotification(clanId: clanId, token: token)
                _ = await (
                    usersResult, rolesResult, eventsResult, userPermsResult, allPermsResult,
                    voiceResult, streamResult, badgeResult, notifResult, catNotifResult
                )
            }
            inflightFetchAllByClanId[clanId] = task
        }

        private func fetchClanUsers(clanId: Int64, token: String) async {
            do {
                let response = try await network.listClanUsers(clanId: clanId, token: token)

                if response.clanUsers.isEmpty {
                    let cachedNonEmpty = !postbox.read({ tx in tx.getClanMembers(clanId: clanId) }).isEmpty
                        || (postbox.getPreferenceData(key: PreferencesKeys.clanUsers(clanId: clanId))?.isEmpty == false)
                    if cachedNonEmpty {
                        return
                    }
                }

                let existingPref = postbox.getPreferenceData(key: PreferencesKeys.clanUsers(clanId: clanId))
                let existingMembers = postbox.read { tx in tx.getClanMembers(clanId: clanId) }
                let hasExistingCache = (existingPref?.isEmpty == false) || !existingMembers.isEmpty
                if !response.cursor.isEmpty && hasExistingCache {
                    return
                }

                let members = response.clanUsers.map { ClanMemberRecord(from: $0) }

                postbox.write { tx in
                    for clanUser in response.clanUsers {
                        tx.updateProfile(ProfileRecord(from: clanUser))
                    }

                    tx.updateClanMembers(members, clanId: clanId)
                }
                if let data = try? response.serializedData() {
                    postbox.setPreferenceDataSync(key: PreferencesKeys.clanUsers(clanId: clanId), value: data)
                }

                clanUsersUpdated.putNext(clanId)
            } catch {
            }
        }

        private func fetchRoles(clanId: Int64, token: String) async {
            do {
                let response = try await network.listRoles(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.clanRoles(clanId: clanId), value: data)
                }
                clanRolesUpdated.putNext(clanId)
            } catch {
            }
        }

        private func fetchEvents(clanId: Int64, token: String) async {
            do {
                let response = try await network.listEvents(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.clanEvents(clanId: clanId), value: data)
                }
                clanEventsUpdated.putNext(clanId)
            } catch {
            }
        }

        private func fetchUserPermissions(clanId: Int64, token: String) async {
            do {
                let response = try await network.getRoleOfUserInTheClan(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.clanUserPermissions(clanId: clanId), value: data)
                }
                clanPermissionsUpdated.putNext(clanId)
            } catch {
            }
        }

        private func fetchAllPermissions(token: String) async {
            do {
                let response = try await network.getListPermission(token: token)
                if let data = try? response.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.allPermissions, value: data)
                }
            } catch {
            }
        }

        private func fetchVoiceChannelUsers(clanId: Int64, token: String) async {
            do {
                let response = try await network.listChannelVoiceUsers(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.clanVoiceUsers(clanId: clanId), value: data)
                }
                clanVoiceUsersUpdated.putNext(clanId)
            } catch {
            }
        }

        private func fetchStreamChannelUsers(clanId: Int64, token: String) async {
            do {
                let response = try await network.listStreamingChannelUsers(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.clanStreamUsers(clanId: clanId), value: data)
                }
                clanStreamUsersUpdated.putNext(clanId)
            } catch {
            }
        }


        private func fetchBadgeCount(clanId: Int64, token: String) async {


        }

        private func fetchDefaultNotification(clanId: Int64, token: String) async {
            do {
                let response = try await network.getNotificationClan(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.clanDefaultNotification(clanId: clanId), value: data)
                }
                clanNotificationUpdated.putNext(clanId)
            } catch {
            }
        }

        private func fetchCategoryNotification(clanId: Int64, token: String) async {
            do {
                let response = try await network.getChannelCategoryNotiSettingsList(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.clanCategoryNotification(clanId: clanId), value: data)
                }
            } catch {
            }
        }

        func getClanUsers(clanId: Int64) -> Mezon_Api_ClanUserList? {
            if let data = postbox.getPreferenceData(key: PreferencesKeys.clanUsers(clanId: clanId)),
               let cached = try? Mezon_Api_ClanUserList(serializedBytes: data),
               !cached.clanUsers.isEmpty {
                let tag = cached.clanID
                if tag == 0 || tag == clanId {
                    return cached
                }
            }
            let rows = postbox.read { $0.getClanMembers(clanId: clanId) }
            guard !rows.isEmpty else { return nil }
            var list = Mezon_Api_ClanUserList()
            list.clanID = clanId
            list.clanUsers = rows.map { $0.toClanUserListClanUser() }
            return list
        }

        func getClanRoles(clanId: Int64) -> Mezon_Api_RoleListEventResponse? {
            guard let data = postbox.getPreferenceData(key: PreferencesKeys.clanRoles(clanId: clanId)) else { return nil }
            return try? Mezon_Api_RoleListEventResponse(serializedBytes: data)
        }

        func getClanEvents(clanId: Int64) -> Mezon_Api_EventList? {
            guard let data = postbox.getPreferenceData(key: PreferencesKeys.clanEvents(clanId: clanId)) else { return nil }
            return try? Mezon_Api_EventList(serializedBytes: data)
        }

        func getUserPermissions(clanId: Int64) -> Mezon_Api_RoleList? {
            guard let data = postbox.getPreferenceData(key: PreferencesKeys.clanUserPermissions(clanId: clanId)) else { return nil }
            return try? Mezon_Api_RoleList(serializedBytes: data)
        }

        func getAllPermissions() -> Mezon_Api_PermissionList? {
            guard let data = postbox.getPreferenceData(key: PreferencesKeys.allPermissions) else { return nil }
            return try? Mezon_Api_PermissionList(serializedBytes: data)
        }

        func getVoiceUsers(clanId: Int64) -> Mezon_Api_VoiceChannelUserList? {
            guard let data = postbox.getPreferenceData(key: PreferencesKeys.clanVoiceUsers(clanId: clanId)) else { return nil }
            return try? Mezon_Api_VoiceChannelUserList(serializedBytes: data)
        }

        func getStreamUsers(clanId: Int64) -> Mezon_Api_VoiceChannelUserList? {
            guard let data = postbox.getPreferenceData(key: PreferencesKeys.clanStreamUsers(clanId: clanId)) else { return nil }
            return try? Mezon_Api_VoiceChannelUserList(serializedBytes: data)
        }

        func refetchVoiceChannelUsers(clanId: Int64, token: String) async {
            await fetchVoiceChannelUsers(clanId: clanId, token: token)
        }

        func applyVoiceJoined(clanId: Int64, channelId: Int64, userId: Int64) {
            var list = getVoiceUsers(clanId: clanId) ?? Mezon_Api_VoiceChannelUserList()
            let uid = "\(userId)"
            applyVoiceLeaved(clanId: clanId, channelId: channelId, userId: userId, list: &list, notify: false)
            if let idx = list.voiceChannelUsers.firstIndex(where: { $0.channelID == channelId }) {
                var entry = list.voiceChannelUsers[idx]
                if !entry.userIds.contains(uid) {
                    entry.userIds.append(uid)
                    list.voiceChannelUsers[idx] = entry
                }
            } else {
                var vu = Mezon_Api_VoiceChannelUser()
                vu.channelID = channelId
                vu.userIds = [uid]
                list.voiceChannelUsers.append(vu)
            }
            persistVoiceUsersList(list, clanId: clanId)
        }

        func applyVoiceLeaved(clanId: Int64, channelId: Int64, userId: Int64) {
            var list = getVoiceUsers(clanId: clanId) ?? Mezon_Api_VoiceChannelUserList()
            applyVoiceLeaved(clanId: clanId, channelId: channelId, userId: userId, list: &list, notify: true)
        }

        private func applyVoiceLeaved(clanId: Int64, channelId: Int64, userId: Int64, list: inout Mezon_Api_VoiceChannelUserList, notify: Bool) {
            let uid = "\(userId)"
            guard let idx = list.voiceChannelUsers.firstIndex(where: { $0.channelID == channelId }) else {
                if notify { persistVoiceUsersList(list, clanId: clanId) }
                return
            }
            var entry = list.voiceChannelUsers[idx]
            entry.userIds.removeAll { $0 == uid }
            if entry.userIds.isEmpty {
                list.voiceChannelUsers.remove(at: idx)
            } else {
                list.voiceChannelUsers[idx] = entry
            }
            if notify {
                persistVoiceUsersList(list, clanId: clanId)
            }
        }

        func applyVoiceEnded(clanId: Int64, channelId: Int64) {
            var list = getVoiceUsers(clanId: clanId) ?? Mezon_Api_VoiceChannelUserList()
            list.voiceChannelUsers.removeAll { $0.channelID == channelId }
            persistVoiceUsersList(list, clanId: clanId)
        }

        private func persistVoiceUsersList(_ list: Mezon_Api_VoiceChannelUserList, clanId: Int64) {
            if let data = try? list.serializedData() {
                postbox.setPreferenceData(key: PreferencesKeys.clanVoiceUsers(clanId: clanId), value: data)
            }
            clanVoiceUsersUpdated.putNext(clanId)
            NotificationCenter.default.post(
                name: .mezonVoicePresenceChanged,
                object: nil,
                userInfo: ["clanId": NSNumber(value: clanId)]
            )
        }

        func getBadgeCount(clanId: Int64) -> Int32 {
            guard let data = postbox.getPreferenceData(key: PreferencesKeys.clanBadgeCount(clanId: clanId)),
                  data.count >= 4 else { return 0 }
            return data.withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        }

        func getAllUserClans() -> Mezon_Api_AllUserClans? {
            guard let data = postbox.getPreferenceData(key: PreferencesKeys.allUserClans) else { return nil }
            return try? Mezon_Api_AllUserClans(serializedBytes: data)
        }

        func getAllChannelsByUser() -> Mezon_Api_ChannelDescList? {
            guard let data = postbox.getPreferenceData(key: PreferencesKeys.allChannelsByUser) else { return nil }
            return try? Mezon_Api_ChannelDescList(serializedBytes: data)
        }

        func resolvedListChannelUsersType(channelId: Int64) -> Int32 {
            if let meta = postbox.read({ tx in tx.getChannelMeta(channelId: channelId) }),
               meta.type != 0 {
                return meta.type
            }
            if let list = getAllChannelsByUser()?.channeldesc,
               let d = list.first(where: { $0.channelID == channelId }),
               d.type != 0 {
                return d.type
            }
            return MezonConstants.ChannelType.channel.rawValue
        }

        @discardableResult
        func applyUserChannelAddedFromSocket(_ event: Mezon_Realtime_UserChannelAdded, currentUserNumericId myId: Int64) -> Mezon_Api_ChannelDescription? {
            guard event.hasChannelDesc else { return nil }
            guard event.users.contains(where: { $0.userID == myId }) else { return nil }

            var ch = event.channelDesc
            if event.clanID != 0 && ch.clanID == 0 {
                ch.clanID = event.clanID
            }
            if event.active != 0 {
                ch.active = event.active
            } else {
                ch.active = 1
            }

            applyLocallyCreatedChannel(ch)
            return ch
        }
        
        func applyLocallyCreatedChannel(_ ch: Mezon_Api_ChannelDescription) {
            upsertAllChannelsByUserCache(ch)
            if ch.clanID != 0 {
                mergeIntoClanChannelListPreferenceIfPresent(clanId: ch.clanID, channel: ch)
            }

            NotificationCenter.default.post(
                name: .mezonUserChannelAddedFromSocket,
                object: nil,
                userInfo: ["clanId": ch.clanID, "channelId": ch.channelID]
            )
        }

        private func upsertAllChannelsByUserCache(_ ch: Mezon_Api_ChannelDescription) {
            var list = getAllChannelsByUser() ?? Mezon_Api_ChannelDescList()
            if let idx = list.channeldesc.firstIndex(where: { $0.channelID == ch.channelID }) {
                list.channeldesc[idx] = ch
            } else {
                list.channeldesc.append(ch)
            }
            guard let data = try? list.serializedData() else { return }
            postbox.setPreferenceData(key: PreferencesKeys.allChannelsByUser, value: data)
        }

        func updateChannelPrivateLocally(clanId: Int64, channelId: Int64, isPrivate: Bool) {
            let priv: Int32 = isPrivate ? 1 : 0
            postbox.write { tx in
                tx.updateChannelPrivate(
                    clanId: clanId, channelId: channelId, isPrivate: isPrivate)
            }
            if let blob = postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)), !blob.isEmpty {
                var arr = ChannelPreferenceListCodec.decode(blob)
                if let idx = arr.firstIndex(where: { $0.channelID == channelId }) {
                    arr[idx].channelPrivate = priv
                    if let data = ChannelPreferenceListCodec.encode(arr) {
                        postbox.setPreferenceDataSync(
                            key: PreferencesKeys.channelList(clanId: clanId), value: data)
                    }
                }
            }
            if var list = getAllChannelsByUser(),
                let idx = list.channeldesc.firstIndex(where: { $0.channelID == channelId }) {
                list.channeldesc[idx].channelPrivate = priv
                if let data = try? list.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.allChannelsByUser, value: data)
                }
            }
            NotificationCenter.default.post(
                name: .mezonChannelDescriptionDidUpdate,
                object: nil,
                userInfo: ["clanId": clanId, "channelId": channelId]
            )
        }

        private func mergeIntoClanChannelListPreferenceIfPresent(clanId: Int64, channel: Mezon_Api_ChannelDescription) {
            guard let blob = postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)), !blob.isEmpty else { return }
            var arr = ChannelPreferenceListCodec.decode(blob)
            guard !arr.isEmpty, arr.allSatisfy({ $0.clanID == 0 || $0.clanID == clanId }) else { return }
            if let idx = arr.firstIndex(where: { $0.channelID == channel.channelID }) {
                arr[idx] = channel
            } else {
                arr.append(channel)
            }
            guard let data = ChannelPreferenceListCodec.encode(arr) else { return }
            postbox.setPreferenceDataSync(key: PreferencesKeys.channelList(clanId: clanId), value: data)
        }

        func getInviteInfo(code: String, token: String) async throws -> ClanInviteInfo {
            try await network.getInviteInfo(code: code, token: token)
        }

        func joinClanWithInvite(code: String, token: String) async throws -> Mezon_Api_InviteUserRes {
            try await network.joinClanWithInvite(code: code, token: token)
        }

        func createClanDesc(name: String, logo: String = "", banner: String = "", token: String) async throws -> Mezon_Api_ClanDesc {
            try await network.createClanDesc(name: name, logo: logo, banner: banner, token: token)
        }

        func applyCreationTemplateChannels(clanId: Int64, template: ClanCreationTemplate, token: String) async {
            do {
                let channelList = try await network.listChannelDescs(clanId: clanId, token: token)
                var defaultCategoryId = channelList.first(where: { $0.parentID == 0 })?.categoryID
                    ?? channelList.first?.categoryID
                    ?? 0
                if defaultCategoryId == 0 {
                    let cats = try await network.listCategoryDescs(clanId: clanId, token: token)
                    defaultCategoryId = cats.first?.categoryID ?? 0
                }
                guard defaultCategoryId != 0 else { return }

                for block in template.postCreateCategoryPlans {
                    var categoryId = defaultCategoryId
                    if !block.categoryName.isEmpty {
                        categoryId = try await network.createCategoryDesc(
                            clanId: clanId,
                            categoryName: block.categoryName,
                            token: token
                        ).categoryID
                    }
                    guard categoryId != 0 else { continue }
                    for ch in block.channels {
                        _ = try await network.createClanChannelDesc(
                            clanId: clanId,
                            categoryId: categoryId,
                            channelLabel: ch.name,
                            type: ch.channelType,
                            channelPrivate: ch.isPrivate ? 1 : 0,
                            token: token
                        )
                        try await Task.sleep(nanoseconds: 400_000_000)
                    }
                }
            } catch {}
        }
    }

    @MainActor
    final class FriendsData {
        private let engine: MezonEngine
        private var network: MezonHTTPClient { engine.account.network }
        private var postbox: Postbox { engine.account.postbox }

        let friendsUpdated = ValuePipe<Void>()

        private var socketDisposable: Disposable?
        private var socketRefreshTask: Task<Void, Never>?
        private var tokenProvider: (() async -> String?)?
        private var inflightNetworkRefreshTask: Task<Void, Never>?
        private var lastFriendsNetworkRefreshAt: Date?
        private let friendsNetworkRefreshCooldown: TimeInterval = 3.0

        init(engine: MezonEngine) {
            self.engine = engine
        }

        func resetForLogout() {
            socketDisposable?.dispose()
            socketDisposable = nil
            socketRefreshTask?.cancel()
            socketRefreshTask = nil
            inflightNetworkRefreshTask?.cancel()
            inflightNetworkRefreshTask = nil
            tokenProvider = nil
            lastFriendsNetworkRefreshAt = nil
        }

        deinit {
            socketDisposable?.dispose()
            socketRefreshTask?.cancel()
            inflightNetworkRefreshTask?.cancel()
        }

        func start(tokenProvider: @escaping () async -> String?) {
            self.tokenProvider = tokenProvider
            socketDisposable?.dispose()
            socketDisposable = (MezonSocket.shared.events()
                |> deliverOnMainQueue).start(next: { [weak self] event in
                    guard let self else { return }
                    switch event {
                    case .addFriend, .removeFriend, .blockFriend:
                        self.scheduleRefreshFromSocket()
                    default:
                        break
                    }
                })
        }

        func allFriends() -> [Mezon_Api_Friend] {
            decodeFriends(postbox.getPreferenceData(key: PreferencesKeys.friendsList))
        }

        func pendingIncomingFriends() -> [Mezon_Api_Friend] {
            allFriends().filter { $0.state == EStateFriend.myPending.rawValue }
        }

        func incomingFriendRequestCount() -> Int {
            pendingIncomingFriends().count
        }

        func blockedUserIds() -> Set<Int64> {
            Set(allFriends().filter { friend in
                friend.state == EStateFriend.block.rawValue && friend.hasUser && friend.user.id != 0
            }.map(\.user.id))
        }

        func lookupByUsername() -> [String: Mezon_Api_Friend] {
            var result: [String: Mezon_Api_Friend] = [:]
            for friend in allFriends() {
                let username = friend.user.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !username.isEmpty else { continue }
                result[username] = friend
            }
            return result
        }

        func refreshFromNetwork(token: String, force: Bool = false) async {
            if let inflight = inflightNetworkRefreshTask {
                _ = await inflight.value
                if !force { return }
            }
            if !force,
               let last = lastFriendsNetworkRefreshAt,
               Date().timeIntervalSince(last) < friendsNetworkRefreshCooldown {
                return
            }
            let task = Task<Void, Never> { @MainActor [weak self] in
                guard let self else { return }
                defer { self.inflightNetworkRefreshTask = nil }
                await self.performRefreshFromNetwork(token: token)
                self.lastFriendsNetworkRefreshAt = Date()
            }
            inflightNetworkRefreshTask = task
            _ = await task.value
        }

        private func performRefreshFromNetwork(token: String) async {
            let net = network
            async let friendList = (try? net.listFriends(token: token, state: EStateFriend.friend.rawValue))?.friends
            async let otherPendingList = (try? net.listFriends(token: token, state: EStateFriend.otherPending.rawValue))?.friends
            async let myPendingList = (try? net.listFriends(token: token, state: EStateFriend.myPending.rawValue))?.friends
            async let blockList = (try? net.listFriends(token: token, state: EStateFriend.block.rawValue))?.friends

            let lists = [await friendList, await otherPendingList, await myPendingList, await blockList].compactMap { $0 }
            let cached = allFriends()

            guard !lists.isEmpty else { return }

            if lists.count == 4, isAllListsIdentical(lists), !cached.isEmpty {
                return
            }

            var dedupByUserId: [Int64: Mezon_Api_Friend] = [:]
            for list in lists {
                for friend in list {
                    dedupByUserId[friend.user.id] = friend
                }
            }

            guard !dedupByUserId.isEmpty || cached.isEmpty else { return }

            let merged = dedupByUserId.values.sorted { lhs, rhs in
                let lName = lhs.user.displayName.isEmpty ? lhs.user.username : lhs.user.displayName
                let rName = rhs.user.displayName.isEmpty ? rhs.user.username : rhs.user.displayName
                if lName.caseInsensitiveCompare(rName) == .orderedSame {
                    return lhs.user.id < rhs.user.id
                }
                return lName.localizedCaseInsensitiveCompare(rName) == .orderedAscending
            }
            persistFriends(Array(merged))
        }

        private func isAllListsIdentical(_ lists: [[Mezon_Api_Friend]]) -> Bool {
            guard let first = lists.first, !first.isEmpty else { return false }
            let firstSignature = first.map { "\($0.user.id):\($0.state)" }.sorted()
            return lists.dropFirst().allSatisfy {
                $0.map { "\($0.user.id):\($0.state)" }.sorted() == firstSignature
            }
        }

        func removePendingRequest(userId: Int64) {
            var list = allFriends()
            list.removeAll { $0.user.id == userId && $0.state == EStateFriend.myPending.rawValue }
            persistFriends(list)
        }

        private func scheduleRefreshFromSocket() {
            socketRefreshTask?.cancel()
            socketRefreshTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let tokenProvider = self.tokenProvider, let token = await tokenProvider() else { return }
                await self.refreshFromNetwork(token: token, force: true)
            }
        }

        private func persistFriends(_ list: [Mezon_Api_Friend]) {
            postbox.setPreferenceData(
                key: PreferencesKeys.friendsList,
                value: encodeFriends(list)
            )
            friendsUpdated.putNext(())
        }

        private func encodeFriends(_ list: [Mezon_Api_Friend]) -> Data {
            var data = Data()
            var count = UInt32(list.count)
            count = count.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &count) { Array($0) })
            for friend in list {
                guard let entry = try? friend.serializedData() else { continue }
                var len = UInt32(entry.count)
                len = len.littleEndian
                data.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
                data.append(entry)
            }
            return data
        }

        private func decodeFriends(_ data: Data?) -> [Mezon_Api_Friend] {
            guard let data, data.count >= 4 else { return [] }
            return data.withUnsafeBytes { rawPtr in
                guard let base = rawPtr.baseAddress else { return [] }
                var offset = 0
                func readUInt32() -> UInt32? {
                    guard offset + 4 <= rawPtr.count else { return nil }
                    let value = base.advanced(by: offset).assumingMemoryBound(to: UInt32.self).pointee
                    offset += 4
                    return UInt32(littleEndian: value)
                }

                guard let count = readUInt32() else { return [] }
                var result: [Mezon_Api_Friend] = []
                result.reserveCapacity(Int(count))
                for _ in 0..<count {
                    guard let len = readUInt32() else { break }
                    let intLen = Int(len)
                    guard intLen >= 0, offset + intLen <= rawPtr.count else { break }
                    let entryData = Data(bytes: base.advanced(by: offset), count: intLen)
                    offset += intLen
                    if let friend = try? Mezon_Api_Friend(serializedBytes: entryData) {
                        result.append(friend)
                    }
                }
                return result
            }
        }
    }
}
