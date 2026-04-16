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
    static var mmnAPIURL: URL         { env.mmnAPIURL }

    static var meetWebSocketURLString: String { env.meetWebSocketURLString }

    static var chatWebAppBaseURL: String {
        if let raw = Self.infoPlistString("MEZON_CHAT_WEB_BASE_URL"), !raw.isEmpty {
            return raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return "https://mezon.ai"
    }

    static func canvasMobileURL(clanId: Int64, channelId: Int64, canvasId: Int64) -> URL? {
        URL(string: "\(chatWebAppBaseURL)/chat/canvas-mobile/\(clanId)/\(channelId)/\(canvasId)")
    }

    static func canvasShareURLString(clanId: Int64, channelId: Int64, canvasId: Int64) -> String {
        "\(chatWebAppBaseURL)/chat/clans/\(clanId)/channels/\(channelId)/canvas/\(canvasId)"
    }

    private static func infoPlistString(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func emojiImageURL(emojiId: String) -> URL? {
        guard !emojiId.isEmpty else {
            #if DEBUG
            print("[EmojiURL] direct skipped: empty emojiId baseImgURL=\(env.baseImgURL)")
            #endif
            return nil
        }
        let path = "\(env.baseImgURL)/emojis/\(emojiId).webp"
        let url = URL(string: path)
        #if DEBUG
        if let url {
            print("[EmojiURL] direct ok emojiId=\(emojiId) -> \(url.absoluteString)")
        } else {
            print("[EmojiURL] direct URL(string:) failed emojiId=\(emojiId) path=\(path)")
        }
        #endif
        return url
    }


    static func emojiResourceURL(emojiId: String, imgproxyFitSide: Int) -> URL? {
        guard let direct = emojiImageURL(emojiId: emojiId) else { return nil }
        let side = max(1, imgproxyFitSide)
        let proxied = ImgproxyURL.createEmoji(from: direct.absoluteString, width: side, height: side)
        let final = URL(string: proxied)
        #if DEBUG
        if proxied == direct.absoluteString {
            print("[EmojiURL] proxied same as direct (imgproxy skipped?) side=\(side) -> \(proxied)")
        } else if let final {
            print("[EmojiURL] proxied ok side=\(side) -> \(final.absoluteString)")
        } else {
            print("[EmojiURL] proxied URL(string:) failed side=\(side) string=\(proxied)")
        }
        #endif
        return final
    }

    static func wsURL(token: String, wsHostOverride: String? = nil) -> URL {
        if let override = wsHostOverride, !override.isEmpty {
            let host: String
            if override.contains("://"), let url = URL(string: override), let h = url.host, !h.isEmpty {
                host = h
            } else if !override.contains("://") {
                host = override
            } else {
                return env.wsURL(token: token)
            }
            var components = URLComponents()
            components.scheme = env.useSSL ? "wss" : "ws"
            components.host = host
            components.path = "/ws"
            components.queryItems = [
                URLQueryItem(name: "token", value: token),
                URLQueryItem(name: "format", value: "protobuf"),
            ]
            guard let url = components.url else { return env.wsURL(token: token) }
            return url
        }
        return env.wsURL(token: token)
    }

}
