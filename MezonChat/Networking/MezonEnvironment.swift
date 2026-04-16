import Foundation

enum MezonEnvironment {
    case dev
    case prod

    var apiHost: String {
        switch self {
        case .dev:  return "dev-mezon.nccsoft.vn"
        case .prod: return Secrets.prodApiHost
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
        case .prod: return Secrets.prodApiGWHost
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
        case .prod: return Secrets.prodWsHost
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

    var baseImgURL: String {
        switch self {
        case .dev:  return "https://cdn.mezon.ai"
        case .prod: return Secrets.prodBaseImgURL
        }
    }

    var profileImgURL: String {
        switch self {
        case .dev:  return "https://profile.mezon.ai"
        case .prod: return Secrets.prodProfileImgURL
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

    static var tenorAPIKey: String? { Secrets.tenorAPIKey }
    static var tenorClientKey: String? { Secrets.tenorClientKey }

    var mmnAPIURL: URL {
        switch self {
        case .dev:  return URL(string: "https://dev-mmn.nccsoft.vn/mmn-api/")!
        case .prod: return URL(string: Secrets.prodMmnAPIURL)!
        }
    }

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
