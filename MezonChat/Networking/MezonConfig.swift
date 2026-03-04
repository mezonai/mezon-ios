import Foundation

enum MezonConfig {

    static var env: MezonEnvironment {
        get { MezonEnvironment.current }
        set { MezonEnvironment.current = newValue }
    }

    static var authBaseURL: URL      { env.authBaseURL }
    static var protoBaseURL: URL     { env.protoBaseURL }
    static var serverKey: String     { env.serverKey }
    static var basicAuthHeader: String { env.basicAuthHeader }
    static var baseImgURL: String    { env.baseImgURL }
    static var profileImgURL: String { env.profileImgURL }

    static func wsURL(token: String, wsHostOverride: String? = nil) -> URL {
        if let override = wsHostOverride {
            var components = URLComponents()
            components.scheme = env.useSSL ? "wss" : "ws"
            components.host = override
            components.path = "/ws"
            components.queryItems = [
                URLQueryItem(name: "token", value: token),
                URLQueryItem(name: "format", value: "protobuf"),
            ]
            return components.url!
        }
        return env.wsURL(token: token)
    }
}
