import Foundation
import SwiftProtobuf

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

        init(engine: MezonEngine) { self.engine = engine }

        func fetchAllClanData(clanId: Int64, token: String) {
            Task { @MainActor [weak self] in
                guard let self else { return }

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
        }

        private func fetchClanUsers(clanId: Int64, token: String) async {
            do {
                let response = try await network.listClanUsers(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.clanUsers(clanId: clanId), value: data)
                }
                clanUsersUpdated.putNext(clanId)
                AppLogger.network.debug("[ClanData] fetched \(response.clanUsers.count) clan users for clan \(clanId)")
            } catch {
                AppLogger.network.warning("[ClanData] fetchClanUsers failed: \(error)")
            }
        }

        private func fetchRoles(clanId: Int64, token: String) async {
            do {
                let response = try await network.listRoles(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.clanRoles(clanId: clanId), value: data)
                }
                clanRolesUpdated.putNext(clanId)
                AppLogger.network.debug("[ClanData] fetched \(response.roles.roles.count) roles for clan \(clanId)")
            } catch {
                AppLogger.network.warning("[ClanData] fetchRoles failed: \(error)")
            }
        }

        private func fetchEvents(clanId: Int64, token: String) async {
            do {
                let response = try await network.listEvents(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.clanEvents(clanId: clanId), value: data)
                }
                clanEventsUpdated.putNext(clanId)
                AppLogger.network.debug("[ClanData] fetched events for clan \(clanId)")
            } catch {
                AppLogger.network.warning("[ClanData] fetchEvents failed: \(error)")
            }
        }

        private func fetchUserPermissions(clanId: Int64, token: String) async {
            do {
                let response = try await network.getRoleOfUserInTheClan(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.clanUserPermissions(clanId: clanId), value: data)
                }
                clanPermissionsUpdated.putNext(clanId)
                AppLogger.network.debug("[ClanData] fetched user permissions for clan \(clanId)")
            } catch {
                AppLogger.network.warning("[ClanData] fetchUserPermissions failed: \(error)")
            }
        }

        private func fetchAllPermissions(token: String) async {
            do {
                let response = try await network.getListPermission(token: token)
                if let data = try? response.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.allPermissions, value: data)
                }
                AppLogger.network.debug("[ClanData] fetched \(response.permissions.count) permissions")
            } catch {
                AppLogger.network.warning("[ClanData] fetchAllPermissions failed: \(error)")
            }
        }

        private func fetchVoiceChannelUsers(clanId: Int64, token: String) async {
            do {
                let response = try await network.listChannelVoiceUsers(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.clanVoiceUsers(clanId: clanId), value: data)
                }
                clanVoiceUsersUpdated.putNext(clanId)
                AppLogger.network.debug("[ClanData] fetched voice users for clan \(clanId)")
            } catch {
                AppLogger.network.warning("[ClanData] fetchVoiceChannelUsers failed: \(error)")
            }
        }

        private func fetchStreamChannelUsers(clanId: Int64, token: String) async {
            do {
                let response = try await network.listStreamingChannelUsers(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.clanStreamUsers(clanId: clanId), value: data)
                }
                clanStreamUsersUpdated.putNext(clanId)
                AppLogger.network.debug("[ClanData] fetched stream users for clan \(clanId)")
            } catch {
                AppLogger.network.warning("[ClanData] fetchStreamChannelUsers failed: \(error)")
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
                AppLogger.network.debug("[ClanData] fetched default notification for clan \(clanId)")
            } catch {
                AppLogger.network.warning("[ClanData] fetchDefaultNotification failed: \(error)")
            }
        }

        private func fetchCategoryNotification(clanId: Int64, token: String) async {
            do {
                let response = try await network.getChannelCategoryNotiSettingsList(clanId: clanId, token: token)
                if let data = try? response.serializedData() {
                    postbox.setPreferenceData(key: PreferencesKeys.clanCategoryNotification(clanId: clanId), value: data)
                }
                AppLogger.network.debug("[ClanData] fetched category notification settings for clan \(clanId)")
            } catch {
                AppLogger.network.warning("[ClanData] fetchCategoryNotification failed: \(error)")
            }
        }


        func getClanUsers(clanId: Int64) -> Mezon_Api_ClanUserList? {
            guard let data = postbox.getPreferenceData(key: PreferencesKeys.clanUsers(clanId: clanId)) else { return nil }
            return try? Mezon_Api_ClanUserList(serializedBytes: data)
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

        func getInviteInfo(code: String, token: String) async throws -> ClanInviteInfo {
            try await network.getInviteInfo(code: code, token: token)
        }

        func joinClanWithInvite(code: String, token: String) async throws -> Mezon_Api_InviteUserRes {
            try await network.joinClanWithInvite(code: code, token: token)
        }
    }
}
