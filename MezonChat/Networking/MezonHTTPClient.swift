import Foundation
import SwiftProtobuf

final class MezonHTTPClient {

    static let shared = MezonHTTPClient()
    var bearerUnauthorizedRecovery: (() async throws -> String?)?

    private let urlSession: URLSession
    private var authBaseURL: URL = MezonConfig.authBaseURL
    private var protoBaseURL: URL = MezonConfig.protoBaseURL

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        if #available(iOS 15.0, *) {
            config.multipathServiceType = .handover
        }
        if #available(iOS 17.0, *),
           config.responds(to: Selector(("setAssumesHTTP3Capable:"))) {
            config.setValue(true, forKey: "assumesHTTP3Capable")
        }
        urlSession = URLSession(configuration: config)
    }

    func updateBaseURL(from session: MezonSession) {
        guard let apiURL = session.apiURL else { return }
        let cleaned = stripDefaultPort(apiURL)
        guard let url = URL(string: cleaned) else { return }
        protoBaseURL = url
        AppLogger.network.info("MezonHTTPClient protoBaseURL updated to \(url)")
    }

    private func stripDefaultPort(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else { return urlString }
        let isHTTPS = components.scheme?.lowercased() == "https"
        if isHTTPS && components.port == 443 {
            components.port = nil
        }
        return components.string ?? urlString
    }

    func authenticateEmail(email: String, password: String) async throws -> MezonSession {
        struct Account: Encodable {
            let email: String
            let password: String
            let vars: [String: String]
        }
        struct Body: Encodable { let account: Account }
        return try await post(
            path: "/v2/account/authenticate/email",
            queryItems: [URLQueryItem(name: "create", value: "false")],
            body: Body(account: Account(email: email, password: password, vars: ["m": "true"])),
            auth: .serverKey
        )
    }

    func authenticateEmailOTPRequest(email: String) async throws -> OTPRequestResponse {
        struct Account: Encodable {
            let email: String
            let vars: [String: String]
        }
        struct Body: Encodable { let account: Account }
        return try await post(
            path: "/v2/account/authenticate/emailotp",
            body: Body(account: Account(email: email, vars: ["m": "true"])),
            auth: .serverKey
        )
    }

    func authenticateSMSOTPRequest(phone: String) async throws -> OTPRequestResponse {
        struct Account: Encodable {
            let phoneno: String
            let vars: [String: String]
        }
        struct Body: Encodable { let account: Account }
        return try await post(
            path: "/v2/account/authenticate/smsotp",
            body: Body(account: Account(phoneno: phone, vars: ["m": "true"])),
            auth: .serverKey
        )
    }

    func confirmAuthenticateOTP(reqId: String, otp: String) async throws -> MezonSession {
        struct Body: Encodable {
            let req_id: String
            let otp_code: String
        }
        return try await post(
            path: "/v2/account/authenticate/confirmotp",
            body: Body(req_id: reqId, otp_code: otp),
            auth: .serverKey
        )
    }

    func confirmLogin(loginId: String, token: String) async throws -> MezonSession {
        struct Body: Encodable {
            let login_id: String
        }
        return try await post(
            path: "/v2/account/authenticate/confirmlogin",
            body: Body(login_id: loginId),
            auth: .bearer(token)
        )
    }

    func getAccount(token: String) async throws -> Mezon_Api_Account {
        let empty = SwiftProtobuf.Google_Protobuf_Empty()
        return try await postProto(
            path: "/mezon.api.Mezon/GetAccount",
            message: empty,
            auth: .bearer(token)
        )
    }

    func updateUserStatus(_ request: Mezon_Api_UserStatusUpdate, token: String) async throws {
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/UpdateUserStatus",
            message: request,
            auth: .bearer(token)
        )
    }

    func getUserStatus(token: String) async throws -> Mezon_Api_UserStatus {
        let empty = SwiftProtobuf.Google_Protobuf_Empty()
        return try await postProto(
            path: "/mezon.api.Mezon/GetUserStatus",
            message: empty,
            auth: .bearer(token)
        )
    }

    func sessionRefresh(refreshToken: String) async throws -> MezonSession {
        var req = Mezon_Api_SessionRefreshRequest()
        req.token = refreshToken
        req.vars = ["m": "true"]
        let apiSession: Mezon_Api_Session = try await postProto(
            path: "/mezon.api.Mezon/SessionRefresh",
            message: req,
            auth: .serverKey
        )
        return MezonSession.fromProto(apiSession)
    }

    func sessionLogout(session: MezonSession, deviceId: String = "", platform: String = "") async throws {
        var req = Mezon_Api_SessionLogoutRequest()
        req.token = session.token
        req.refreshToken = session.refreshToken
        req.deviceID = deviceId
        req.platform = platform
        let _: SwiftProtobuf.Google_Protobuf_Empty = try await postProto(
            path: "/mezon.api.Mezon/SessionLogout",
            message: req,
            auth: .bearer(session.token)
        )
    }

    func getInviteInfo(code: String, token: String) async throws -> ClanInviteInfo {
        let req = try buildRequest(
            method: "GET", path: "/v2/invite/\(code)", queryItems: [],
            body: Optional<EmptyBody>.none,
            auth: .serverKey
        )
        return try await execute(req, allowBearerRetry: false)
    }

    func joinClanWithInvite(code: String, token: String) async throws -> Mezon_Api_InviteUserRes {
        var req = Mezon_Api_InviteUserRequest()
        req.inviteID = Int64(code) ?? 0
        return try await postProto(
            path: "/mezon.api.Mezon/InviteUser",
            message: req,
            auth: .bearer(token)
        )
    }

    func listChannelDescs(clanId: Int64, token: String) async throws -> [Mezon_Api_ChannelDescription] {
        var req = Mezon_Api_ListChannelDescsRequest()
        req.clanID      = clanId
        req.limit       = 500
        req.state       = 1
        req.page        = 0
        req.channelType = 1
        req.isMobile    = true
        let response: Mezon_Api_ChannelDescList = try await postProto(
            path: "/mezon.api.Mezon/ListChannelDescs",
            message: req,
            auth: .bearer(token)
        )
        return response.channeldesc
    }

    func listCategoryDescs(clanId: Int64, token: String) async throws -> [Mezon_Api_CategoryDesc] {
        var req = Mezon_Api_ListCategoryDescsRequest()
        req.clanID = clanId
        req.limit = 100
        let response: Mezon_Api_CategoryDescList = try await postProto(
            path: "/mezon.api.Mezon/ListCategoryDescs",
            message: req,
            auth: .bearer(token)
        )
        return response.categorydesc
    }

    func listFavoriteChannelIds(clanId: Int64, token: String) async throws -> [Int64] {
        var req = Mezon_Api_ListFavoriteChannelRequest()
        req.clanID = clanId
        let response: Mezon_Api_ListFavoriteChannelResponse = try await postProto(
            path: "/mezon.api.Mezon/GetListFavoriteChannel",
            message: req,
            auth: .bearer(token)
        )
        return response.channelIds
    }

    func listDirectMessageChannels(token: String) async throws -> [Mezon_Api_ChannelDescription] {
        var req = Mezon_Api_ListChannelDescsRequest()
        req.clanID      = 0
        req.limit       = 500
        req.state       = 1
        req.page        = 0
        req.channelType = 3
        req.isMobile    = true
        let response: Mezon_Api_ChannelDescList = try await postProto(
            path: "/mezon.api.Mezon/ListChannelDescs",
            message: req,
            auth: .bearer(token)
        )
        return response.channeldesc
    }

    func listThreadDescs(
        parentChannelId: Int64,
        clanId: Int64,
        page: Int32,
        token: String
    ) async throws -> Mezon_Api_ChannelDescList {
        var req = Mezon_Api_ListThreadRequest()
        req.limit = 100
        req.state = 0
        req.clanID = clanId
        req.channelID = parentChannelId
        req.threadID = 0
        req.page = page
        return try await postProto(
            path: "/mezon.api.Mezon/ListThreadDescs",
            message: req,
            auth: .bearer(token)
        )
    }

    func searchThread(
        clanId: Int64,
        parentChannelId: Int64,
        label: String,
        token: String
    ) async throws -> Mezon_Api_ChannelDescList {
        var req = Mezon_Api_SearchThreadRequest()
        req.clanID = clanId
        req.channelID = parentChannelId
        req.label = label
        return try await postProto(
            path: "/mezon.api.Mezon/SearchThread",
            message: req,
            auth: .bearer(token)
        )
    }

    func listChannelBadgeCount(clanId: Int64, token: String) async throws -> Mezon_Api_ListChannelBadgeCountResponse {
        var req = Mezon_Api_ListChannelBadgeCountRequest()
        req.clanID = clanId
        return try await postProto(
            path: "/mezon.api.Mezon/ListChannelBadgeCount",
            message: req,
            auth: .bearer(token)
        )
    }

    func createDirectMessage(userId: Int64, token: String) async throws -> Mezon_Api_ChannelDescription {
        var req = Mezon_Api_CreateChannelDescRequest()
        req.clanID = 0
        req.type = MezonConstants.ChannelType.dm.rawValue
        req.channelPrivate = 1
        req.userIds = [userId]
        return try await postProto(
            path: "/mezon.api.Mezon/CreateChannelDesc",
            message: req,
            auth: .bearer(token)
        )
    }

    func listClanDescs(token: String) async throws -> [Mezon_Api_ClanDesc] {
        var req = Mezon_Api_ListClanDescRequest()
        req.limit = 100
        let response: Mezon_Api_ClanDescList = try await postProto(
            path: "/mezon.api.Mezon/ListClanDescs",
            message: req,
            auth: .bearer(token)
        )
        return response.clandesc
    }

    func listNotifications(clanID: Int64, category: Int32, token: String, notificationID: Int64)
        async throws
        -> [Mezon_Api_Notification]
    {
        var req = Mezon_Api_ListNotificationsRequest()
        req.limit = 50
        req.clanID = clanID
        req.notificationID = notificationID | 0
        req.category = category
        let response: Mezon_Api_NotificationList = try await postProto(
            path: "/mezon.api.Mezon/ListNotifications",
            message: req,
            auth: .bearer(token)
        )
        return response.notifications
    }

    func listSdTopics(clanID: Int64, token: String) async throws -> [Mezon_Api_SdTopic] {
        var req = Mezon_Api_ListSdTopicRequest()
        req.clanID = clanID
        req.limit = 50
        let response: Mezon_Api_SdTopicList = try await postProto(
            path: "/mezon.api.Mezon/ListSdTopic",
            message: req,
            auth: .bearer(token)
        )
        return response.topics
    }

    func getTopicDetail(topicId: Int64, token: String) async throws -> Mezon_Api_SdTopic {
        var req = Mezon_Api_SdTopicDetailRequest()
        req.topicID = topicId
        let response: Mezon_Api_SdTopic = try await postProto(
            path: "/mezon.api.Mezon/GetTopicDetail",
            message: req,
            auth: .bearer(token)
        )
        return response
    }

    func getUserProfileOnClan(clanId: Int64, token: String) async throws -> Mezon_Api_ClanProfile {
        var req = Mezon_Api_ClanProfileRequest()
        req.clanID = clanId
        return try await postProto(
            path: "/mezon.api.Mezon/GetUserProfileOnClan",
            message: req,
            auth: .bearer(token)
        )
    }

    func sendChannelMessage(
        clanId: Int64,
        channelId: Int64,
        mode: Int32,
        isPublic: Bool,
        content: String,
        mentions: [Mezon_Api_MessageMention] = [],
        attachments: [Mezon_Api_MessageAttachment] = [],
        references: [Mezon_Api_MessageRef] = [],
        anonymous: Bool = false,
        mentionEveryone: Bool = false,
        avatar: String = "",
        topicId: Int64 = 0,
        code: Int32 = 0,
        token: String
    ) async throws -> Mezon_Realtime_ChannelMessageAck {
        var req = Mezon_Realtime_ChannelMessageSend()
        req.clanID = clanId
        req.channelID = channelId
        req.mode = mode
        req.isPublic = isPublic
        req.content = content
        req.mentions = mentions
        req.attachments = attachments
        req.references = references
        req.anonymousMessage = anonymous
        req.mentionEveryone = mentionEveryone
        req.avatar = avatar
        req.topicID = topicId
        req.code = code

        return try await postProto(
            path: "/mezon.api.Mezon/SendChannelMessage",
            message: req,
            auth: .bearer(token)
        )
    }

    func listChannelMessages(
        clanId: Int64,
        channelId: Int64,
        messageId: Int64 = 0,
        direction: Int32 = 2,
        limit: Int32 = 50,
        topicId: Int64 = 0,
        token: String
    ) async throws -> Mezon_Api_ChannelMessageList {
        var req = Mezon_Api_ListChannelMessagesRequest()
        req.clanID = clanId
        req.channelID = channelId
        req.messageID = messageId
        req.direction = direction
        req.limit = limit
        req.topicID = topicId
        return try await postProto(
            path: "/mezon.api.Mezon/ListChannelMessages",
            message: req,
            auth: .bearer(token)
        )
    }

    func updateChannelDesc(
        clanId: Int64,
        channelId: Int64,
        channelLabel: String? = nil,
        topic: String? = nil,
        categoryId: Int64? = nil,
        token: String
    ) async throws -> Mezon_Api_ChannelDescription {
        var req = Mezon_Api_UpdateChannelDescRequest()
        req.clanID = clanId
        req.channelID = channelId
        if let channelLabel = channelLabel {
            var labelValue = SwiftProtobuf.Google_Protobuf_StringValue()
            labelValue.value = channelLabel
            req.channelLabel = labelValue
        }
        if let topic = topic {
            req.topic = topic
        }
        if let categoryId = categoryId {
            req.categoryID = categoryId
        }
        return try await postProto(
            path: "/mezon.api.Mezon/UpdateChannelDesc",
            message: req,
            auth: .bearer(token)
        )
    }

    func getNotificationChannel(channelId: Int64, token: String) async throws -> Mezon_Api_NotificationUserChannel {
        var req = Mezon_Api_NotificationChannel()
        req.channelID = channelId
        return try await postProto(
            path: "/mezon.api.Mezon/GetNotificationChannel",
            message: req,
            auth: .bearer(token)
        )
    }

    func listUserPermissionInChannel(clanId: Int64, channelId: Int64, token: String) async throws -> Mezon_Api_UserPermissionInChannelListResponse {
        var req = Mezon_Api_UserPermissionInChannelListRequest()
        req.clanID = clanId
        req.channelID = channelId
        return try await postProto(
            path: "/mezon.api.Mezon/ListUserPermissionInChannel",
            message: req,
            auth: .bearer(token)
        )
    }

    func listChannelUsers(clanId: Int64, channelId: Int64, channelType: Int32, limit: Int32 = 2000, state: Int32 = 1, token: String) async throws -> Mezon_Api_ChannelUserList {
        var req = Mezon_Api_ListChannelUsersRequest()
        req.clanID = clanId
        req.channelID = channelId
        req.channelType = channelType
        req.limit = limit
        req.state = state
        return try await postProto(
            path: "/mezon.api.Mezon/ListChannelUsers",
            message: req,
            auth: .bearer(token)
        )
    }

    func isBanned(channelId: Int64, token: String) async throws -> Mezon_Api_IsBannedResponse {
        var req = Mezon_Api_IsBannedRequest()
        req.channelID = channelId
        return try await postProto(
            path: "/mezon.api.Mezon/IsBanned",
            message: req,
            auth: .bearer(token)
        )
    }

    func listClanUsers(clanId: Int64, token: String) async throws -> Mezon_Api_ClanUserList {
        var req = Mezon_Api_ListClanUsersRequest()
        req.clanID = clanId
        return try await postProto(
            path: "/mezon.api.Mezon/ListClanUsers",
            message: req,
            auth: .bearer(token)
        )
    }

    func listRoles(clanId: Int64, limit: Int32 = 500, state: Int32 = 1, token: String) async throws -> Mezon_Api_RoleListEventResponse {
        var req = Mezon_Api_RoleListEventRequest()
        req.clanID = clanId
        req.limit = limit
        req.state = state
        return try await postProto(
            path: "/mezon.api.Mezon/ListRoles",
            message: req,
            auth: .bearer(token)
        )
    }

    func listEvents(clanId: Int64, token: String) async throws -> Mezon_Api_EventList {
        var req = Mezon_Api_ListEventsRequest()
        req.clanID = clanId
        return try await postProto(
            path: "/mezon.api.Mezon/ListEvents",
            message: req,
            auth: .bearer(token)
        )
    }

    func getRoleOfUserInTheClan(clanId: Int64, token: String) async throws -> Mezon_Api_RoleList {
        var req = Mezon_Api_ListPermissionOfUsersRequest()
        req.clanID = clanId
        return try await postProto(
            path: "/mezon.api.Mezon/GetRoleOfUserInTheClan",
            message: req,
            auth: .bearer(token)
        )
    }

    func getListPermission(token: String) async throws -> Mezon_Api_PermissionList {
        let empty = SwiftProtobuf.Google_Protobuf_Empty()
        return try await postProto(
            path: "/mezon.api.Mezon/GetListPermission",
            message: empty,
            auth: .bearer(token)
        )
    }

    func listChannelVoiceUsers(clanId: Int64, token: String) async throws -> Mezon_Api_VoiceChannelUserList {
        var req = Mezon_Api_ListChannelUsersRequest()
        req.clanID = clanId
        req.channelID = 0
        req.channelType = MezonConstants.ChannelType.mezonVoice.rawValue
        req.limit = 100
        req.state = 1
        return try await postProto(
            path: "/mezon.api.Mezon/ListChannelVoiceUsers",
            message: req,
            auth: .bearer(token)
        )
    }

    func generateMeetToken(channelId: Int64, roomName: String, token: String) async throws -> String {
        var req = Mezon_Api_GenerateMeetTokenRequest()
        req.channelID = channelId
        req.roomName = roomName
        let response: Mezon_Api_GenerateMeetTokenResponse = try await postProto(
            path: "/mezon.api.Mezon/GenerateMeetToken",
            message: req,
            auth: .bearer(token)
        )
        return response.token
    }

    func listStreamingChannelUsers(clanId: Int64, token: String) async throws -> Mezon_Api_StreamingChannelUserList {
        var req = Mezon_Api_ListChannelUsersRequest()
        req.clanID = clanId
        req.channelType = MezonConstants.ChannelType.streaming.rawValue
        req.limit = 100
        req.state = 1
        return try await postProto(
            path: "/mezon.api.Mezon/ListStreamingChannelUsers",
            message: req,
            auth: .bearer(token)
        )
    }


    func getNotificationClan(clanId: Int64, token: String) async throws -> Mezon_Api_NotificationUserChannel {
        var req = Mezon_Api_DefaultNotificationClan()
        req.clanID = clanId
        return try await postProto(
            path: "/mezon.api.Mezon/GetNotificationClan",
            message: req,
            auth: .bearer(token)
        )
    }

    func getChannelCategoryNotiSettingsList(clanId: Int64, token: String) async throws -> Mezon_Api_NotificationChannelCategorySettingList {
        var req = Mezon_Api_DefaultNotificationClan()
        req.clanID = clanId
        return try await postProto(
            path: "/mezon.api.Mezon/GetChannelCategoryNotiSettingsList",
            message: req,
            auth: .bearer(token)
        )
    }

    func registFcmDeviceToken(fcmToken: String, deviceId: String, platform: String = "ios", voipToken: String = "", authToken: String) async throws -> Mezon_Api_RegistFcmDeviceTokenResponse {
        var req = Mezon_Api_RegistFcmDeviceTokenRequest()
        req.token = fcmToken
        req.deviceID = deviceId
        req.platform = platform
        req.voipToken = voipToken
        return try await postProto(
            path: "/mezon.api.Mezon/RegistFCMDeviceToken",
            message: req,
            auth: .bearer(authToken)
        )
    }

    func uploadAttachmentFile(
        filename: String,
        filetype: String,
        size: Int,
        width: Int = 0,
        height: Int = 0,
        token: String
    ) async throws -> Mezon_Api_UploadAttachment {
        var req = Mezon_Api_UploadAttachmentRequest()
        req.filename = filename
        req.filetype = filetype
        req.size = Int32(size)
        req.width = Int32(width)
        req.height = Int32(height)
        return try await postProto(
            path: "/mezon.api.Mezon/UploadAttachmentFile",
            message: req,
            auth: .bearer(token)
        )
    }

    func uploadToMinIO(url: String, data: Data, contentType: String) async throws {
        guard let uploadURL = URL(string: url) else {
            throw MezonError.httpError(statusCode: 0, message: "Invalid MinIO URL")
        }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = data

        AppLogger.network.debug("→ PUT (minio) \(url)")
        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MezonError.invalidResponse }
        AppLogger.network.debug("← \(http.statusCode) (minio)")
        guard (200..<300).contains(http.statusCode) else {
            throw MezonError.httpError(statusCode: http.statusCode, message: "MinIO upload failed")
        }
    }

    func listChannelApps(clanId: Int64, token: String) async throws -> [Mezon_Api_ChannelAppResponse] {
        var req = Mezon_Api_ListChannelAppsRequest()
        req.clanID = clanId
        let response: Mezon_Api_ListChannelAppsResponse = try await postProto(
            path: "/mezon.api.Mezon/ListChannelApps",
            message: req,
            auth: .bearer(token)
        )
        return response.channelApps
    }

    func writeMessageReaction(
        clanId: Int64,
        channelId: Int64,
        mode: Int32,
        isPublic: Bool,
        messageId: Int64,
        emojiId: Int64,
        emoji: String,
        count: Int32,
        messageSenderId: Int64,
        actionDelete: Bool,
        topicId: Int64 = 0,
        emojiRecentId: Int64 = 0,
        senderName: String = "",
        token: String
    ) async throws -> Mezon_Api_MessageReaction {
        var req = Mezon_Api_MessageReaction()
        req.clanID = clanId
        req.channelID = channelId
        req.mode = mode
        req.isPublic = isPublic
        req.messageID = messageId
        req.emojiID = emojiId
        req.emoji = emoji
        req.count = count
        req.messageSenderID = messageSenderId
        req.action = actionDelete
        req.topicID = topicId
        req.emojiRecentID = emojiRecentId
        req.senderName = senderName
        return try await postProto(
            path: "/mezon.api.Mezon/ReactChannelMessage",
            message: req,
            auth: .bearer(token)
        )
    }

    func listUserClansByUserId(token: String) async throws -> Mezon_Api_AllUserClans {
        let empty = SwiftProtobuf.Google_Protobuf_Empty()
        return try await postProto(
            path: "/mezon.api.Mezon/ListUserClansByUserId",
            message: empty,
            auth: .bearer(token)
        )
    }

    func listChannelByUserId(token: String) async throws -> Mezon_Api_ChannelDescList {
        let empty = SwiftProtobuf.Google_Protobuf_Empty()
        return try await postProto(
            path: "/mezon.api.Mezon/ListChannelByUserId",
            message: empty,
            auth: .bearer(token)
        )
    }


    func getListEmojisByUserId(token: String) async throws -> Mezon_Api_EmojiListedResponse {
        let empty = SwiftProtobuf.Google_Protobuf_Empty()
        return try await postProto(
            path: "/mezon.api.Mezon/GetListEmojisByUserId",
            message: empty,
            auth: .bearer(token)
        )
    }

    func getListStickersByUserId(token: String) async throws -> Mezon_Api_StickerListedResponse {
        let empty = SwiftProtobuf.Google_Protobuf_Empty()
        return try await postProto(
            path: "/mezon.api.Mezon/GetListStickersByUserId",
            message: empty,
            auth: .bearer(token)
        )
    }

    func searchMessage(
        filters: [Mezon_Api_FilterParam] = [],
        from: Int32 = 1,
        size: Int32 = 25,
        sorts: [Mezon_Api_SortParam] = [],
        token: String
    ) async throws -> Mezon_Api_SearchMessageResponse {
        var req = Mezon_Api_SearchMessageRequest()
        req.filters = filters
        req.from = from
        req.size = size
        req.sorts = sorts
        return try await postProto(
            path: "/mezon.api.Mezon/SearchMessage",
            message: req,
            auth: .bearer(token)
        )
    }

    func createPinMessage(
        clanId: Int64,
        channelId: Int64,
        messageId: Int64,
        token: String
    ) async throws -> Mezon_Api_PinMessagesList {
        var req = Mezon_Api_PinMessageRequest()
        req.clanID = clanId
        req.channelID = channelId
        req.messageID = messageId
        return try await postProto(
            path: "/mezon.api.Mezon/CreatePinMessage",
            message: req,
            auth: .bearer(token)
        )
    }

    func listPinMessages(
        clanId: Int64,
        channelId: Int64,
        token: String
    ) async throws -> Mezon_Api_PinMessagesList {
        var req = Mezon_Api_PinMessageRequest()
        req.clanID = clanId
        req.channelID = channelId
        return try await postProto(
            path: "/mezon.api.Mezon/GetPinMessagesList",
            message: req,
            auth: .bearer(token)
        )
    }

    func listChannelAttachments(
        clanId: Int64,
        channelId: Int64,
        fileType: String = "all",
        limit: Int32 = 50,
        before: UInt32 = 0,
        after: UInt32 = 0,
        token: String
    ) async throws -> Mezon_Api_ChannelAttachmentList {
        var req = Mezon_Api_ListChannelAttachmentRequest()
        req.clanID = clanId
        req.channelID = channelId
        req.fileType = fileType
        req.limit = limit
        req.before = before
        req.after = after
        return try await postProto(
            path: "/mezon.api.Mezon/ListChannelAttachment",
            message: req,
            auth: .bearer(token)
        )
    }

    func listChannelCanvases(
        clanId: Int64,
        channelId: Int64,
        limit: Int32 = 50,
        page: Int32 = 0,
        token: String
    ) async throws -> Mezon_Api_ChannelCanvasListResponse {
        var req = Mezon_Api_ChannelCanvasListRequest()
        req.clanID = clanId
        req.channelID = channelId
        req.limit = limit
        req.page = page
        return try await postProto(
            path: "/mezon.api.Mezon/GetChannelCanvasList",
            message: req,
            auth: .bearer(token)
        )
    }

    func get<T: Decodable>(path: String, queryItems: [URLQueryItem] = [], token: String) async throws -> T {
        let req = try buildRequest(method: "GET", path: path, queryItems: queryItems, body: Optional<EmptyBody>.none, auth: .bearer(token))
        return try await execute(req, allowBearerRetry: true)
    }

    func getProto<Response: SwiftProtobuf.Message>(path: String, token: String) async throws -> Response {
        let empty = SwiftProtobuf.Google_Protobuf_Empty()
        return try await postProto(path: path, message: empty, auth: .bearer(token))
    }

    func post<Body: Encodable, Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Body,
        auth: AuthMethod
    ) async throws -> Response {
        let req = try buildRequest(method: "POST", path: path, queryItems: queryItems, body: body, auth: auth)
        return try await execute(req, allowBearerRetry: true)
    }

    func postProto<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
        path: String,
        message: Request,
        auth: AuthMethod,
        allowBearerRetry: Bool = true
    ) async throws -> Response {
        let url = protoBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/proto", forHTTPHeaderField: "Content-Type")
        request.setValue("application/proto", forHTTPHeaderField: "Accept")
        switch auth {
        case .serverKey:
            request.setValue(MezonConfig.basicAuthHeader, forHTTPHeaderField: "Authorization")
        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try message.serializedData()

        AppLogger.network.debug("→ POST (proto) \(url.absoluteString)")
        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw MezonError.invalidResponse }
        AppLogger.network.debug("← \(http.statusCode) \(url.path) (\(data.count) bytes)")

        if (200..<300).contains(http.statusCode) {
            return try Response(serializedBytes: data)
        }

        if allowBearerRetry,
            http.statusCode == 401 || http.statusCode == 403,
            case .bearer = auth,
            let recovery = bearerUnauthorizedRecovery,
           let newToken = try await recovery() {
            AppLogger.network.info("[HTTP] \(http.statusCode) on proto \(url.path); retrying with refreshed session token")
            return try await postProto(
                path: path,
                message: message,
                auth: .bearer(newToken),
                allowBearerRetry: false
            )
        }

        let msg = (try? JSONDecoder().decode(APIError.self, from: data))?.message
            ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
        throw MezonError.httpError(statusCode: http.statusCode, message: msg)
    }

    func postProtoIgnoringBody<Request: SwiftProtobuf.Message>(
        path: String,
        message: Request,
        auth: AuthMethod,
        allowBearerRetry: Bool = true
    ) async throws {
        let _: SwiftProtobuf.Google_Protobuf_Empty = try await postProto(
            path: path,
            message: message,
            auth: auth,
            allowBearerRetry: allowBearerRetry
        )
    }

    enum AuthMethod {
        case serverKey
        case bearer(String)
    }

    private func buildRequest<Body: Encodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        body: Body?,
        auth: AuthMethod
    ) throws -> URLRequest {
        var components = URLComponents(url: authBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty { components.queryItems = queryItems }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        switch auth {
        case .serverKey:
            request.setValue(MezonConfig.basicAuthHeader, forHTTPHeaderField: "Authorization")
        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    private func execute<T: Decodable>(_ request: URLRequest, allowBearerRetry: Bool = true) async throws -> T {
        AppLogger.network.debug("→ \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "")")
        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw MezonError.invalidResponse
        }
        AppLogger.network.debug("← \(http.statusCode) \(request.url?.path ?? "")")

        if (200..<300).contains(http.statusCode) {
            if T.self == EmptyResponse.self { return EmptyResponse() as! T }
            return try JSONDecoder().decode(T.self, from: data)
        }

        if allowBearerRetry,
            http.statusCode == 401 || http.statusCode == 403,
            request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true,
            let recovery = bearerUnauthorizedRecovery,
           let newToken = try await recovery() {
            AppLogger.network.info("[HTTP] \(http.statusCode) on \(request.url?.path ?? ""); retrying JSON request with refreshed token")
            var retry = request
            retry.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            return try await execute(retry, allowBearerRetry: false)
        }

        let msg = (try? JSONDecoder().decode(APIError.self, from: data))?.message
            ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
        throw MezonError.httpError(statusCode: http.statusCode, message: msg)
    }
}

private struct EmptyBody: Encodable {}
struct EmptyResponse: Decodable {}
struct APIError: Decodable { let message: String?; let code: Int? }

enum MezonError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case socketError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:              return "Invalid server response."
        case .httpError(let c, let msg):    return "HTTP \(c): \(msg)"
        case .socketError(let msg):         return "Socket: \(msg)"
        }
    }
}
