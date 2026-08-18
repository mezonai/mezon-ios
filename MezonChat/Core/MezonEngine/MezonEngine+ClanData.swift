import Foundation
import SwiftProtobuf

enum ClanEventStatusValue {
    static let upcoming: Int32 = 1
    static let ongoing: Int32 = 2
    static let completed: Int32 = 3
}

enum ChannelPreferenceListCodec {
    static func decode(_ data: Data) -> [Mezon_Api_ChannelDescription] {
        guard data.count >= 4 else { return [] }
        let count = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        var result: [Mezon_Api_ChannelDescription] = []
        var offset = 4
        for _ in 0..<count {
            guard offset + 4 <= data.count else { break }
            let len = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
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

struct ChannelListCachedMeta {
    var categoryDescs: [Mezon_Api_CategoryDesc]
    var favoriteIds: Set<Int64>
}

enum ChannelListMetaCodec {
    static func encode(categoryDescs: [Mezon_Api_CategoryDesc], favoriteIds: Set<Int64>) -> Data {
        var d = Data()
        var version: UInt32 = 1
        d.append(contentsOf: withUnsafeBytes(of: &version) { Array($0) })
        let favSorted = favoriteIds.sorted()
        var favCount = UInt32(favSorted.count)
        d.append(contentsOf: withUnsafeBytes(of: &favCount) { Array($0) })
        for id in favSorted {
            var le = id.littleEndian
            d.append(contentsOf: withUnsafeBytes(of: &le) { Array($0) })
        }
        var catCount = UInt32(categoryDescs.count)
        d.append(contentsOf: withUnsafeBytes(of: &catCount) { Array($0) })
        for c in categoryDescs {
            guard let sd = try? c.serializedData() else { continue }
            var len = UInt32(sd.count)
            d.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
            d.append(sd)
        }
        return d
    }

    static func decode(_ data: Data) -> ChannelListCachedMeta? {
        guard data.count >= 4 else { return nil }
        var offset = 0
        let version = data.subdata(in: 0..<4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard version == 1 else { return nil }
        offset = 4
        guard offset + 4 <= data.count else { return nil }
        let favCount = Int(data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        offset += 4
        var favs = Set<Int64>()
        for _ in 0..<favCount {
            guard offset + 8 <= data.count else { return nil }
            let id = data.subdata(in: offset..<(offset + 8)).withUnsafeBytes { $0.loadUnaligned(as: Int64.self).littleEndian }
            favs.insert(id)
            offset += 8
        }
        guard offset + 4 <= data.count else { return ChannelListCachedMeta(categoryDescs: [], favoriteIds: favs) }
        let catCount = Int(data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        offset += 4
        var cats: [Mezon_Api_CategoryDesc] = []
        for _ in 0..<catCount {
            guard offset + 4 <= data.count else { break }
            let len = Int(data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            offset += 4
            guard offset + len <= data.count else { break }
            if let m = try? Mezon_Api_CategoryDesc(serializedBytes: data.subdata(in: offset..<(offset + len))) {
                cats.append(m)
            }
            offset += len
        }
        return ChannelListCachedMeta(categoryDescs: cats, favoriteIds: favs)
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
        private let clanDataCacheTTL: TimeInterval = 300
        private var inflightForceRefreshClanUsersByClanId: [Int64: Task<Void, Never>] = [:]
        private var lastPresenceMemberRefreshAtByClanId: [Int64: Date] = [:]
        private var attemptedMemberRefreshUserIdsByClanId: [Int64: Set<Int64>] = [:]
        private let presenceMemberRefreshCooldown: TimeInterval = 60
        private var clanUsersMemoByClanId: [Int64: (list: Mezon_Api_ClanUserList?, at: Date)] = [:]
        private let clanUsersMemoTTL: TimeInterval = 2
        private let clanUsersMemoMaxEntries = 4
        private var clanEventSocketVersionsByClanId: [Int64: Int] = [:]
        private var inflightEventFetchesByClanId: [Int64: Task<Void, Never>] = [:]
        private var clanEventFetchIdsByClanId: [Int64: UUID] = [:]
        private var pendingForcedEventFetchIdsByClanId: [Int64: UUID] = [:]

        init(engine: MezonEngine) { self.engine = engine }

        func resetForLogout() {
            for (_, task) in inflightFetchAllByClanId {
                task.cancel()
            }
            inflightFetchAllByClanId.removeAll()
            lastFetchAllAtByClanId.removeAll()
            for (_, task) in inflightForceRefreshClanUsersByClanId {
                task.cancel()
            }
            inflightForceRefreshClanUsersByClanId.removeAll()
            lastPresenceMemberRefreshAtByClanId.removeAll()
            attemptedMemberRefreshUserIdsByClanId.removeAll()
            clanUsersMemoByClanId.removeAll()
            for (_, task) in inflightEventFetchesByClanId {
                task.cancel()
            }
            inflightEventFetchesByClanId.removeAll()
            clanEventFetchIdsByClanId.removeAll()
            pendingForcedEventFetchIdsByClanId.removeAll()
            clanEventSocketVersionsByClanId.removeAll()
        }

        func cancelFetchAllClanData(exceptClanId: Int64) {
            for (cid, task) in inflightFetchAllByClanId where cid != exceptClanId {
                task.cancel()
                inflightFetchAllByClanId[cid] = nil
                lastFetchAllAtByClanId[cid] = nil
            }
        }

        func fetchAllClanData(clanId: Int64, token: String) {
            Task { @MainActor in
                await self.fetchAllClanDataIfNeeded(clanId: clanId, token: token)
            }
        }

        func fetchAllClanDataIfNeeded(clanId: Int64, token: String) async {
            guard clanId != 0 else { return }
            if let existing = inflightFetchAllByClanId[clanId] {
                await existing.value
                return
            }
            if let last = lastFetchAllAtByClanId[clanId], Date().timeIntervalSince(last) < clanDataCacheTTL {
                return
            }
            lastFetchAllAtByClanId[clanId] = Date()
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    self.inflightFetchAllByClanId[clanId] = nil
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
                if !Task.isCancelled, !self.hasPersistedClanData(clanId: clanId) {
                    self.lastFetchAllAtByClanId[clanId] = nil
                }
            }
            inflightFetchAllByClanId[clanId] = task
            await task.value
        }

        private func hasPersistedClanData(clanId: Int64) -> Bool {
            postbox.getPreferenceData(key: PreferencesKeys.clanRoles(clanId: clanId))?.isEmpty == false
                || postbox.getPreferenceData(key: PreferencesKeys.clanUsers(clanId: clanId))?.isEmpty == false
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

                persistClanUsersResponse(clanId: clanId, response: response)
            } catch {
            }
        }

        func maybeRefreshClanMembersAfterPresenceJoins(clanId: Int64, joinedUserIds: [Int64], token: String) {
            guard clanId != 0, !joinedUserIds.isEmpty else { return }
            if let last = lastPresenceMemberRefreshAtByClanId[clanId],
               Date().timeIntervalSince(last) < presenceMemberRefreshCooldown {
                return
            }
            let knownIds = Set(resolvedClanMembers(clanId: clanId).map(\.userId))
            var attempted = attemptedMemberRefreshUserIdsByClanId[clanId] ?? []
            let unknownIds = joinedUserIds.filter {
                $0 != 0 && !knownIds.contains($0) && !attempted.contains($0)
            }
            guard !unknownIds.isEmpty else { return }
            attempted.formUnion(unknownIds)
            attemptedMemberRefreshUserIdsByClanId[clanId] = attempted
            lastPresenceMemberRefreshAtByClanId[clanId] = Date()
            forceRefreshClanUsers(clanId: clanId, token: token)
        }

        func forceRefreshClanUsers(clanId: Int64, token: String) {
            guard clanId != 0 else { return }
            if let existing = inflightForceRefreshClanUsersByClanId[clanId], !existing.isCancelled { return }
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.inflightForceRefreshClanUsersByClanId[clanId] = nil }
                await self.fetchClanUsersForced(clanId: clanId, token: token)
            }
            inflightForceRefreshClanUsersByClanId[clanId] = task
        }

        private func fetchClanUsersForced(clanId: Int64, token: String) async {
            do {
                let response = try await network.listClanUsers(clanId: clanId, token: token)
                persistClanUsersResponse(clanId: clanId, response: response)
            } catch {
            }
        }

        private func persistClanUsersResponse(clanId: Int64, response: Mezon_Api_ClanUserList) {
            let responseMembers = response.clanUsers.map { ClanMemberRecord(from: $0) }
            let existingMembers = postbox.read { tx in tx.getClanMembers(clanId: clanId) }
            var seenUserIds = Set<Int64>()
            let finalMembers = (responseMembers + existingMembers).filter {
                seenUserIds.insert($0.userId).inserted
            }
            postbox.write { tx in
                for clanUser in response.clanUsers {
                    tx.updateProfile(ProfileRecord(from: clanUser))
                }
                tx.updateClanMembers(finalMembers, clanId: clanId)
            }
            syncClanUsersPreferenceCache(clanId: clanId, members: finalMembers)
            let nowKnown = Set(finalMembers.map(\.userId))
            if var attempted = attemptedMemberRefreshUserIdsByClanId[clanId] {
                attempted.subtract(nowKnown)
                attemptedMemberRefreshUserIdsByClanId[clanId] = attempted
            }
            clanUsersUpdated.putNext(clanId)
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

        func refetchEvents(clanId: Int64, token: String) async {
            await fetchEvents(clanId: clanId, token: token, force: true)
        }

        func channelEventStatuses(clanId: Int64) -> [Int64: Int32] {
            var statuses: [Int64: Int32] = [:]
            for event in getClanEvents(clanId: clanId)?.events ?? [] where event.channelID != 0 {
                switch event.eventStatus {
                case ClanEventStatusValue.ongoing:
                    statuses[event.channelID] = ClanEventStatusValue.ongoing
                case ClanEventStatusValue.upcoming:
                    if statuses[event.channelID] != ClanEventStatusValue.ongoing {
                        statuses[event.channelID] = ClanEventStatusValue.upcoming
                    }
                default:
                    break
                }
            }
            return statuses
        }

        @discardableResult
        func applyClanEventStatusUpdate(_ update: Mezon_Api_CreateEventRequest) -> Bool {
            let validStatuses: Set<Int32> = [
                ClanEventStatusValue.upcoming,
                ClanEventStatusValue.ongoing,
                ClanEventStatusValue.completed,
            ]
            guard update.clanID != 0 else {
                return false
            }
            markClanEventSocketUpdate(clanId: update.clanID)
            guard update.action == 0,
                  validStatuses.contains(update.eventStatus) else {
                return false
            }

            guard var list = getClanEvents(clanId: update.clanID) else {
                return false
            }
            guard let index = list.events.firstIndex(where: { $0.id == update.eventID }) else {
                return false
            }

            var event = list.events[index]
            let updatedStartTime = update.eventStatus == ClanEventStatusValue.completed
                && update.startTimeSeconds != 0
                ? update.startTimeSeconds
                : event.startTimeSeconds
            guard event.eventStatus != update.eventStatus || event.startTimeSeconds != updatedStartTime else {
                return true
            }

            event.eventStatus = update.eventStatus
            event.startTimeSeconds = updatedStartTime
            list.events[index] = event
            guard let data = try? list.serializedData() else { return false }
            postbox.setPreferenceDataSync(
                key: PreferencesKeys.clanEvents(clanId: update.clanID),
                value: data
            )
            clanEventsUpdated.putNext(update.clanID)
            return true
        }

        private func markClanEventSocketUpdate(clanId: Int64) {
            clanEventSocketVersionsByClanId[clanId, default: 0] += 1
        }

        func setUserEventInterest(
            clanId: Int64,
            eventId: Int64,
            userId: Int64,
            interested: Bool,
            token: String
        ) async {
            applyUserEventInterestLocally(
                clanId: clanId,
                eventId: eventId,
                userId: userId,
                interested: interested
            )
            clanEventsUpdated.putNext(clanId)
            var req = Mezon_Api_UserEventRequest()
            req.clanID = clanId
            req.eventID = eventId
            do {
                if interested {
                    try await network.addUserEvent(request: req, token: token)
                } else {
                    try await network.deleteUserEvent(request: req, token: token)
                }
            } catch {
                await refetchEvents(clanId: clanId, token: token)
            }
        }

        private func applyUserEventInterestLocally(
            clanId: Int64,
            eventId: Int64,
            userId: Int64,
            interested: Bool
        ) {
            guard var list = getClanEvents(clanId: clanId) else { return }
            guard let index = list.events.firstIndex(where: { $0.id == eventId }) else { return }
            var event = list.events[index]
            var userIds = event.userIds.filter { $0 != 0 }
            if interested {
                if !userIds.contains(userId) {
                    userIds.append(userId)
                }
            } else {
                userIds.removeAll { $0 == userId }
            }
            event.userIds = userIds
            list.events[index] = event
            guard let data = try? list.serializedData() else { return }
            postbox.setPreferenceDataSync(key: PreferencesKeys.clanEvents(clanId: clanId), value: data)
        }

        private func fetchEvents(clanId: Int64, token: String, force: Bool = false) async {
            guard clanId != 0 else { return }
            if let existing = inflightEventFetchesByClanId[clanId] {
                if force, let fetchId = clanEventFetchIdsByClanId[clanId] {
                    pendingForcedEventFetchIdsByClanId[clanId] = fetchId
                }
                await existing.value
                return
            }

            let fetchId = UUID()
            clanEventFetchIdsByClanId[clanId] = fetchId
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    if self.clanEventFetchIdsByClanId[clanId] == fetchId {
                        self.inflightEventFetchesByClanId[clanId] = nil
                        self.clanEventFetchIdsByClanId[clanId] = nil
                        self.pendingForcedEventFetchIdsByClanId[clanId] = nil
                    }
                }

                var shouldFetch = true
                while shouldFetch, !Task.isCancelled {
                    let socketVersion = self.clanEventSocketVersionsByClanId[clanId] ?? 0
                    var appliedCurrentResponse = false
                    do {
                        let response = try await self.network.listEvents(clanId: clanId, token: token)
                        guard !Task.isCancelled,
                              self.clanEventFetchIdsByClanId[clanId] == fetchId else {
                            return
                        }
                        if self.clanEventSocketVersionsByClanId[clanId, default: 0] == socketVersion {
                            if let data = try? response.serializedData() {
                                self.postbox.setPreferenceDataSync(
                                    key: PreferencesKeys.clanEvents(clanId: clanId),
                                    value: data
                                )
                            }
                            self.clanEventsUpdated.putNext(clanId)
                            appliedCurrentResponse = true
                        }
                    } catch {
                    }

                    let hasPendingForce = self.pendingForcedEventFetchIdsByClanId[clanId] == fetchId
                    if hasPendingForce {
                        self.pendingForcedEventFetchIdsByClanId[clanId] = nil
                    }
                    shouldFetch = hasPendingForce && !appliedCurrentResponse
                }
            }
            inflightEventFetchesByClanId[clanId] = task
            await task.value
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
                persistStreamUsersList(response, clanId: clanId)
            } catch {
            }
        }

        private func persistStreamUsersList(_ list: Mezon_Api_StreamingChannelUserList, clanId: Int64) {
            if let data = try? list.serializedData() {
                postbox.setPreferenceData(key: PreferencesKeys.clanStreamUsers(clanId: clanId), value: data)
            }
            clanStreamUsersUpdated.putNext(clanId)
            NotificationCenter.default.post(
                name: .mezonVoicePresenceChanged,
                object: nil,
                userInfo: ["clanId": NSNumber(value: clanId)]
            )
        }

        private func resolvedStreamUsersList(clanId: Int64) -> Mezon_Api_StreamingChannelUserList? {
            guard let data = postbox.getPreferenceData(key: PreferencesKeys.clanStreamUsers(clanId: clanId)),
                  let list = try? Mezon_Api_StreamingChannelUserList(serializedBytes: data) else { return nil }
            return list
        }

        private func voiceChannelUserList(from streamList: Mezon_Api_StreamingChannelUserList) -> Mezon_Api_VoiceChannelUserList {
            var grouped: [Int64: [String]] = [:]
            for user in streamList.streamingChannelUsers {
                guard user.channelID != 0, user.userID != 0 else { continue }
                let uid = "\(user.userID)"
                var ids = grouped[user.channelID] ?? []
                if !ids.contains(uid) {
                    ids.append(uid)
                    grouped[user.channelID] = ids
                }
            }
            var result = Mezon_Api_VoiceChannelUserList()
            result.voiceChannelUsers = grouped.map { channelId, userIds in
                var entry = Mezon_Api_VoiceChannelUser()
                entry.channelID = channelId
                entry.userIds = userIds
                return entry
            }
            return result
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
            if let memo = clanUsersMemoByClanId[clanId], Date().timeIntervalSince(memo.at) < clanUsersMemoTTL {
                return memo.list
            }
            let resolved = readClanUsersFromPostbox(clanId: clanId)
            storeClanUsersMemo(clanId: clanId, list: resolved)
            return resolved
        }

        private func readClanUsersFromPostbox(clanId: Int64) -> Mezon_Api_ClanUserList? {
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

        private func storeClanUsersMemo(clanId: Int64, list: Mezon_Api_ClanUserList?) {
            if clanUsersMemoByClanId[clanId] == nil, clanUsersMemoByClanId.count >= clanUsersMemoMaxEntries,
               let oldest = clanUsersMemoByClanId.min(by: { $0.value.at < $1.value.at })?.key {
                clanUsersMemoByClanId.removeValue(forKey: oldest)
            }
            clanUsersMemoByClanId[clanId] = (list, Date())
        }

        func applyClanUserAddedFromSocket(_ event: Mezon_Realtime_AddClanUserEvent) {
            let clanId = event.clanID
            guard clanId != 0, event.hasUser else { return }
            let user = event.user
            guard user.userID != 0 else { return }

            var members = resolvedClanMembers(clanId: clanId)
            guard !members.contains(where: { $0.userId == user.userID }) else { return }

            members.append(ClanMemberRecord(
                userId: user.userID,
                roleIds: [],
                clanNick: "",
                clanAvatar: "",
                userAvatarURL: user.avatar,
                clanId: clanId,
                isOnline: user.online,
                displayName: user.displayName,
                username: user.username
            ))

            var apiUser = Mezon_Api_User()
            apiUser.id = user.userID
            apiUser.username = user.username
            apiUser.displayName = user.displayName
            apiUser.avatarURL = user.avatar
            apiUser.online = user.online
            apiUser.status = user.status

            postbox.write { tx in
                tx.updateClanMembers(members, clanId: clanId)
                tx.updateProfile(ProfileRecord(from: apiUser))
            }
            syncClanUsersPreferenceCache(clanId: clanId, members: members)
            clanUsersUpdated.putNext(clanId)
        }

        func applyClanMembersFromUserChannelAddedForObservers(
            _ event: Mezon_Realtime_UserChannelAdded,
            observingClanId: Int64
        ) {
            let clanId = event.clanID != 0 ? event.clanID : event.channelDesc.clanID
            guard clanId != 0, clanId == observingClanId, !event.users.isEmpty else { return }

            var members = resolvedClanMembers(clanId: clanId)
            var appended: [ClanMemberRecord] = []
            for user in event.users where user.userID != 0 {
                guard !members.contains(where: { $0.userId == user.userID }) else { continue }
                let member = ClanMemberRecord(
                    userId: user.userID,
                    roleIds: [],
                    clanNick: "",
                    clanAvatar: "",
                    userAvatarURL: user.avatar,
                    clanId: clanId,
                    isOnline: user.online,
                    displayName: user.displayName,
                    username: user.username
                )
                members.append(member)
                appended.append(member)
            }
            guard !appended.isEmpty else { return }

            postbox.write { tx in
                tx.updateClanMembers(members, clanId: clanId)
                for user in appended {
                    var apiUser = Mezon_Api_User()
                    apiUser.id = user.userId
                    apiUser.username = user.username
                    apiUser.displayName = user.displayName
                    apiUser.avatarURL = user.userAvatarURL
                    apiUser.online = user.isOnline
                    tx.updateProfile(ProfileRecord(from: apiUser))
                }
            }
            syncClanUsersPreferenceCache(clanId: clanId, members: members)
            clanUsersUpdated.putNext(clanId)
        }

        func applyClanUserRemovedFromSocket(_ event: Mezon_Realtime_UserClanRemoved) {
            let clanId = event.clanID
            let removeSet = Set(event.userIds)
            guard clanId != 0, !removeSet.isEmpty else { return }

            var members = resolvedClanMembers(clanId: clanId)
            let filtered = members.filter { !removeSet.contains($0.userId) }
            guard filtered.count != members.count else { return }

            postbox.write { tx in
                tx.updateClanMembers(filtered, clanId: clanId)
            }
            syncClanUsersPreferenceCache(clanId: clanId, members: filtered)
            clanUsersUpdated.putNext(clanId)
        }

        private func resolvedClanMembers(clanId: Int64) -> [ClanMemberRecord] {
            let rows = postbox.read { tx in tx.getClanMembers(clanId: clanId) }
            if !rows.isEmpty { return rows }
            if let cached = getClanUsers(clanId: clanId) {
                return cached.clanUsers.map { ClanMemberRecord(from: $0) }
            }
            return []
        }

        private func syncClanUsersPreferenceCache(clanId: Int64, members: [ClanMemberRecord]) {
            var list = Mezon_Api_ClanUserList()
            list.clanID = clanId
            list.clanUsers = members.map { $0.toClanUserListClanUser() }
            guard let data = try? list.serializedData() else { return }
            postbox.setPreferenceDataSync(key: PreferencesKeys.clanUsers(clanId: clanId), value: data)
            storeClanUsersMemo(clanId: clanId, list: list.clanUsers.isEmpty ? nil : list)
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
            guard let streamList = resolvedStreamUsersList(clanId: clanId) else { return nil }
            return voiceChannelUserList(from: streamList)
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

        func applyStreamJoined(
            clanId: Int64,
            channelId: Int64,
            userId: Int64,
            entryId: Int64 = 0,
            participant: String = ""
        ) {
            guard clanId != 0, channelId != 0, userId != 0 else { return }
            var list = resolvedStreamUsersList(clanId: clanId) ?? Mezon_Api_StreamingChannelUserList()
            list.streamingChannelUsers.removeAll { $0.userID == userId && $0.channelID != channelId }
            list.streamingChannelUsers.removeAll { $0.channelID == channelId && $0.userID == userId }
            var user = Mezon_Api_StreamingChannelUser()
            user.id = entryId
            user.userID = userId
            user.channelID = channelId
            user.participant = participant
            list.streamingChannelUsers.append(user)
            persistStreamUsersList(list, clanId: clanId)
        }

        func applyStreamLeaved(clanId: Int64, channelId: Int64, userId: Int64) {
            guard clanId != 0, channelId != 0, userId != 0 else { return }
            var list = resolvedStreamUsersList(clanId: clanId) ?? Mezon_Api_StreamingChannelUserList()
            list.streamingChannelUsers.removeAll { $0.channelID == channelId && $0.userID == userId }
            persistStreamUsersList(list, clanId: clanId)
        }

        func applyStreamLeaved(clanId: Int64, entryId: String) {
            guard clanId != 0, !entryId.isEmpty else { return }
            var list = resolvedStreamUsersList(clanId: clanId) ?? Mezon_Api_StreamingChannelUserList()
            if let numericId = Int64(entryId) {
                list.streamingChannelUsers.removeAll { $0.id == numericId }
            } else {
                list.streamingChannelUsers.removeAll { "\($0.id)" == entryId }
            }
            persistStreamUsersList(list, clanId: clanId)
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
            return data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self).littleEndian }
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
        
        func applyLocallyCreatedChannel(
            _ ch: Mezon_Api_ChannelDescription,
            skipChannelListFetch: Bool = false
        ) {
            upsertAllChannelsByUserCache(ch)
            if ch.clanID != 0 {
                mergeIntoClanChannelListPreferenceIfPresent(clanId: ch.clanID, channel: ch)
                if ch.parentID != 0 {
                    mergeIntoThreadListPreferenceIfPresent(
                        clanId: ch.clanID,
                        parentChannelId: ch.parentID,
                        thread: ch
                    )
                }
            }

            NotificationCenter.default.post(
                name: .mezonUserChannelAddedFromSocket,
                object: nil,
                userInfo: [
                    "clanId": ch.clanID,
                    "channelId": ch.channelID,
                    "channel": ch,
                    "skipChannelListFetch": skipChannelListFetch
                ]
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
            } else if channel.parentID != 0,
                      let parentIdx = arr.firstIndex(where: { $0.channelID == channel.parentID }) {
                var insertAt = parentIdx + 1
                while insertAt < arr.count, arr[insertAt].parentID == channel.parentID {
                    insertAt += 1
                }
                arr.insert(channel, at: insertAt)
            } else {
                arr.append(channel)
            }
            guard let data = ChannelPreferenceListCodec.encode(arr) else { return }
            postbox.setPreferenceDataSync(key: PreferencesKeys.channelList(clanId: clanId), value: data)
        }

        private func mergeIntoThreadListPreferenceIfPresent(
            clanId: Int64,
            parentChannelId: Int64,
            thread: Mezon_Api_ChannelDescription
        ) {
            guard clanId != 0, parentChannelId != 0, thread.channelID != 0 else { return }
            let key = PreferencesKeys.threadList(clanId: clanId, parentChannelId: parentChannelId)
            var threads: [Mezon_Api_ChannelDescription] = []
            if let blob = postbox.getPreferenceData(key: key), !blob.isEmpty {
                threads = decodeThreadListPreferenceBlob(blob)
            }
            if let idx = threads.firstIndex(where: { $0.channelID == thread.channelID }) {
                threads[idx] = thread
            } else {
                threads.insert(thread, at: 0)
            }
            guard let data = encodeThreadListPreferenceBlob(threads) else { return }
            postbox.setPreferenceDataSync(key: key, value: data)
        }

        private func encodeThreadListPreferenceBlob(_ channels: [Mezon_Api_ChannelDescription]) -> Data? {
            var result = Data()
            var ts = Date().timeIntervalSince1970
            result.append(contentsOf: withUnsafeBytes(of: &ts) { Array($0) })
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

        private func decodeThreadListPreferenceBlob(_ data: Data) -> [Mezon_Api_ChannelDescription] {
            guard data.count >= 8 + 4 else { return [] }
            var offset = 8
            let count = Int(data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            offset += 4
            guard count >= 0, count < 4096 else { return [] }
            var channels: [Mezon_Api_ChannelDescription] = []
            for _ in 0..<count {
                guard offset + 4 <= data.count else { break }
                let len = Int(data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
                offset += 4
                guard offset + len <= data.count, len > 0 else { break }
                if let ch = try? Mezon_Api_ChannelDescription(serializedBytes: data.subdata(in: offset..<(offset + len))) {
                    channels.append(ch)
                }
                offset += len
            }
            return channels
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
                    case .blockFriend(let m):
                        self.applyLocalBlockState(userId: m.userID, blocked: true, blockerUserId: m.userID)
                        self.scheduleRefreshFromSocket()
                    case .unBlockFriend(let m):
                        self.applyLocalBlockState(userId: m.userID, blocked: false)
                        self.scheduleRefreshFromSocket()
                    case .addFriend, .removeFriend:
                        self.scheduleRefreshFromSocket()
                    default:
                        break
                    }
                })
        }

        func applyLocalBlockState(userId: Int64, blocked: Bool, blockerUserId: Int64 = 0) {
            guard userId != 0 else { return }
            var list = allFriends()
            guard let idx = list.firstIndex(where: { $0.user.id == userId }) else { return }
            let newState = blocked ? EStateFriend.block.rawValue : EStateFriend.friend.rawValue
            guard list[idx].state != newState else { return }
            list[idx].state = newState
            if blocked, blockerUserId != 0 {
                list[idx].sourceID = blockerUserId
            }
            persistFriends(list)
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
            guard let fetched = (try? await net.listFriends(token: token, limit: 100, state: 0))?.friends else {
                return
            }
            let cached = allFriends()

            guard !fetched.isEmpty || cached.isEmpty else { return }

            var dedupByUserId: [Int64: Mezon_Api_Friend] = [:]
            for friend in fetched {
                dedupByUserId[friend.user.id] = friend
            }

            for cachedFriend in cached {
                guard cachedFriend.hasUser, cachedFriend.user.id != 0 else { continue }
                if dedupByUserId[cachedFriend.user.id] == nil,
                   cachedFriend.state != EStateFriend.friend.rawValue {
                    dedupByUserId[cachedFriend.user.id] = cachedFriend
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

        func removePendingRequest(userId: Int64) {
            var list = allFriends()
            list.removeAll { $0.user.id == userId && $0.state == EStateFriend.myPending.rawValue }
            persistFriends(list)
        }

        func scheduleRefreshFromSocket() {
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
                let maxPossibleEntries = (rawPtr.count - offset) / 4
                result.reserveCapacity(min(Int(count), maxPossibleEntries))
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
