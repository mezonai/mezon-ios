import Foundation

extension MezonEngine {
    private static var stickerListSyncTask: Task<Void, Never>?

    func scheduleStickerListNetworkSync(debounceSeconds: Double = 0.8) {
        Self.stickerListSyncTask?.cancel()
        Self.stickerListSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(debounceSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.syncStickerListFromNetwork()
        }
    }

    func syncStickerListFromNetwork() async {
        guard let session = SessionStore.load(),
              !session.token.isEmpty,
              !session.isExpired else { return }
        do {
            try await refreshStickerListFromNetwork(token: session.token)
        } catch {
        }
    }

    func refreshStickerListFromNetwork(token: String) async throws {
        let postbox = account.postbox
        let key = MediaPanelPostboxKeys.stickerListByUser
        let previousEventRevision = stickerListEventRevision
        let previous = await Task.detached {
            postbox.getSettingData(key: key)
        }.value
        let response = try await account.network.getListStickersByUserId(token: token)
        try Task.checkCancellation()
        let cacheData = try await Task.detached { () throws -> Data? in
            guard !response.stickers.isEmpty else { return nil }
            let cache = MediaPanelStickerListCache(
                fetchedAt: Date().timeIntervalSince1970,
                stickers: response.stickers.map { $0.toCachedRecord() }
            )
            return try JSONEncoder().encode(cache)
        }.value
        try Task.checkCancellation()
        let current = postbox.getSettingData(key: key)
        guard current == previous, stickerListEventRevision == previousEventRevision else {
            scheduleStickerListNetworkSync()
            return
        }

        guard let cacheData else { return }
        postbox.setSettingData(key: key, value: cacheData)
        NotificationCenter.default.post(name: .mezonStickerListDidUpdate, object: nil)
    }

    func handleStickerEvent(_ event: SocketEvent) {
        let postbox = account.postbox
        let now = Date().timeIntervalSince1970
        var cache = postbox.getSetting(key: MediaPanelPostboxKeys.stickerListByUser, type: MediaPanelStickerListCache.self)
            ?? MediaPanelStickerListCache(fetchedAt: now, stickers: [])

        var stickers = cache.stickers
        var hasChanges = false

        switch event {
        case .stickerCreated(let ev):
            stickerListEventRevision &+= 1
            if let idx = stickers.firstIndex(where: { $0.id == ev.stickerID }) {
                var existing = stickers[idx]
                if !ev.source.isEmpty {
                    existing.source = ev.source
                }
                if !ev.shortname.isEmpty { existing.shortname = ev.shortname }
                if !ev.category.isEmpty { existing.category = ev.category }
                if ev.creatorID != 0 { existing.creatorID = ev.creatorID }
                if ev.clanID != 0 { existing.clanID = ev.clanID }
                if !ev.logo.isEmpty { existing.logo = ev.logo }
                if !ev.clanName.isEmpty { existing.clanName = ev.clanName }
                stickers[idx] = existing
                hasChanges = true
            } else {
                scheduleStickerListNetworkSync()
                return
            }
            stickers.removeAll { $0.id == 0 }
        case .stickerUpdated(let ev):
            stickerListEventRevision &+= 1
            if let idx = stickers.firstIndex(where: { $0.id == ev.stickerID }),
               !ev.shortname.isEmpty {
                stickers[idx].shortname = ev.shortname
                hasChanges = true
            }
        case .stickerDeleted(let ev):
            stickerListEventRevision &+= 1
            if stickers.contains(where: { $0.id == ev.stickerID }) {
                stickers.removeAll { $0.id == ev.stickerID }
                hasChanges = true
            }
        default:
            break
        }

        guard hasChanges else { return }

        cache.fetchedAt = now
        cache.stickers = stickers
        postbox.setSetting(key: MediaPanelPostboxKeys.stickerListByUser, value: cache)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .mezonStickerListDidUpdate, object: nil)
        }
    }
}
