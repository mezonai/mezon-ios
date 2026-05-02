import Foundation

enum MezonEnvironment {
    case dev
    case prod

    var apiHost: String {
        switch self {
        case .dev:  return Secrets.devApiHost
        case .prod: return Secrets.prodApiHost
        }
    }

    var apiPort: Int? {
        switch self {
        case .dev:  return Secrets.devApiPort
        case .prod: return Secrets.prodApiPort
        }
    }

    var apiGWHost: String {
        switch self {
        case .dev:  return Secrets.devApiGWHost
        case .prod: return Secrets.prodApiGWHost
        }
    }

    var apiGWPort: Int? {
        switch self {
        case .dev:  return Secrets.devApiGWPort
        case .prod: return Secrets.prodApiGWPort
        }
    }

    var wsHost: String {
        switch self {
        case .dev:  return Secrets.devWsHost
        case .prod: return Secrets.prodWsHost
        }
    }

    var wsPort: Int? {
        switch self {
        case .dev:  return Secrets.devWsPort
        case .prod: return Secrets.prodWsPort
        }
    }

    var serverKey: String {
        switch self {
        case .dev:  return Secrets.devServerKey
        case .prod: return Secrets.prodServerKey
        }
    }

    var useSSL: Bool { return true }

    var baseImgURL: String {
        switch self {
        case .dev:  return Secrets.devBaseImgURL
        case .prod: return Secrets.prodBaseImgURL
        }
    }

    var profileImgURL: String {
        switch self {
        case .dev:  return Secrets.devProfileImgURL
        case .prod: return Secrets.prodProfileImgURL
        }
    }

    var imgproxyBaseURL: String {
        switch self {
        case .dev:  return Secrets.devImgproxyBaseURL
        case .prod: return Secrets.prodImgproxyBaseURL
        }
    }

    var imgproxySigningPath: String {
        switch self {
        case .dev:  return Secrets.devImgproxySigningPath
        case .prod: return Secrets.prodImgproxySigningPath
        }
    }

    var authBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = apiGWHost
        components.port = apiGWPort
        guard let url = components.url else {
            fatalError("Invalid authBaseURL components: \(components)")
        }
        return url
    }

    var protoBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = apiHost
        components.port = apiPort
        guard let url = components.url else {
            fatalError("Invalid protoBaseURL components: \(components)")
        }
        return url
    }

    func wsURL(token: String) -> URL {
        var components = URLComponents()
        components.scheme = useSSL ? "wss" : "ws"
        components.host = wsHost
        components.port = wsPort
        components.path = "/ws"
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "format", value: "protobuf"),
        ]
        guard let url = components.url else {
            fatalError("Invalid wsURL components: \(components)")
        }
        return url
    }

    var basicAuthHeader: String {
        let encoded = Data("\(serverKey):".utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    static var current: MezonEnvironment = .prod

    private static func infoPlistString(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static var tenorAPIKey: String? {
        switch current {
        case .dev:  return Secrets.devTenorAPIKey
        case .prod: return Secrets.prodTenorAPIKey
        }
    }

    static var tenorClientKey: String? {
        switch current {
        case .dev:  return Secrets.devTenorClientKey
        case .prod: return Secrets.prodTenorClientKey
        }
    }

    var mmnAPIURL: URL {
        switch self {
        case .dev:  return URL(string: Secrets.devMmnAPIURL)!
        case .prod: return URL(string: Secrets.prodMmnAPIURL)!
        }
    }

    var zkAPIURL: URL {
        if let s = Self.infoPlistString("MEZON_ZK_API_URL"), let u = URL(string: s) { return u }
        switch self {
        case .dev:  return URL(string: Secrets.devZkAPIURL)!
        case .prod: return URL(string: Secrets.prodZkAPIURL)!
        }
    }

    var meetWebSocketURLString: String {
        if let override = Self.infoPlistString("MEET_WS_URL"), !override.isEmpty {
            return override
        }
        switch self {
        case .dev:  return Secrets.devMeetWebSocketURL
        case .prod: return Secrets.prodMeetWebSocketURL
        }
    }

    var webRTCIceServerURL: String {
        switch self {
        case .dev: return Secrets.devWebRTCIceServerURL
        case .prod: return Secrets.prodWebRTCIceServerURL
        }
    }

    var webRTCIceUsername: String {
        switch self {
        case .dev: return Secrets.devWebRTCIceUsername
        case .prod: return Secrets.prodWebRTCIceUsername
        }
    }

    var webRTCIceCredential: String {
        switch self {
        case .dev: return Secrets.devWebRTCIceCredential
        case .prod: return Secrets.prodWebRTCIceCredential
        }
    }
}
