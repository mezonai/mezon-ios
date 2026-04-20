import Foundation
import UIKit

private enum MediaPanelEmojiImagePrefetch {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private static let semaphore = DispatchSemaphore(value: 4)

    static func start(for emojis: [CachedClanEmojiRecord]) {
        let imgproxySide = 32
        let urls: [URL] = emojis.compactMap { emoji in
            let trimmedSrc = emoji.src.trimmingCharacters(in: .whitespacesAndNewlines)
            if emoji.isForSale && trimmedSrc.isEmpty { return nil }
            return MezonConfig.emojiResourceURL(emojiId: "\(emoji.id)", imgproxyFitSide: imgproxySide)
        }
        guard !urls.isEmpty else { return }

        DispatchQueue.global(qos: .utility).async {
            for url in urls {
                let key = url.absoluteString
                if ImageCache.shared.hasDiskCache(forKey: key) { continue }
                if !NetworkMonitor.shared.isConnected { return }

                Self.semaphore.wait()
                let task = Self.session.dataTask(with: url) { data, _, _ in
                    defer { Self.semaphore.signal() }
                    guard let data,
                          let image = UIImage.animatedImage(from: data) ?? UIImage.decodeImage(from: data)
                    else { return }
                    ImageCache.shared.setImage(image, data: data, forKey: key)
                }
                task.resume()
            }
        }
    }
}

extension MezonEngine {

    func prefetchMediaPanelCaches(token: String) async {
        let network = account.network
        let postbox = account.postbox
        let now = Date().timeIntervalSince1970

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    let res = try await network.getListEmojisByUserId(token: token)
                    let rows = res.emojiList.map { $0.toCachedRecord() }
                    if rows.isEmpty {
                        let existing = postbox.getSetting(key: MediaPanelPostboxKeys.emojiListByUser, type: MediaPanelEmojiListCache.self)
                        if let existing, !existing.emojis.isEmpty { return }
                    }
                    let cache = MediaPanelEmojiListCache(fetchedAt: now, emojis: rows)
                    postbox.setSetting(key: MediaPanelPostboxKeys.emojiListByUser, value: cache)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: Notification.Name("MezonEmojiListDidUpdate"),
                            object: nil,
                            userInfo: nil
                        )
                    }
                    MediaPanelEmojiImagePrefetch.start(for: rows)
                } catch {
                }
            }
            group.addTask {
                do {
                    let res = try await network.getListStickersByUserId(token: token)
                    let rows = res.stickers.map { $0.toCachedRecord() }
                    if rows.isEmpty {
                        let existing = postbox.getSetting(key: MediaPanelPostboxKeys.stickerListByUser, type: MediaPanelStickerListCache.self)
                        if let existing, !existing.stickers.isEmpty { return }
                    }
                    let cache = MediaPanelStickerListCache(fetchedAt: now, stickers: rows)
                    postbox.setSetting(key: MediaPanelPostboxKeys.stickerListByUser, value: cache)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: Notification.Name("MezonStickerListDidUpdate"),
                            object: nil,
                            userInfo: nil
                        )
                    }
                } catch {
                }
            }
            group.addTask {
                guard TenorGIFClient.isConfigured else {
                    return
                }
                do {
                    let data = try await TenorGIFClient.fetchCategoriesData()
                    let cache = MediaPanelTenorJsonCache(fetchedAt: now, jsonData: data)
                    postbox.setSetting(key: MediaPanelPostboxKeys.gifCategoriesJson, value: cache)
                } catch {
                }
            }
            group.addTask {
                guard TenorGIFClient.isConfigured else { return }
                do {
                    let data = try await TenorGIFClient.fetchFeaturedData()
                    let cache = MediaPanelTenorJsonCache(fetchedAt: now, jsonData: data)
                    postbox.setSetting(key: MediaPanelPostboxKeys.gifFeaturedJson, value: cache)
                } catch {
                }
            }
        }
    }
}

enum TenorGIFClient {

    private static let categoriesURL = "https://tenor.googleapis.com/v2/categories"
    private static let featuredURL = "https://tenor.googleapis.com/v2/featured"
    private static let searchURL = "https://tenor.googleapis.com/v2/search"

    static var isConfigured: Bool {
        MezonEnvironment.tenorAPIKey != nil && MezonEnvironment.tenorClientKey != nil
    }

    static func fetchCategoriesData() async throws -> Data {
        try await getJSON(urlString: categoriesURL, extraItems: [
            URLQueryItem(name: "type", value: "featured"),
            URLQueryItem(name: "limit", value: "30"),
        ])
    }

    static func fetchFeaturedData() async throws -> Data {
        try await getJSON(urlString: featuredURL, extraItems: [
            URLQueryItem(name: "limit", value: "30"),
        ])
    }

    static func fetchSearchData(query: String) async throws -> Data {
        try await getJSON(urlString: searchURL, extraItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "30"),
        ])
    }

    private static func getJSON(urlString: String, extraItems: [URLQueryItem]) async throws -> Data {
        guard let key = MezonEnvironment.tenorAPIKey, let clientKey = MezonEnvironment.tenorClientKey else {
            throw URLError(.userAuthenticationRequired)
        }
        guard var components = URLComponents(string: urlString) else {
            throw URLError(.badURL)
        }
        var items = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "client_key", value: clientKey),
        ]
        items.append(contentsOf: extraItems)
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
