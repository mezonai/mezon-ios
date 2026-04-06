import Foundation

enum MezonEnvironment {
    case dev
    case prod

    var apiHost: String {
        switch self {
        case .dev:  return "dev-mezon.nccsoft.vn"
        case .prod: return "api.mezon.ai"
        }
    }

    var apiPort: Int? {
        switch self {
        case .dev:  return 7305
        case .prod: return nil
        }
    }

    var apiGWHost: String {
        switch self {
        case .dev:  return "dev-mezon.nccsoft.vn"
        case .prod: return "gw.mezon.ai"
        }
    }

    var apiGWPort: Int? {
        switch self {
        case .dev:  return 8088
        case .prod: return nil
        }
    }

    var wsHost: String {
        switch self {
        case .dev:  return "dev-mezon.nccsoft.vn"
        case .prod: return "sock.mezon.ai"
        }
    }

    var wsPort: Int? {
        switch self {
        case .dev:  return 7305
        case .prod: return nil
        }
    }

    var serverKey: String {
        switch self {
        case .dev:  return "defaultkey"
        case .prod: return Secrets.prodServerKey
        }
    }

    var useSSL: Bool { return true }

    var baseImgURL: String { return "https://cdn.mezon.ai" }
    var profileImgURL: String { return "https://profile.mezon.ai" }

    var authBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = apiGWHost
        components.port = apiGWPort
        return components.url!
    }

    var protoBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = apiHost
        components.port = apiPort
        return components.url!
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
        return components.url!
    }

    var basicAuthHeader: String {
        let encoded = Data("\(serverKey):".utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    static var current: MezonEnvironment = {
        #if DEBUG
        return .dev
        #else
        return .prod
        #endif
    }()


    private static func infoPlistString(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static var tenorAPIKey: String? { infoPlistString("TENOR_API_KEY") }
    static var tenorClientKey: String? { infoPlistString("TENOR_CLIENT_KEY") }

    var meetWebSocketURLString: String {
        if let override = Self.infoPlistString("MEET_WS_URL"), !override.isEmpty {
            return override
        }
        switch self {
        case .dev: return "wss://meet.mezon.ai"
        case .prod: return "wss://meet.mezon.ai"
        }
    }
}
