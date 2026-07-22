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
                    let existing = postbox.getSetting(key: MediaPanelPostboxKeys.emojiListByUser, type: MediaPanelEmojiListCache.self)
                    let apiRows = res.emojiList.map { $0.toCachedRecord() }
                    if apiRows.isEmpty {
                        if let existing, !existing.emojis.isEmpty { return }
                    }
                    let rows = apiRows.deduplicatedByEmojiId()
                    let cache = MediaPanelEmojiListCache(fetchedAt: now, emojis: rows)
                    postbox.setSetting(key: MediaPanelPostboxKeys.emojiListByUser, value: cache)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .mezonEmojiListDidUpdate, object: nil)
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
                            name: .mezonStickerListDidUpdate,
                            object: nil,
                            userInfo: nil
                        )
                    }
                } catch {
                }
            }
            group.addTask {
                guard MezonEnvironment.isKlipyConfigured else { return }
                do {
                    let data = try await KlipyGIFClient.fetchCategoriesData()
                    let cache = MediaPanelTenorJsonCache(fetchedAt: now, jsonData: data)
                    postbox.setSetting(key: MediaPanelPostboxKeys.gifCategoriesJson, value: cache)
                } catch {
                }
            }
            group.addTask {
                guard MezonEnvironment.isKlipyConfigured else { return }
                do {
                    let data = try await KlipyGIFClient.fetchTrendingData()
                    let cache = MediaPanelTenorJsonCache(fetchedAt: now, jsonData: data)
                    postbox.setSetting(key: MediaPanelPostboxKeys.gifFeaturedJson, value: cache)
                } catch {
                }
            }
        }
    }
}

enum KlipyGIFClient {

    static func fetchCategoriesData() async throws -> Data {
        let urlStr = "\(MezonEnvironment.klipyBaseURL)/\(MezonEnvironment.klipyAPIKey)/gifs/categories"
        return try await getJSON(urlString: urlStr, extraItems: [])
    }

    static func fetchTrendingData(page: Int = 1, perPage: Int = 30) async throws -> Data {
        // Klipy uses /stickers/trending with format_filter=gif for trending gifs
        let urlStr = "\(MezonEnvironment.klipyBaseURL)/\(MezonEnvironment.klipyAPIKey)/stickers/trending"
        return try await getJSON(urlString: urlStr, extraItems: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
            URLQueryItem(name: "format_filter", value: "gif")
        ])
    }

    static func fetchSearchData(query: String, page: Int = 1, perPage: Int = 30) async throws -> Data {
        let urlStr = "\(MezonEnvironment.klipyBaseURL)/\(MezonEnvironment.klipyAPIKey)/gifs/search"
        return try await getJSON(urlString: urlStr, extraItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
            URLQueryItem(name: "format_filter", value: "gif")
        ])
    }

    private static func getJSON(urlString: String, extraItems: [URLQueryItem]) async throws -> Data {
        guard var components = URLComponents(string: urlString) else {
            throw URLError(.badURL)
        }
        if !extraItems.isEmpty {
            components.queryItems = extraItems
        }
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
