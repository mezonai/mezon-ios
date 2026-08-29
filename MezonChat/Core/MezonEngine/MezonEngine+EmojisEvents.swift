import Foundation

extension MezonEngine {
    private static var emojiListSyncHandle: CancelHandle?

    @available(iOS 13.0, *)
    func scheduleEmojiListNetworkSync(debounceSeconds: Double = 0.8) {
        Self.emojiListSyncHandle?.cancel()
        let task = Task { @MainActor [weak self] in
            if debounceSeconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounceSeconds * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            await self.syncEmojiListFromNetwork()
        }
        Self.emojiListSyncHandle = CancelHandle { task.cancel() }
    }

    @available(iOS 13.0, *)
    func syncEmojiListFromNetwork() async {
        guard let session = SessionStore.load(),
              !session.token.isEmpty,
              !session.isExpired else { return }
        do {
            let res = try await account.network.getListEmojisByUserId(token: session.token)
            let rows = res.emojiList.map { $0.toCachedRecord() }.deduplicatedByEmojiId()
            let now = Date().timeIntervalSince1970
            let cache = MediaPanelEmojiListCache(fetchedAt: now, emojis: rows)
            account.postbox.setSetting(key: MediaPanelPostboxKeys.emojiListByUser, value: cache)
            postEmojiListDidUpdate()
        } catch {
        }
    }

    /// Mirrors web `oneventemoji`: create / rename / delete clan emoji in postbox cache.
    func handleEmojiEvent(_ event: Mezon_Realtime_EventEmoji) {
        let postbox = account.postbox
        let now = Date().timeIntervalSince1970
        let currentUserId = Int64(SessionStore.load()?.userId ?? "") ?? 0

        var cache = postbox.getSetting(key: MediaPanelPostboxKeys.emojiListByUser, type: MediaPanelEmojiListCache.self)
            ?? MediaPanelEmojiListCache(fetchedAt: now, emojis: [])

        var emojis = cache.emojis
        var hasChanges = false

        switch MediaPanelRealtimeAction(rawValue: event.action) {
        case .created:
            let src = resolvedEmojiSrc(from: event, currentUserId: currentUserId)
            let category = !event.category.isEmpty ? event.category : event.clanName
            let record = CachedClanEmojiRecord(
                id: event.id,
                src: src,
                shortname: event.shortName,
                category: category,
                creatorID: event.userID,
                clanID: event.clanID,
                logo: event.logo,
                clanName: event.clanName,
                isForSale: event.isForSale
            )
            if let idx = emojis.firstIndex(where: { $0.id == event.id }) {
                emojis[idx] = mergeEmojiSocketRecord(existing: emojis[idx], incoming: record, unlockedSrc: src)
            } else {
                emojis.insert(record, at: 0)
            }
            hasChanges = true
        case .update:
            if let idx = emojis.firstIndex(where: { $0.id == event.id }) {
                if !event.shortName.isEmpty {
                    emojis[idx].shortname = event.shortName
                }
                let src = resolvedEmojiSrc(from: event, currentUserId: currentUserId)
                if !src.isEmpty {
                    emojis[idx].src = src
                }
                hasChanges = true
            }
        case .delete:
            if emojis.contains(where: { $0.id == event.id }) {
                emojis.removeAll { $0.id == event.id }
                hasChanges = true
            }
        default:
            break
        }

        guard hasChanges else { return }

        cache.fetchedAt = now
        cache.emojis = emojis.filter { $0.id != 0 }.deduplicatedByEmojiId()
        postbox.setSetting(key: MediaPanelPostboxKeys.emojiListByUser, value: cache)
        postEmojiListDidUpdate()
    }

    private func resolvedEmojiSrc(from event: Mezon_Realtime_EventEmoji, currentUserId: Int64) -> String {
        if event.userID == currentUserId || !event.isForSale {
            return event.source
        }
        return ""
    }

    private func mergeEmojiSocketRecord(
        existing: CachedClanEmojiRecord,
        incoming: CachedClanEmojiRecord,
        unlockedSrc: String
    ) -> CachedClanEmojiRecord {
        var merged = existing
        if incoming.id != 0 { merged.id = incoming.id }
        if !unlockedSrc.isEmpty {
            merged.src = unlockedSrc
        } else if !incoming.src.isEmpty {
            merged.src = incoming.src
        }
        if !incoming.shortname.isEmpty { merged.shortname = incoming.shortname }
        if !incoming.category.isEmpty { merged.category = incoming.category }
        if incoming.creatorID != 0 { merged.creatorID = incoming.creatorID }
        if incoming.clanID != 0 { merged.clanID = incoming.clanID }
        if !incoming.logo.isEmpty { merged.logo = incoming.logo }
        if !incoming.clanName.isEmpty { merged.clanName = incoming.clanName }
        merged.isForSale = incoming.isForSale
        return merged
    }

    private func postEmojiListDidUpdate() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .mezonEmojiListDidUpdate, object: nil)
        }
    }
}
