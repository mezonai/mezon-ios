import Foundation
import SwiftProtobuf

final class MezonHTTPClient {

    static let shared = MezonHTTPClient()

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

    func getAccount(token: String) async throws -> Mezon_Api_Account {
        let empty = SwiftProtobuf.Google_Protobuf_Empty()
        return try await postProto(
            path: "/mezon.api.Mezon/GetAccount",
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
        struct Body: Encodable {
            let token: String
            let refresh_token: String
            let device_id: String
            let platform: String
        }
        let _: EmptyResponse = try await post(
            path: "/v2/session/logout",
            body: Body(token: session.token, refresh_token: session.refreshToken,
                device_id: deviceId, platform: platform),
            auth: .bearer(session.token)
        )
    }

    func listChannelDescs(clanId: Int64, token: String) async throws -> [Mezon_Api_ChannelDescription] {
        var req = Mezon_Api_ListChannelDescsRequest()
        req.clanID      = clanId
        req.limit       = 500
        req.state       = 1
        req.page        = 0
        req.channelType = 0
        req.isMobile    = true
        let response: Mezon_Api_ChannelDescList = try await postProto(
            path: "/mezon.api.Mezon/ListChannelDescs",
            message: req,
            auth: .bearer(token)
        )
        return response.channeldesc
    }

    func listDirectMessageChannels(token: String) async throws -> [Mezon_Api_ChannelDescription] {
        var req = Mezon_Api_ListChannelDescsRequest()
        req.clanID      = 0
        req.limit       = 500
        req.state       = 1
        req.page        = 1
        req.channelType = 3
        req.isMobile    = true
        let response: Mezon_Api_ChannelDescList = try await postProto(
            path: "/mezon.api.Mezon/ListChannelDescs",
            message: req,
            auth: .bearer(token)
        )
        return response.channeldesc
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

    func listNotifications(clanID: Int64, category: Int32, token: String, notificationID: Int64) async throws
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
        var req = Mezon_Api_ListClanUsersRequest()
        req.clanID = clanId
        return try await postProto(
            path: "/mezon.api.Mezon/ListChannelVoiceUsers",
            message: req,
            auth: .bearer(token)
        )
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

    func listClanBadgeCount(clanId: Int64, token: String) async throws -> Mezon_Api_ListClanBadgeCountResponse {
        var req = Mezon_Api_ListClanBadgeCountRequest()
        req.clanID = clanId
        return try await postProto(
            path: "/mezon.api.Mezon/ListClanBadgeCount",
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

    func get<T: Decodable>(path: String, queryItems: [URLQueryItem] = [], token: String) async throws -> T {
        let req = try buildRequest(method: "GET", path: path, queryItems: queryItems, body: Optional<EmptyBody>.none, auth: .bearer(token))
        return try await execute(req)
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
        return try await execute(req)
    }

    func postProto<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
        path: String,
        message: Request,
        auth: AuthMethod
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

        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(APIError.self, from: data))?.message
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw MezonError.httpError(statusCode: http.statusCode, message: msg)
        }

        return try Response(serializedBytes: data)
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

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        AppLogger.network.debug("→ \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "")")
        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw MezonError.invalidResponse
        }
        AppLogger.network.debug("← \(http.statusCode) \(request.url?.path ?? "")")

        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(APIError.self, from: data))?.message
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw MezonError.httpError(statusCode: http.statusCode, message: msg)
        }

        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        return try JSONDecoder().decode(T.self, from: data)
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
