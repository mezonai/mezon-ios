import Foundation

extension MezonEngine {
    private static var stickerListSyncHandle: CancelHandle?

    @available(iOS 13.0, *)
    func scheduleStickerListNetworkSync(debounceSeconds: Double = 0.8) {
        Self.stickerListSyncHandle?.cancel()
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(debounceSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.syncStickerListFromNetwork()
        }
        Self.stickerListSyncHandle = CancelHandle { task.cancel() }
    }

    @available(iOS 13.0, *)
    func syncStickerListFromNetwork() async {
        guard let session = SessionStore.load(),
              !session.token.isEmpty,
              !session.isExpired else { return }
        do {
            let res = try await account.network.getListStickersByUserId(token: session.token)
            let rows = res.stickers.map { $0.toCachedRecord() }
            guard !rows.isEmpty else { return }
            let now = Date().timeIntervalSince1970
            let cache = MediaPanelStickerListCache(fetchedAt: now, stickers: rows)
            account.postbox.setSetting(key: MediaPanelPostboxKeys.stickerListByUser, value: cache)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .mezonStickerListDidUpdate, object: nil)
            }
        } catch {
        }
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
            if let idx = stickers.firstIndex(where: { $0.id == ev.stickerID }) {
                var existing = stickers[idx]
                if !ev.source.isEmpty { existing.source = ev.source }
                if !ev.shortname.isEmpty { existing.shortname = ev.shortname }
                if !ev.category.isEmpty { existing.category = ev.category }
                if ev.creatorID != 0 { existing.creatorID = ev.creatorID }
                if ev.clanID != 0 { existing.clanID = ev.clanID }
                if !ev.logo.isEmpty { existing.logo = ev.logo }
                if !ev.clanName.isEmpty { existing.clanName = ev.clanName }
                stickers[idx] = existing
                hasChanges = true
            } else if !ev.shortname.isEmpty,
                      let idx = stickers.firstIndex(where: {
                          $0.shortname == ev.shortname && (ev.clanID == 0 || $0.clanID == ev.clanID)
                      }) {
                var existing = stickers[idx]
                existing.id = ev.stickerID
                if !ev.source.isEmpty { existing.source = ev.source }
                if !ev.category.isEmpty { existing.category = ev.category }
                if ev.creatorID != 0 { existing.creatorID = ev.creatorID }
                if ev.clanID != 0 { existing.clanID = ev.clanID }
                if !ev.logo.isEmpty { existing.logo = ev.logo }
                if !ev.clanName.isEmpty { existing.clanName = ev.clanName }
                stickers[idx] = existing
                stickers.removeAll { $0.id == ev.stickerID && $0.shortname != ev.shortname }
                hasChanges = true
            } else {
                let record = CachedClanStickerRecord(
                    id: ev.stickerID,
                    source: ev.source,
                    shortname: ev.shortname,
                    category: ev.category,
                    creatorID: ev.creatorID,
                    createTimeSeconds: UInt32(now),
                    clanID: ev.clanID,
                    logo: ev.logo,
                    clanName: ev.clanName,
                    mediaType: StickerMediaType.sticker.rawValue,
                    isForSale: false
                )
                stickers.insert(record, at: 0)
                hasChanges = true
            }
            stickers.removeAll { $0.id == 0 }
        case .stickerUpdated(let ev):
            if let idx = stickers.firstIndex(where: { $0.id == ev.stickerID }),
               !ev.shortname.isEmpty {
                stickers[idx].shortname = ev.shortname
                hasChanges = true
            }
        case .stickerDeleted(let ev):
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
        switch event {
        case .stickerCreated, .stickerUpdated:
            if #available(iOS 13.0, *) {
                scheduleStickerListNetworkSync()
            }
        default:
            break
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .mezonStickerListDidUpdate, object: nil)
        }
    }
}
