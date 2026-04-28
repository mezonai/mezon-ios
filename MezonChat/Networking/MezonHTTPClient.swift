import Foundation
import SwiftProtobuf
import UIKit
import Network
import os.log

final class MezonHTTPClient {

    static let shared = MezonHTTPClient()
    var bearerUnauthorizedRecovery: (() async throws -> String?)?

    private let urlSession: URLSession
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

    private static let logger = OSLog(subsystem: "ai.mezon.MezonChat", category: "MezonHTTP")
    private let seqLock = NSLock()
    private var seqCounter: UInt64 = 0

    private func nextReqId() -> UInt64 {
        seqLock.lock()
        defer { seqLock.unlock() }
        seqCounter += 1
        return seqCounter
    }

    private func httpData(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let reqId = nextReqId()
        let start = Date()
        Self.logRequest(reqId: reqId, request: request)
        do {
            let result: (Data, URLResponse)
            if #available(iOS 15.0, *) {
                result = try await urlSession.data(for: request)
            } else {
                result = try await legacyData(for: request)
            }
            let elapsed = Date().timeIntervalSince(start) * 1000
            Self.logResponse(reqId: reqId, request: request, response: result.1, data: result.0, elapsedMs: elapsed)
            return result
        } catch {
            let elapsed = Date().timeIntervalSince(start) * 1000
            Self.logFailure(reqId: reqId, request: request, error: error, elapsedMs: elapsed)
            throw error
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

    static func describeAuthHeader(_ value: String?) -> String {
        guard let v = value, !v.isEmpty else { return "none" }
        if v.hasPrefix("Bearer ") {
            let tok = String(v.dropFirst(7))
            return "Bearer(len=\(tok.count), tail=\(tok.suffix(6)))"
        }
        if v.hasPrefix("Basic ") {
            return "Basic(len=\(v.count - 6))"
        }
        return "type=\(v.prefix(12))…"
    }

    static func describeNSError(_ error: Error, maxDepth: Int = 5) -> String {
        var lines: [String] = []
        var current: Error? = error
        var depth = 0
        while let err = current, depth < maxDepth {
            let ns = err as NSError
            let keys = ns.userInfo.keys.map { String(describing: $0) }.sorted().joined(separator: ",")
            var extra = ""
            if ns.domain == NSURLErrorDomain {
                extra = " urlErr=\(NSURLErrorName(ns.code))"
                if let failingURL = ns.userInfo[NSURLErrorFailingURLStringErrorKey] as? String {
                    extra += " failingURL=\(failingURL)"
                }
            }
            lines.append("[\(depth)] \(ns.domain) code=\(ns.code)\(extra) desc=\(ns.localizedDescription) keys=[\(keys)]")
            current = ns.userInfo[NSUnderlyingErrorKey] as? Error
            depth += 1
        }
        return lines.joined(separator: " => ")
    }

    static func currentNetworkSnapshot() -> String {
        var parts: [String] = []
        parts.append("connected=\(NetworkMonitor.shared.isConnected)")
        if Thread.isMainThread {
            parts.append("appState=\(UIApplication.shared.applicationState.debugName)")
        }
        parts.append("iOS=\(UIDevice.current.systemVersion)")
        return parts.joined(separator: " | ")
    }

    private static func logRequest(reqId: UInt64, request: URLRequest) {
        let auth = describeAuthHeader(request.value(forHTTPHeaderField: "Authorization"))
        let bodyLen = request.httpBody?.count ?? 0
        let line = "[REQ #\(reqId)] \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?") | bodyLen=\(bodyLen) | auth=\(auth) | ct=\(request.value(forHTTPHeaderField: "Content-Type") ?? "-") | accept=\(request.value(forHTTPHeaderField: "Accept") ?? "-") | net=[\(currentNetworkSnapshot())]"
        emit(line, kind: .routine)
    }

    private static func logResponse(reqId: UInt64, request: URLRequest, response: URLResponse, data: Data, elapsedMs: Double) {
        guard let http = response as? HTTPURLResponse else {
            emit(
                "[RES #\(reqId)] non-HTTP response \(type(of: response)) elapsed=\(String(format: "%.0f", elapsedMs))ms",
                kind: .issue
            )
            return
        }
        let ct = http.value(forHTTPHeaderField: "Content-Type") ?? "-"
        let server = http.value(forHTTPHeaderField: "Server") ?? "-"
        var line = "[RES #\(reqId)] \(http.statusCode) \(request.url?.absoluteString ?? "?") | bytes=\(data.count) | ct=\(ct) | server=\(server) | elapsed=\(String(format: "%.0f", elapsedMs))ms"
        let kind: MezonHTTPLogKind = (200..<300).contains(http.statusCode) ? .routine : .issue
        if kind == .issue {
            let snippet = bodySnippet(data, limit: 256)
            line += " | bodyPreview=\(snippet)"
        }
        emit(line, kind: kind)
    }

    private static func logFailure(reqId: UInt64, request: URLRequest, error: Error, elapsedMs: Double) {
        let chain = describeNSError(error)
        let line = "[ERR #\(reqId)] \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?") | elapsed=\(String(format: "%.0f", elapsedMs))ms | net=[\(currentNetworkSnapshot())] | chain=\(chain)"
        emit(line, kind: .issue)
    }

    static func bodySnippet(_ data: Data, limit: Int) -> String {
        guard !data.isEmpty else { return "<empty>" }
        if let s = String(data: data.prefix(limit), encoding: .utf8) {
            let truncated = data.count > limit ? "…(+\(data.count - limit)B)" : ""
            return "\"\(s.replacingOccurrences(of: "\n", with: "\\n"))\"\(truncated)"
        }
        return "<\(data.count)B binary> head=\(data.prefix(min(16, data.count)).map { String(format: "%02x", $0) }.joined())"
    }

    static func emit(_ message: String, kind: MezonHTTPLogKind = .routine) {
        #if DEBUG
        switch kind {
        case .routine:
            guard MezonConsoleLog.httpVerbose else { return }
        case .diagnostic:
            guard MezonConsoleLog.networkDiagnostics else { return }
        case .issue:
            break
        }
        #else
        if kind != .issue { return }
        #endif
        let ot: OSLogType = kind == .issue ? .default : .info
        os_log("%{public}@", log: logger, type: ot, message)
        #if DEBUG
        print("[MezonHTTP] \(message)")
        #endif
    }

    func updateBaseURL(from session: MezonSession) {
        guard let apiURL = session.apiURL else { return }
        let cleaned = stripDefaultPort(apiURL)
        guard let url = URL(string: cleaned) else { return }
        protoBaseURL = url
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
        let tokenTail = String(refreshToken.suffix(6))
        Self.emit(
            "[SessionRefresh] start | tokenLen=\(refreshToken.count) tail=\(tokenTail) baseURL=\(protoBaseURL.absoluteString)",
            kind: .diagnostic
        )
        do {
            var req = Mezon_Api_SessionRefreshRequest()
            req.token = refreshToken
            req.vars = ["m": "true"]
            let apiSession: Mezon_Api_Session = try await postProto(
                path: "/mezon.api.Mezon/SessionRefresh",
                message: req,
                auth: .serverKey
            )
            Self.emit(
                "[SessionRefresh] ok | newTokenLen=\(apiSession.token.count) refreshLen=\(apiSession.refreshToken.count) userId=\(apiSession.userID)",
                kind: .diagnostic
            )
            return MezonSession.fromProto(apiSession)
        } catch {
            Self.emit("[SessionRefresh] FAIL | tokenTail=\(tokenTail) | \(Self.describeNSError(error))", kind: .issue)
            throw error
        }
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
        var req = Mezon_Api_ListChannelDescsRequest()
        req.clanID = clanId
        req.limit = 100
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

        let (_, response) = try await httpData(request)
        guard let http = response as? HTTPURLResponse else { throw MezonError.invalidResponse }
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

        let (data, response) = try await httpData(request)

        guard let http = response as? HTTPURLResponse else { throw MezonError.invalidResponse }

        if (200..<300).contains(http.statusCode) {
            do {
                return try Response(serializedBytes: data)
            } catch {
                Self.emit(
                    "[postProto] decode FAIL path=\(path) bytes=\(data.count) ct=\(http.value(forHTTPHeaderField: "Content-Type") ?? "-") preview=\(Self.bodySnippet(data, limit: 256)) err=\(Self.describeNSError(error))",
                    kind: .issue
                )
                throw error
            }
        }

        if allowBearerRetry,
            http.statusCode == 401 || http.statusCode == 403,
            case .bearer = auth,
            let recovery = bearerUnauthorizedRecovery,
           let newToken = try await recovery() {
            Self.emit("[postProto] retry-after-401 path=\(path) status=\(http.statusCode) newTokenLen=\(newToken.count)", kind: .issue)
            return try await postProto(
                path: path,
                message: message,
                auth: .bearer(newToken),
                allowBearerRetry: false
            )
        }

        let msg = (try? JSONDecoder().decode(APIError.self, from: data))?.message
            ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
        Self.emit("[postProto] HTTP error path=\(path) status=\(http.statusCode) msg=\(msg)", kind: .issue)
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
}

private struct EmptyBody: Encodable {}
struct EmptyResponse: Decodable {}
struct APIError: Decodable { let message: String?; let code: Int? }

private extension UIApplication.State {
    var debugName: String {
        switch self {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }
}

func NSURLErrorName(_ code: Int) -> String {
    switch code {
    case NSURLErrorUnknown: return "Unknown"
    case NSURLErrorCancelled: return "Cancelled"
    case NSURLErrorBadURL: return "BadURL"
    case NSURLErrorTimedOut: return "TimedOut"
    case NSURLErrorUnsupportedURL: return "UnsupportedURL"
    case NSURLErrorCannotFindHost: return "CannotFindHost"
    case NSURLErrorCannotConnectToHost: return "CannotConnectToHost"
    case NSURLErrorNetworkConnectionLost: return "NetworkConnectionLost"
    case NSURLErrorDNSLookupFailed: return "DNSLookupFailed"
    case NSURLErrorHTTPTooManyRedirects: return "HTTPTooManyRedirects"
    case NSURLErrorResourceUnavailable: return "ResourceUnavailable"
    case NSURLErrorNotConnectedToInternet: return "NotConnectedToInternet"
    case NSURLErrorRedirectToNonExistentLocation: return "RedirectToNonExistentLocation"
    case NSURLErrorBadServerResponse: return "BadServerResponse"
    case NSURLErrorUserCancelledAuthentication: return "UserCancelledAuthentication"
    case NSURLErrorUserAuthenticationRequired: return "UserAuthenticationRequired"
    case NSURLErrorZeroByteResource: return "ZeroByteResource"
    case NSURLErrorCannotDecodeRawData: return "CannotDecodeRawData"
    case NSURLErrorCannotDecodeContentData: return "CannotDecodeContentData"
    case NSURLErrorCannotParseResponse: return "CannotParseResponse"
    case NSURLErrorAppTransportSecurityRequiresSecureConnection: return "ATSRequiresSecure"
    case NSURLErrorFileDoesNotExist: return "FileDoesNotExist"
    case NSURLErrorFileIsDirectory: return "FileIsDirectory"
    case NSURLErrorNoPermissionsToReadFile: return "NoPermissionsToReadFile"
    case NSURLErrorDataLengthExceedsMaximum: return "DataLengthExceedsMaximum"
    case NSURLErrorFileOutsideSafeArea: return "FileOutsideSafeArea"
    case NSURLErrorSecureConnectionFailed: return "SecureConnectionFailed"
    case NSURLErrorServerCertificateHasBadDate: return "ServerCertificateHasBadDate"
    case NSURLErrorServerCertificateUntrusted: return "ServerCertificateUntrusted"
    case NSURLErrorServerCertificateHasUnknownRoot: return "ServerCertificateHasUnknownRoot"
    case NSURLErrorServerCertificateNotYetValid: return "ServerCertificateNotYetValid"
    case NSURLErrorClientCertificateRejected: return "ClientCertificateRejected"
    case NSURLErrorClientCertificateRequired: return "ClientCertificateRequired"
    case NSURLErrorCannotLoadFromNetwork: return "CannotLoadFromNetwork"
    case NSURLErrorCannotCreateFile: return "CannotCreateFile"
    case NSURLErrorCannotOpenFile: return "CannotOpenFile"
    case NSURLErrorCannotCloseFile: return "CannotCloseFile"
    case NSURLErrorCannotWriteToFile: return "CannotWriteToFile"
    case NSURLErrorCannotRemoveFile: return "CannotRemoveFile"
    case NSURLErrorCannotMoveFile: return "CannotMoveFile"
    case NSURLErrorDownloadDecodingFailedMidStream: return "DownloadDecodingFailedMidStream"
    case NSURLErrorDownloadDecodingFailedToComplete: return "DownloadDecodingFailedToComplete"
    case NSURLErrorInternationalRoamingOff: return "InternationalRoamingOff"
    case NSURLErrorCallIsActive: return "CallIsActive"
    case NSURLErrorDataNotAllowed: return "DataNotAllowed"
    case NSURLErrorRequestBodyStreamExhausted: return "RequestBodyStreamExhausted"
    case NSURLErrorBackgroundSessionRequiresSharedContainer: return "BackgroundSessionRequiresSharedContainer"
    case NSURLErrorBackgroundSessionInUseByAnotherProcess: return "BackgroundSessionInUseByAnotherProcess"
    case NSURLErrorBackgroundSessionWasDisconnected: return "BackgroundSessionWasDisconnected"
    default: return "code=\(code)"
    }
}

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
