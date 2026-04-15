import Foundation

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
                    let cache = MediaPanelEmojiListCache(fetchedAt: now, emojis: rows)
                    postbox.setSetting(key: MediaPanelPostboxKeys.emojiListByUser, value: cache)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: Notification.Name("MezonEmojiListDidUpdate"),
                            object: nil,
                            userInfo: nil
                        )
                    }
                } catch {
                }
            }
            group.addTask {
                do {
                    let res = try await network.getListStickersByUserId(token: token)
                    let rows = res.stickers.map { $0.toCachedRecord() }
                    let cache = MediaPanelStickerListCache(fetchedAt: now, stickers: rows)
                    postbox.setSetting(key: MediaPanelPostboxKeys.stickerListByUser, value: cache)
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
