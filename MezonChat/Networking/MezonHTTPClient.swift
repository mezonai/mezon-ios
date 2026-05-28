import Foundation
import SwiftProtobuf
import UIKit
import Network

final class MezonHTTPClient {

    static let shared = MezonHTTPClient()
    var bearerUnauthorizedRecovery: (() async throws -> String?)?

    private let urlSession: URLSession
    private let uploadURLSession: URLSession
    private var authBaseURL: URL = MezonConfig.authBaseURL
    private var protoBaseURL: URL = MezonConfig.protoBaseURL

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        var headers: [AnyHashable: Any] = config.httpAdditionalHeaders ?? [:]
        headers["User-Agent"] = Self.userAgent
        headers["Accept-Encoding"] = "gzip, deflate"
        config.httpAdditionalHeaders = headers
        if #available(iOS 17.0, *),
           config.responds(to: Selector(("setAssumesHTTP3Capable:"))) {
            config.setValue(true, forKey: "assumesHTTP3Capable")
        }
        urlSession = URLSession(configuration: config)

        let uploadConfig = URLSessionConfiguration.default
        uploadConfig.timeoutIntervalForRequest = 120
        uploadConfig.timeoutIntervalForResource = 600
        uploadConfig.waitsForConnectivity = true
        uploadConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        uploadConfig.urlCache = nil
        uploadConfig.httpShouldSetCookies = false
        uploadConfig.httpCookieAcceptPolicy = .never
        uploadURLSession = URLSession(configuration: uploadConfig)
    }

    private static let userAgent: String = {
        let info = Bundle.main.infoDictionary
        let appName = (info?["CFBundleName"] as? String) ?? "MezonChat"
        let appVersion = (info?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let build = (info?["CFBundleVersion"] as? String) ?? "0"
        let osVersion = UIDevice.current.systemVersion
        let model = UIDevice.current.model
        return "\(appName)/\(appVersion).\(build) (iOS \(osVersion); \(model))"
    }()

    private func httpData(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if #available(iOS 15.0, *) {
            return try await urlSession.data(for: request)
        } else {
            return try await legacyData(for: request)
        }
    }

    private func legacyData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            let task = urlSession.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let response else {
                    continuation.resume(throwing: MezonError.invalidResponse)
                    return
                }
                continuation.resume(returning: (data ?? Data(), response))
            }
            task.resume()
        }
    }

    func updateBaseURL(from session: MezonSession) {
        guard let apiURL = session.apiURL else { return }
        let cleaned = stripDefaultPort(apiURL)
        guard let url = URL(string: cleaned) else { return }
        protoBaseURL = url
    }

    func resetProtoBaseURLToDefault() {
        protoBaseURL = MezonConfig.protoBaseURL
    }

    private static let transientRetryDelaysNanoseconds: [UInt64] = [
        350_000_000,
        1_000_000_000
    ]

    private func retryingTransientRequest<Response>(
        operationName: String,
        operation: () async throws -> Response
    ) async throws -> Response {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch {
                if error is CancellationError || Task.isCancelled {
                    throw error
                }
                guard attempt <= Self.transientRetryDelaysNanoseconds.count,
                      Self.isRetriableTransientError(error) else {
                    throw error
                }

                let delay = Self.transientRetryDelaysNanoseconds[attempt - 1]
                MezonRPCLog.response("\(operationName) transient fail attempt=\(attempt) retryDelayMs=\(delay / 1_000_000) error=\(error.localizedDescription)")
                attempt += 1
                try await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private static func isRetriableTransientError(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }

        if let mezonError = error as? MezonError {
            switch mezonError {
            case .invalidResponse, .socketError:
                return true
            case .httpError(let statusCode, _):
                return statusCode == 0
                    || statusCode == 408
                    || statusCode == 425
                    || statusCode == 429
                    || (500...599).contains(statusCode)
            }
        }

        if let urlError = error as? URLError {
            return isRetriableURLErrorCode(urlError.code)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return isRetriableURLErrorCode(URLError.Code(rawValue: nsError.code))
        }

        return false
    }

    private static func isRetriableURLErrorCode(_ code: URLError.Code) -> Bool {
        switch code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .secureConnectionFailed,
             .cannotLoadFromNetwork,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .badServerResponse,
             .cannotParseResponse:
            return true
        default:
            return false
        }
    }

    func updateUsername(username: String, token: String) async throws -> Mezon_Api_Session {
        var req = Mezon_Api_UpdateUsernameRequest()
        req.username = username
        return try await postProto(
            path: "/mezon.api.Mezon/UpdateUsername",
            message: req,
            auth: .bearer(token)
        )
    }

    func leaveThread(clanId: Int64, channelId: Int64, token: String) async throws {
        var req = Mezon_Api_LeaveThreadRequest()
        req.clanID = clanId
        req.channelID = channelId
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/LeaveThread",
            message: req,
            auth: .bearer(token)
        )
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

    func linkEmail(email: String, token: String) async throws -> OTPRequestResponse {
        var req = Mezon_Api_AccountEmail()
        req.email = email
        req.vars = ["m": "true"]
        let response: Mezon_Api_LinkAccountConfirmRequest = try await postProto(
            path: "/mezon.api.Mezon/LinkEmail",
            message: req,
            auth: .bearer(token)
        )
        return OTPRequestResponse(reqId: response.reqID.isEmpty ? nil : response.reqID)
    }

    func confirmLinkEmailOTP(reqId: String, otpCode: String, token: String) async throws {
        var req = Mezon_Api_LinkAccountConfirmRequest()
        req.reqID = reqId
        req.otpCode = otpCode
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/ConfirmLinkMezonOTP",
            message: req,
            auth: .bearer(token)
        )
    }

    func linkSMS(phoneNumber: String, token: String) async throws -> OTPRequestResponse {
        var req = Mezon_Api_AccountMezon()
        req.phoneNumber = phoneNumber
        req.vars = ["m": "true"]
        let response: Mezon_Api_LinkAccountConfirmRequest = try await postProto(
            path: "/mezon.api.Mezon/LinkSMS",
            message: req,
            auth: .bearer(token)
        )
        return OTPRequestResponse(reqId: response.reqID.isEmpty ? nil : response.reqID)
    }

    func confirmLinkPhoneOTP(reqId: String, otpCode: String, token: String) async throws {
        var req = Mezon_Api_LinkAccountConfirmRequest()
        req.reqID = reqId
        req.otpCode = otpCode
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/ConfirmLinkMezonOTP",
            message: req,
            auth: .bearer(token)
        )
    }

    @discardableResult
    func confirmLogin(loginId: String, token: String) async throws -> MezonSession? {
        struct Body: Encodable {
            let login_id: String
        }
        let request = try buildRequest(
            method: "POST",
            path: "/v2/account/authenticate/confirmlogin",
            queryItems: [],
            body: Body(login_id: loginId),
            auth: .bearer(token)
        )
        let (data, response) = try await httpData(request)
        guard let http = response as? HTTPURLResponse else { throw MezonError.invalidResponse }
        if (200..<300).contains(http.statusCode) {
            if data.isEmpty { return nil }
            return try? JSONDecoder().decode(MezonSession.self, from: data)
        }
        let msg = (try? JSONDecoder().decode(APIError.self, from: data))?.message
            ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
        throw MezonError.httpError(statusCode: http.statusCode, message: msg)
    }

    func getAccount(token: String) async throws -> Mezon_Api_Account {
        let empty = SwiftProtobuf.Google_Protobuf_Empty()
        return try await postProto(
            path: "/mezon.api.Mezon/GetAccount",
            message: empty,
            auth: .bearer(token)
        )
    }

    func deleteAccount(token: String) async throws {
        let empty = SwiftProtobuf.Google_Protobuf_Empty()
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/DeleteAccount",
            message: empty,
            auth: .bearer(token)
        )
    }

    func registrationPassword(email: String, password: String, oldPassword: String, token: String) async throws {
        var req = Mezon_Api_RegistrationEmailRequest()
        req.email = email
        req.password = password
        req.oldPassword = oldPassword
        let _: Mezon_Api_Session = try await postProto(
            path: "/mezon.api.Mezon/RegistrationEmail",
            message: req,
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

    func createClanDesc(name: String, logo: String = "", banner: String = "", token: String) async throws -> Mezon_Api_ClanDesc {
        var req = Mezon_Api_CreateClanDescRequest()
        req.clanName = name
        req.logo = logo
        req.banner = banner
        return try await postProto(
            path: "/mezon.api.Mezon/CreateClanDesc",
            message: req,
            auth: .bearer(token)
        )
    }

    func linkInviteUser(
        clanId: Int64,
        channelId: Int64,
        expiryTime: Int32 = 10,
        token: String
    ) async throws -> Mezon_Api_LinkInviteUser {
        var req = Mezon_Api_LinkInviteUserRequest()
        req.clanID = clanId
        req.channelID = channelId
        req.expiryTime = expiryTime
        return try await postProto(
            path: "/mezon.api.Mezon/CreateLinkInviteUser",
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
        var req = Mezon_Api_CategoryDesc()
        req.clanID = clanId
        let response: Mezon_Api_CategoryDescList = try await postProto(
            path: "/mezon.api.Mezon/ListCategoryDescs",
            message: req,
            auth: .bearer(token)
        )
        return response.categorydesc
    }

    func createCategoryDesc(clanId: Int64, categoryName: String, token: String) async throws -> Mezon_Api_CategoryDesc {
        var req = Mezon_Api_CreateCategoryDescRequest()
        req.clanID = clanId
        req.categoryName = categoryName
        return try await postProto(
            path: "/mezon.api.Mezon/CreateCategoryDesc",
            message: req,
            auth: .bearer(token)
        )
    }

    func createClanChannelDesc(
        clanId: Int64,
        categoryId: Int64,
        channelLabel: String,
        type: Int32,
        channelPrivate: Int32,
        token: String
    ) async throws -> Mezon_Api_ChannelDescription {
        var req = Mezon_Api_CreateChannelDescRequest()
        req.clanID = clanId
        req.parentID = 0
        req.categoryID = categoryId
        req.type = type
        req.channelLabel = channelLabel
        req.channelPrivate = channelPrivate
        return try await postProto(
            path: "/mezon.api.Mezon/CreateChannelDesc",
            message: req,
            auth: .bearer(token)
        )
    }

    func createThreadChannelDesc(
        clanId: Int64,
        parentChannelId: Int64,
        categoryId: Int64,
        channelLabel: String,
        channelPrivate: Int32,
        token: String
    ) async throws -> Mezon_Api_ChannelDescription {
        var req = Mezon_Api_CreateChannelDescRequest()
        req.clanID = clanId
        req.parentID = parentChannelId
        req.categoryID = categoryId
        req.channelLabel = channelLabel
        req.type = MezonConstants.ChannelType.thread.rawValue
        req.channelPrivate = channelPrivate
        return try await postProto(
            path: "/mezon.api.Mezon/CreateChannelDesc",
            message: req,
            auth: .bearer(token)
        )
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

    func listGroupMessageChannels(token: String) async throws -> [Mezon_Api_ChannelDescription] {
        var req = Mezon_Api_ListChannelDescsRequest()
        req.clanID      = 0
        req.limit       = 500
        req.state       = 1
        req.page        = 0
        req.channelType = 2
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
        limit: Int32 = 100,
        token: String
    ) async throws -> Mezon_Api_ChannelDescList {
        var req = Mezon_Api_ListThreadRequest()
        req.limit = limit
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
        let primary: Mezon_Api_ListChannelBadgeCountResponse = try await postProto(
            path: "/mezon.api.Mezon/ListChannelBadgeCount",
            message: req,
            auth: .bearer(token)
        )
        if !primary.channeldesc.isEmpty {
            return primary
        }
        return try await postProtoHTTP(
            path: "/mezon.api.Mezon/ListChannelBadgeCount",
            message: req,
            auth: .bearer(token)
        )
    }

    func listClanBadgeCount(token: String) async throws -> Mezon_Api_ListClanBadgeCountResponse {
        let empty = SwiftProtobuf.Google_Protobuf_Empty()
        return try await postProto(
            path: "/mezon.api.Mezon/ListClanBadgeCount",
            message: empty,
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

    func createGroupDirectMessage(userIds: [Int64], token: String) async throws -> Mezon_Api_ChannelDescription {
        var req = Mezon_Api_CreateChannelDescRequest()
        req.clanID = 0
        req.type = MezonConstants.ChannelType.group.rawValue
        req.channelPrivate = 1
        req.userIds = userIds
        return try await postProto(
            path: "/mezon.api.Mezon/CreateChannelDesc",
            message: req,
            auth: .bearer(token)
        )
    }

    func listUserActivity(token: String) async throws -> Mezon_Api_ListUserActivity {
        let empty = SwiftProtobuf.Google_Protobuf_Empty()
        return try await postProto(
            path: "/mezon.api.Mezon/ListActivity",
            message: empty,
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

    private struct ClanDiscoverJSONBody: Encodable {
        let page_number: Int
        let item_per_page: Int
    }

    func listClanDiscover(pageNumber: Int32, itemPerPage: Int32, bearerToken: String?) async throws -> Mezon_Api_ListClanDiscover {
        let body = ClanDiscoverJSONBody(page_number: Int(pageNumber), item_per_page: Int(itemPerPage))
        let encoded = try JSONEncoder().encode(body)
        var url = authBaseURL
        for segment in ["v2", "clan", "discover"] {
            url = url.appendingPathComponent(segment)
        }

        func makeRequest(authorization: String) -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = encoded
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/x-protobuf", forHTTPHeaderField: "Accept")
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
            return request
        }

        func decodeDiscoverResponse(_ data: Data) throws -> Mezon_Api_ListClanDiscover {
            if data.isEmpty {
                return Mezon_Api_ListClanDiscover()
            }
            do {
                return try Mezon_Api_ListClanDiscover(serializedBytes: data)
            } catch {
                return try Mezon_Api_ListClanDiscover(jsonUTF8Data: data)
            }
        }

        func run(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let (data, response) = try await httpData(request)
            guard let http = response as? HTTPURLResponse else { throw MezonError.invalidResponse }
            return (data, http)
        }

        var request = makeRequest(authorization: MezonConfig.basicAuthHeader)
        var (data, http) = try await run(request)
        if [401, 403].contains(http.statusCode), let t = bearerToken, !t.isEmpty {
            request = makeRequest(authorization: "Bearer \(t)")
            (data, http) = try await run(request)
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(APIError.self, from: data))?.message
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw MezonError.httpError(statusCode: http.statusCode, message: msg)
        }
        return try decodeDiscoverResponse(data)
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

    func createSdTopic(clanID: Int64, channelID: Int64, messageID: Int64, token: String) async throws -> Mezon_Api_SdTopic {
        var req = Mezon_Api_SdTopicRequest()
        req.clanID = clanID
        req.channelID = channelID
        req.messageID = messageID
        return try await postProto(
            path: "/mezon.api.Mezon/CreateSdTopic",
            message: req,
            auth: .bearer(token)
        )
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

    func updateAccount(
        displayName: String? = nil,
        avatarUrl: String? = nil,
        aboutMe: String? = nil,
        logo: String? = nil,
        token: String
    ) async throws -> Mezon_Api_Account {
        var req = Mezon_Api_UpdateAccountRequest()
        if let displayName {
            var v = SwiftProtobuf.Google_Protobuf_StringValue()
            v.value = displayName
            req.displayName = v
        }
        if let avatarUrl {
            var v = SwiftProtobuf.Google_Protobuf_StringValue()
            v.value = avatarUrl
            req.avatarURL = v
        }
        if let aboutMe {
            var v = SwiftProtobuf.Google_Protobuf_StringValue()
            v.value = aboutMe
            req.aboutMe = v
        }
        if let logo {
            var v = SwiftProtobuf.Google_Protobuf_StringValue()
            v.value = logo
            req.logo = v
        }
        return try await postProto(
            path: "/mezon.api.Mezon/UpdateAccount",
            message: req,
            auth: .bearer(token)
        )
    }

    func updateClanProfile(
        clanId: Int64,
        nickName: String? = nil,
        avatar: String? = nil,
        token: String
    ) async throws -> SwiftProtobuf.Google_Protobuf_Empty {
        var req = Mezon_Api_UpdateClanProfileRequest()
        req.clanID = clanId
        if let nickName {
            var v = SwiftProtobuf.Google_Protobuf_StringValue()
            v.value = nickName
            req.nickName = v
        }
        if let avatar {
            var v = SwiftProtobuf.Google_Protobuf_StringValue()
            v.value = avatar
            req.avatar = v
        }
        return try await postProto(
            path: "/mezon.api.Mezon/UpdateUserProfileByClan",
            message: req,
            auth: .bearer(token)
        )
    }

    func checkDuplicateName(
        name: String,
        type: Int32,
        conditionId: Int64,
        token: String
    ) async throws -> Bool {
        var req = Mezon_Api_CheckDuplicateNameRequest()
        req.name = name
        req.type = type
        req.conditionID = conditionId
        let response: Mezon_Api_CheckDuplicateNameResponse = try await postProto(
            path: "/mezon.api.Mezon/CheckDuplicateName",
            message: req,
            auth: .bearer(token)
        )
        return response.isDuplicate
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
        token: String,
        preferHTTPFirst: Bool = false
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
            auth: .bearer(token),
            preferHTTPFirst: preferHTTPFirst
        )
    }

    func messageButtonClick(
        messageId: Int64,
        channelId: Int64,
        buttonId: String,
        senderId: Int64,
        userId: Int64,
        extraData: String,
        token: String
    ) async throws {
        var req = Mezon_Realtime_MessageButtonClicked()
        req.messageID = messageId
        req.channelID = channelId
        req.buttonID = buttonId
        req.senderID = senderId
        req.userID = userId
        req.extraData = extraData
        
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/MessageButtonClick",
            message: req,
            auth: .bearer(token)
        )
    }

    func updateChannelMessage(
        clanId: Int64,
        channelId: Int64,
        mode: Int32,
        isPublic: Bool,
        messageId: Int64,
        content: String,
        mentions: [Mezon_Api_MessageMention] = [],
        attachments: [Mezon_Api_MessageAttachment] = [],
        hideEditted: Bool = false,
        topicId: Int64 = 0,
        isUpdateMsgTopic: Bool = false,
        token: String
    ) async throws -> Mezon_Realtime_ChannelMessageAck {
        var req = Mezon_Realtime_ChannelMessageUpdate()
        req.clanID = clanId
        req.channelID = channelId
        req.messageID = messageId
        req.content = content
        req.mentions = mentions
        req.attachments = attachments
        req.mode = mode
        req.isPublic = isPublic
        req.hideEditted = hideEditted
        req.topicID = topicId
        req.isUpdateMsgTopic = isUpdateMsgTopic

        let ack: Mezon_Realtime_ChannelMessageAck = try await postProto(
            path: "/mezon.api.Mezon/UpdateChannelMessage",
            message: req,
            auth: .bearer(token)
        )
        return ack
    }

    func listChannelMessages(
        clanId: Int64,
        channelId: Int64,
        messageId: Int64 = 0,
        direction: Int32 = 2,
        limit: Int32 = 50,
        topicId: Int64 = 0,
        token: String,
        preferHTTPFirst: Bool = true
    ) async throws -> Mezon_Api_ChannelMessageList {
        try await retryingTransientRequest(
            operationName: "ListChannelMessages clanId=\(clanId) channelId=\(channelId) messageId=\(messageId) direction=\(direction)"
        ) {
            var req = Mezon_Api_ListChannelMessagesRequest()
            req.clanID = clanId
            req.channelID = channelId
            req.messageID = messageId
            req.direction = direction
            req.limit = limit
            req.topicID = topicId
            return try await self.postProto(
                path: "/mezon.api.Mezon/ListChannelMessages",
                message: req,
                auth: .bearer(token),
                preferHTTPFirst: preferHTTPFirst
            )
        }
    }

    func updateChannelDesc(
        clanId: Int64,
        channelId: Int64,
        channelLabel: String? = nil,
        channelAvatar: String? = nil,
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
        if let channelAvatar = channelAvatar {
            var avatarValue = SwiftProtobuf.Google_Protobuf_StringValue()
            avatarValue.value = channelAvatar
            req.channelAvatar = avatarValue
        }
        if let topic = topic, !topic.isEmpty {
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

    func listChannelUsersUC(channelId: Int64, limit: Int32 = 500, token: String) async throws -> Mezon_Api_AllUsersAddChannelResponse {
        var req = Mezon_Api_AllUsersAddChannelRequest()
        req.channelID = channelId
        req.limit = limit
        return try await postProto(
            path: "/mezon.api.Mezon/ListChannelUsersUC",
            message: req,
            auth: .bearer(token)
        )
    }

    func addChannelUsers(channelId: Int64, userIds: [Int64], token: String) async throws {
        var req = Mezon_Api_AddChannelUsersRequest()
        req.channelID = channelId
        req.userIds = userIds
        let _: SwiftProtobuf.Google_Protobuf_Empty = try await postProto(
            path: "/mezon.api.Mezon/AddChannelUsers",
            message: req,
            auth: .bearer(token)
        )
    }

    func removeChannelUsers(channelId: Int64, userIds: [Int64], token: String) async throws {
        var req = Mezon_Api_RemoveChannelUsersRequest()
        req.channelID = channelId
        req.userIds = userIds
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/RemoveChannelUsers",
            message: req,
            auth: .bearer(token)
        )
    }

    func addRoleChannelDesc(channelId: Int64, roleIds: [Int64], token: String) async throws {
        var req = Mezon_Api_AddRoleChannelDescRequest()
        req.channelID = channelId
        req.roleIds = roleIds
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/AddRolesChannelDesc",
            message: req,
            auth: .bearer(token)
        )
    }

    func deleteRoleChannelDesc(roleId: Int64, clanId: Int64, channelId: Int64, token: String) async throws {
        var req = Mezon_Api_DeleteRoleRequest()
        req.roleID = roleId
        req.clanID = clanId
        req.channelID = channelId
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/DeleteRoleChannelDesc",
            message: req,
            auth: .bearer(token)
        )
    }

    func changeChannelPrivate(
        clanId: Int64,
        channelId: Int64,
        channelPrivate: Int32,
        userIds: [Int64] = [],
        roleIds: [Int64] = [],
        token: String
    ) async throws {
        var req = Mezon_Api_ChangeChannelPrivateRequest()
        req.clanID = clanId
        req.channelID = channelId
        req.channelPrivate = channelPrivate
        req.userIds = userIds
        req.roleIds = roleIds
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/UpdateChannelPrivate",
            message: req,
            auth: .bearer(token)
        )
    }

    func getPermissionByRoleIdChannelId(
        roleId: Int64,
        channelId: Int64,
        userId: Int64,
        token: String
    ) async throws -> Mezon_Api_PermissionRoleChannelListEventResponse {
        var req = Mezon_Api_PermissionRoleChannelListEventRequest()
        req.roleID = roleId
        req.channelID = channelId
        req.userID = userId
        return try await postProto(
            path: "/mezon.api.Mezon/GetPermissionByRoleIdChannelId",
            message: req,
            auth: .bearer(token)
        )
    }

    func setRoleChannelPermission(
        roleId: Int64,
        channelId: Int64,
        userId: Int64,
        maxPermissionId: Int64,
        permissions: [Mezon_Api_PermissionUpdate],
        roleLabel: String = "",
        token: String
    ) async throws {
        var req = Mezon_Api_UpdateRoleChannelRequest()
        req.roleID = roleId
        req.channelID = channelId
        req.userID = userId
        req.maxPermissionID = maxPermissionId
        req.permissionUpdate = permissions
        req.roleLabel = roleLabel
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/SetRoleChannelPermission",
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

    func createRole(request: Mezon_Api_CreateRoleRequest, token: String) async throws -> Mezon_Api_Role {
        return try await postProto(
            path: "/mezon.api.Mezon/CreateRole",
            message: request,
            auth: .bearer(token)
        )
    }

    func updateRole(request: Mezon_Api_UpdateRoleRequest, token: String) async throws {
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/UpdateRole",
            message: request,
            auth: .bearer(token)
        )
    }

    func deleteRole(roleId: Int64, clanId: Int64, channelId: Int64 = 0, roleLabel: String = "", token: String) async throws {
        var req = Mezon_Api_DeleteRoleRequest()
        req.roleID = roleId
        req.clanID = clanId
        req.channelID = channelId
        req.roleLabel = roleLabel
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/DeleteRole",
            message: req,
            auth: .bearer(token)
        )
    }

    func listRoleUsers(roleId: Int64, limit: Int32 = 100, cursor: String = "", token: String) async throws -> Mezon_Api_RoleUserList {
        var req = Mezon_Api_ListRoleUsersRequest()
        req.roleID = roleId
        req.limit = limit
        req.cursor = cursor
        return try await postProto(
            path: "/mezon.api.Mezon/ListRoleUsers",
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

    func muteMezonMeetParticipant(clanId: Int64, channelId: Int64, roomName: String, username: String, token: String) async throws {
        var req = Mezon_Api_MeetParticipantRequest()
        req.clanID = clanId
        req.channelID = channelId
        req.roomName = roomName
        req.username = username
        let _: SwiftProtobuf.Google_Protobuf_Empty = try await postProto(
            path: "/mezon.api.Mezon/MuteParticipantMezonMeet",
            message: req,
            auth: .bearer(token)
        )
    }

    func removeMezonMeetParticipant(clanId: Int64, channelId: Int64, roomName: String, username: String, token: String) async throws {
        var req = Mezon_Api_MeetParticipantRequest()
        req.clanID = clanId
        req.channelID = channelId
        req.roomName = roomName
        req.username = username
        let _: SwiftProtobuf.Google_Protobuf_Empty = try await postProto(
            path: "/mezon.api.Mezon/RemoveParticipantMezonMeet",
            message: req,
            auth: .bearer(token)
        )
    }

    func addAgentToVoiceChannel(channelId: Int64, roomName: String, token: String) async throws {
        var req = Mezon_Api_UpdateAIAgentRequest()
        req.channelID = channelId
        req.roomName = roomName
        let _: SwiftProtobuf.Google_Protobuf_Empty = try await postProto(
            path: "/mezon.api.Mezon/AddAgentToChannel",
            message: req,
            auth: .bearer(token)
        )
    }

    func disconnectAgentFromVoiceChannel(channelId: Int64, roomName: String, token: String) async throws {
        var req = Mezon_Api_UpdateAIAgentRequest()
        req.channelID = channelId
        req.roomName = roomName
        let _: SwiftProtobuf.Google_Protobuf_Empty = try await postProto(
            path: "/mezon.api.Mezon/DisconnectAgent",
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
        token: String,
        preferHTTPFirst: Bool = false
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
            auth: .bearer(token),
            preferHTTPFirst: preferHTTPFirst
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

        let (_, response) = try await uploadHTTPData(request)
        guard let http = response as? HTTPURLResponse else { throw MezonError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw MezonError.httpError(statusCode: http.statusCode, message: "MinIO upload failed")
        }
    }

    func uploadToMinIO(url: String, fileURL: URL, contentType: String) async throws {
        guard let uploadURL = URL(string: url) else {
            throw MezonError.httpError(statusCode: 0, message: "Invalid MinIO URL")
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let fileSize = attrs[.size] as? NSNumber else {
            throw MezonError.httpError(statusCode: 0, message: "Cannot read file size")
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(fileSize.intValue)", forHTTPHeaderField: "Content-Length")

        let (_, response) = try await uploadFromFile(request, fileURL: fileURL)
        guard let http = response as? HTTPURLResponse else { throw MezonError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw MezonError.httpError(statusCode: http.statusCode, message: "MinIO upload failed")
        }
    }

    private func uploadHTTPData(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if #available(iOS 15.0, *) {
            return try await uploadURLSession.data(for: request)
        }
        return try await legacyUploadData(for: request)
    }

    private func uploadFromFile(_ request: URLRequest, fileURL: URL) async throws -> (Data, URLResponse) {
        if #available(iOS 15.0, *) {
            return try await uploadURLSession.upload(for: request, fromFile: fileURL)
        }
        return try await legacyUploadFromFile(request, fileURL: fileURL)
    }

    private func legacyUploadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            let task = uploadURLSession.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let response else {
                    continuation.resume(throwing: MezonError.invalidResponse)
                    return
                }
                continuation.resume(returning: (data ?? Data(), response))
            }
            task.resume()
        }
    }

    private func legacyUploadFromFile(_ request: URLRequest, fileURL: URL) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            let task = uploadURLSession.uploadTask(with: request, fromFile: fileURL) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let response else {
                    continuation.resume(throwing: MezonError.invalidResponse)
                    return
                }
                continuation.resume(returning: (data ?? Data(), response))
            }
            task.resume()
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

    func generateChannelAppHash(appId: Int64, token: String) async throws -> String {
        var req = Mezon_Api_GenerateHashChannelAppsRequest()
        req.appID = appId
        let response: Mezon_Api_GenerateHashChannelAppsResponse = try await postProto(
            path: "/mezon.api.Mezon/GenerateHashChannelApps",
            message: req,
            auth: .bearer(token)
        )
        return response.webAppData
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

    func listFriends(
        token: String,
        limit: Int32 = 100,
        state: Int32 = 0,
        cursor: String = ""
    ) async throws -> Mezon_Api_FriendList {
        var req = Mezon_Api_ListFriendsRequest()
        req.limit = min(max(limit, 1), 100)
        req.state = state
        req.cursor = cursor
        return try await postProto(
            path: "/mezon.api.Mezon/ListFriends",
            message: req,
            auth: .bearer(token)
        )
    }

    func addFriends(ids: [Int64] = [], usernames: [String] = [], token: String) async throws {
        var req = Mezon_Api_AddFriendsRequest()
        req.ids = ids
        req.usernames = usernames
        let _: Mezon_Api_AddFriendsResponse = try await postProto(
            path: "/mezon.api.Mezon/AddFriends",
            message: req,
            auth: .bearer(token)
        )
    }

    func deleteFriends(ids: [Int64] = [], usernames: [String] = [], token: String) async throws {
        var req = Mezon_Api_DeleteFriendsRequest()
        req.ids = ids
        req.usernames = usernames
        let _: SwiftProtobuf.Google_Protobuf_Empty = try await postProto(
            path: "/mezon.api.Mezon/DeleteFriends",
            message: req,
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

    func reportMessageAbuse(messageId: Int64, abuseType: String, token: String) async throws {
        var req = Mezon_Api_ReportMessageAbuseReqest()
        req.messageID = messageId
        req.abuseType = abuseType
        let _: SwiftProtobuf.Google_Protobuf_Empty = try await postProto(
            path: "/mezon.api.Mezon/ReportMessageAbuse",
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

    func deletePinMessage(
        clanId: Int64,
        channelId: Int64,
        pinId: Int64,
        messageId: Int64,
        token: String
    ) async throws {
        var req = Mezon_Api_DeletePinMessage()
        req.clanID = clanId
        req.channelID = channelId
        req.id = pinId
        req.messageID = messageId
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/DeletePinMessage",
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
        allowBearerRetry: Bool = true,
        preferHTTPFirst: Bool = false
    ) async throws -> Response {
        if preferHTTPFirst {
            let prefix = "/mezon.api.Mezon/"
            let apiName = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
            do {
                let response: Response = try await postProtoHTTP(
                    path: path,
                    message: message,
                    auth: auth,
                    allowBearerRetry: allowBearerRetry
                )
                MezonRPCLog.response("route api='\(apiName)' HTTP-FIRST ok (skipped socket)")
                return response
            } catch {
                MezonRPCLog.response("route api='\(apiName)' HTTP-FIRST fail error=\(error.localizedDescription) → SOCKET fallback")
                if let response: Response = try await sendOverSocketIfPossible(path: path, message: message) {
                    return response
                }
                throw error
            }
        }
        if let response: Response = try await sendOverSocketIfPossible(path: path, message: message) {
            return response
        }
        return try await postProtoHTTP(
            path: path,
            message: message,
            auth: auth,
            allowBearerRetry: allowBearerRetry
        )
    }

    private static let httpOnlyApiNames: Set<String> = [
        "SessionRefresh"
    ]
    private static let socketFallbackGraceWaitNanoseconds: UInt64 = 2_000_000_000

    private func sendOverSocketIfPossible<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
        path: String,
        message: Request
    ) async throws -> Response? {
        let prefix = "/mezon.api.Mezon/"
        guard path.hasPrefix(prefix) else { return nil }
        let apiName = String(path.dropFirst(prefix.count))

        if Self.httpOnlyApiNames.contains(apiName) {
            return nil
        }

        var connected = await MezonSocket.shared.isConnected
        if !connected {
            connected = await MezonSocket.shared.waitForConnected(
                timeoutNanoseconds: Self.socketFallbackGraceWaitNanoseconds)
        }
        guard connected else {
            let waitMs = Int(Self.socketFallbackGraceWaitNanoseconds / 1_000_000)
            MezonRPCLog.response("route api='\(apiName)' SOCKET unavailable after graceWaitMs=\(waitMs) → HTTP fallback")
            return nil
        }

        let body: Data
        do {
            body = try message.serializedData()
        } catch {
            throw MezonError.socketError("Encode body failed for '\(apiName)': \(error.localizedDescription)")
        }

        let started = Date()
        do {
            let respBytes = try await MezonSocket.shared.sendApiRequest(apiName: apiName, body: body)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            MezonRPCLog.response("route api='\(apiName)' SOCKET ok respBytes=\(respBytes.count) elapsedMs=\(ms)")
            if Response.self == SwiftProtobuf.Google_Protobuf_Empty.self {
                return SwiftProtobuf.Google_Protobuf_Empty() as? Response
            }
            do {
                return try Response(serializedBytes: respBytes)
            } catch {
                MezonRPCLog.response("route api='\(apiName)' SOCKET decode FAIL bytes=\(respBytes.count) error=\(error.localizedDescription) → HTTP fallback")
                return nil
            }
        } catch {
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            MezonRPCLog.response("route api='\(apiName)' SOCKET fail elapsedMs=\(ms) error=\(error.localizedDescription) → HTTP fallback")
            return nil
        }
    }

    private func postProtoHTTP<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
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

        let started = Date()

        let (data, response) = try await httpData(request)

        guard let http = response as? HTTPURLResponse else {
            MezonRPCLog.response("HTTP \(path) invalid response")
            throw MezonError.invalidResponse
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)

        if (200..<300).contains(http.statusCode) {
            MezonRPCLog.response("HTTP \(path) ok status=\(http.statusCode) bytes=\(data.count) elapsedMs=\(ms)")
            do {
                return try Response(serializedBytes: data)
            } catch {
                MezonRPCLog.response("HTTP \(path) decode FAIL bytes=\(data.count) error=\(error.localizedDescription)")
                throw error
            }
        }

        if allowBearerRetry,
            http.statusCode == 401 || http.statusCode == 403,
            case .bearer = auth,
            let recovery = bearerUnauthorizedRecovery,
           let newToken = try await recovery() {
            return try await postProtoHTTP(
                path: path,
                message: message,
                auth: .bearer(newToken),
                allowBearerRetry: false
            )
        }

        let msg = apiFailureMessage(httpStatusCode: http.statusCode, data: data)
        MezonRPCLog.response("HTTP \(path) FAIL status=\(http.statusCode) elapsedMs=\(ms) msg='\(msg)'")
        throw MezonError.httpError(statusCode: http.statusCode, message: msg)
    }

    private func apiFailureMessage(httpStatusCode: Int, data: Data) -> String {
        let decoded = (try? JSONDecoder().decode(APIError.self, from: data))?.message
        let base = decoded ?? HTTPURLResponse.localizedString(forStatusCode: httpStatusCode)
        #if DEBUG
        if httpStatusCode >= 500, !data.isEmpty,
            let snippet = String(data: data.prefix(1500), encoding: .utf8), !snippet.isEmpty {
            return "\(base) | raw=\(snippet)"
        }
        #endif
        return base
    }

    func postProtoIgnoringBody<Request: SwiftProtobuf.Message>(
        path: String,
        message: Request,
        auth: AuthMethod,
        allowBearerRetry: Bool = true
    ) async throws {
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

        let (data, response) = try await httpData(request)

        guard let http = response as? HTTPURLResponse else { throw MezonError.invalidResponse }

        if (200..<300).contains(http.statusCode) {
            return
        }

        if allowBearerRetry,
            http.statusCode == 401 || http.statusCode == 403,
            case .bearer = auth,
            let recovery = bearerUnauthorizedRecovery,
           let newToken = try await recovery() {
            try await postProtoIgnoringBody(
                path: path,
                message: message,
                auth: .bearer(newToken),
                allowBearerRetry: false
            )
            return
        }

        let msg = apiFailureMessage(httpStatusCode: http.statusCode, data: data)
        MezonRPCLog.response("HTTP \(path) FAIL status=\(http.statusCode) msg='\(msg)'")
        throw MezonError.httpError(statusCode: http.statusCode, message: msg)
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
        guard var components = URLComponents(url: authBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw MezonError.invalidResponse
        }
        if !queryItems.isEmpty { components.queryItems = queryItems }

        guard let url = components.url else {
            throw MezonError.invalidResponse
        }
        var request = URLRequest(url: url)
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
        let (data, response) = try await httpData(request)

        guard let http = response as? HTTPURLResponse else {
            throw MezonError.invalidResponse
        }

        if (200..<300).contains(http.statusCode) {
            if T.self == EmptyResponse.self { return EmptyResponse() as! T }
            return try JSONDecoder().decode(T.self, from: data)
        }

        if allowBearerRetry,
            http.statusCode == 401 || http.statusCode == 403,
            request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true,
            let recovery = bearerUnauthorizedRecovery,
           let newToken = try await recovery() {
            var retry = request
            retry.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            return try await execute(retry, allowBearerRetry: false)
        }

        let msg = (try? JSONDecoder().decode(APIError.self, from: data))?.message
            ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
        throw MezonError.httpError(statusCode: http.statusCode, message: msg)
    }

    func votePoll(
        pollId: Int64,
        messageId: Int64,
        channelId: Int64,
        answerIndices: [Int32],
        token: String
    ) async throws -> Mezon_Api_VotePollResponse {
        var req = Mezon_Api_VotePollRequest()
        req.pollID = pollId
        req.messageID = messageId
        req.channelID = channelId
        req.answerIndices = answerIndices
        return try await postProto(
            path: "/mezon.api.Mezon/VotePoll",
            message: req,
            auth: .bearer(token)
        )
    }

    func createPoll(
        channelId: Int64,
        clanId: Int64,
        question: String,
        answers: [String],
        expireHours: Int32,
        type: Mezon_Api_PollType,
        token: String
    ) async throws -> Mezon_Api_CreatePollResponse {
        var req = Mezon_Api_CreatePollRequest()
        req.channelID = channelId
        req.clanID = clanId
        req.question = question
        req.answers = answers
        req.expireHours = expireHours
        req.type = type
        return try await postProto(
            path: "/mezon.api.Mezon/CreatePoll",
            message: req,
            auth: .bearer(token)
        )
    }

    func getPoll(
        pollId: Int64,
        messageId: Int64,
        channelId: Int64,
        token: String
    ) async throws -> Mezon_Api_GetPollResponse {
        var req = Mezon_Api_GetPollRequest()
        req.pollID = pollId
        req.messageID = messageId
        req.channelID = channelId
        return try await postProto(
            path: "/mezon.api.Mezon/GetPoll",
            message: req,
            auth: .bearer(token)
        )
    }

    func closePoll(
        pollId: Int64,
        messageId: Int64,
        channelId: Int64,
        token: String
    ) async throws {
        var req = Mezon_Api_ClosePollRequest()
        req.pollID = pollId
        req.messageID = messageId
        req.channelID = channelId
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/ClosePoll",
            message: req,
            auth: .bearer(token)
        )
    }

    func markAsRead(channelId: Int64, clanId: Int64, categoryId: Int64 = 0, token: String) async throws {
        var req = Mezon_Api_MarkAsReadRequest()
        req.channelID = channelId
        req.clanID = clanId
        req.categoryID = categoryId
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/MarkAsRead",
            message: req,
            auth: .bearer(token)
        )
    }

    func addFavoriteChannel(channelId: Int64, clanId: Int64, token: String) async throws -> Mezon_Api_AddFavoriteChannelResponse {
        var req = Mezon_Api_AddFavoriteChannelRequest()
        req.channelID = channelId
        req.clanID = clanId
        return try await postProto(
            path: "/mezon.api.Mezon/AddChannelFavorite",
            message: req,
            auth: .bearer(token)
        )
    }

    func removeFavoriteChannel(channelId: Int64, clanId: Int64, token: String) async throws {
        var req = Mezon_Api_RemoveFavoriteChannelRequest()
        req.channelID = channelId
        req.clanID = clanId
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/RemoveChannelFavorite",
            message: req,
            auth: .bearer(token)
        )
    }

    func deleteChannelDesc(channelId: Int64, clanId: Int64, token: String) async throws {
        var req = Mezon_Api_DeleteChannelDescRequest()
        req.channelID = channelId
        req.clanID = clanId
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/DeleteChannelDesc",
            message: req,
            auth: .bearer(token)
        )
    }

    func setMuteChannel(id: Int64, clanId: Int64, muteTime: Int32, active: Int32, token: String) async throws {
        var req = Mezon_Api_SetMuteRequest()
        req.id = id
        req.clanID = clanId
        req.muteTime = muteTime
        req.active = active
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/SetMuteChannel",
            message: req,
            auth: .bearer(token)
        )
    }

    func setNotificationChannel(channelId: Int64, notificationType: Int32, clanId: Int64, token: String) async throws {
        var req = Mezon_Api_SetNotificationRequest()
        req.channelCategoryID = channelId
        req.notificationType = notificationType
        req.clanID = clanId
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/SetNotificationChannelSetting",
            message: req,
            auth: .bearer(token)
        )
    }

    func deleteNotificationChannel(channelId: Int64, token: String) async throws {
        var req = Mezon_Api_NotificationChannel()
        req.channelID = channelId
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/DeleteNotificationChannel",
            message: req,
            auth: .bearer(token)
        )
    }

    func listWebhooksByChannelId(channelId: Int64, clanId: Int64, token: String) async throws -> [Mezon_Api_Webhook] {
        var req = Mezon_Api_WebhookListRequest()
        req.channelID = channelId
        req.clanID = clanId
        let response: Mezon_Api_WebhookListResponse = try await postProto(
            path: "/mezon.api.Mezon/ListWebhookByChannelId",
            message: req,
            auth: .bearer(token)
        )
        return response.webhooks
    }

    func generateWebhook(request: Mezon_Api_WebhookCreateRequest, token: String) async throws -> Mezon_Api_WebhookGenerateResponse {
        return try await postProto(
            path: "/mezon.api.Mezon/GenerateWebhook",
            message: request,
            auth: .bearer(token)
        )
    }

    func updateWebhookById(request: Mezon_Api_WebhookUpdateRequestById, token: String) async throws {
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/UpdateWebhookById",
            message: request,
            auth: .bearer(token)
        )
    }

    func deleteWebhookById(request: Mezon_Api_WebhookDeleteRequestById, token: String) async throws {
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/DeleteWebhookById",
            message: request,
            auth: .bearer(token)
        )
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
