import Foundation

final class EmojisRepository {
    static let maxSlots = 250

    private let context: AccountContext

    init(context: AccountContext) {
        self.context = context
    }

    func emojis(clanId: Int64) -> [CachedClanEmojiRecord] {
        guard let list = context.engine.data.cachedEmojiList(clanId: clanId) else {
            return []
        }
        return list.emojis
            .filter { $0.clanID == clanId }
            .sorted { $0.id > $1.id }
    }

    func emojiCount(clanId: Int64) -> Int {
        emojis(clanId: clanId).count
    }

    func isAtUploadLimit(clanId: Int64) -> Bool {
        emojiCount(clanId: clanId) >= Self.maxSlots
    }

    @available(iOS 13.0, *)
    @MainActor
    func updateEmoji(id: Int64, clanId: Int64, shortname: String) async throws {
        var req = Mezon_Api_ClanEmojiUpdateRequest()
        req.id = id
        req.clanID = clanId
        req.shortname = shortname
        guard let token = await context.getToken() else {
            Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
            return
        }
        let updated = try await context.account.network.updateClanEmoji(request: req, token: token)
        mutateEmojiCache { emojis in
            guard let idx = emojis.firstIndex(where: { $0.id == id }) else { return }
            emojis[idx].shortname = updated.shortname.isEmpty ? shortname : updated.shortname
        }
    }

    @available(iOS 13.0, *)
    @MainActor
    func deleteEmoji(id: Int64, clanId: Int64, shortname: String) async throws {
        var req = Mezon_Api_ClanEmojiDeleteRequest()
        req.id = id
        req.clanID = clanId
        req.emojiLabel = shortname
        guard let token = await context.getToken() else {
            Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
            return
        }
        try await context.account.network.deleteClanEmoji(request: req, token: token)
        mutateEmojiCache { emojis in
            emojis.removeAll { $0.id == id }
        }
    }

    @available(iOS 13.0, *)
    func addEmoji(
        clanId: Int64,
        source: String,
        shortname: String,
        category: String,
        isForSale: Bool = false,
        id: Int64? = nil
    ) async throws {
        var req = Mezon_Api_ClanEmojiCreateRequest()
        req.clanID = clanId
        req.source = source
        req.shortname = shortname
        req.category = category
        req.isForSale = isForSale
        req.id = id ?? Int64(Date().timeIntervalSince1970 * 1000)
        guard let token = await context.getToken() else {
            Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
            return
        }
        let created = try await context.account.network.createClanEmoji(request: req, token: token)
        let record: CachedClanEmojiRecord
        if Self.isEmptyApiEmojiResponse(created) {
            record = recordFromAddRequest(
                req: req,
                source: source,
                shortname: shortname,
                category: category,
                isForSale: isForSale
            )
        } else {
            var recordFromApi = created.toCachedRecord()
            recordFromApi.isForSale = isForSale
            record = recordFromApi
        }
        mutateEmojiCache { emojis in
            Self.removeInvalidPlaceholderEmojis(&emojis)
            if let idx = emojis.firstIndex(where: { $0.id == req.id }) {
                emojis[idx] = Self.mergeEmojiRecord(
                    existing: emojis[idx],
                    updated: record,
                    fallbackShortname: shortname
                )
            } else if let idx = emojis.firstIndex(where: {
                $0.shortname == shortname && $0.clanID == clanId
            }) {
                emojis[idx] = Self.mergeEmojiRecord(
                    existing: emojis[idx],
                    updated: record,
                    fallbackShortname: shortname
                )
            } else {
                emojis.insert(record, at: 0)
            }
        }
    }

    private static func mergeEmojiRecord(
        existing: CachedClanEmojiRecord,
        updated: CachedClanEmojiRecord,
        fallbackShortname: String
    ) -> CachedClanEmojiRecord {
        var merged = existing
        if updated.id != 0 { merged.id = updated.id }
        if !updated.src.isEmpty { merged.src = updated.src }
        if !updated.shortname.isEmpty {
            merged.shortname = updated.shortname
        } else {
            merged.shortname = fallbackShortname
        }
        if !updated.category.isEmpty { merged.category = updated.category }
        if updated.creatorID != 0 { merged.creatorID = updated.creatorID }
        if updated.clanID != 0 { merged.clanID = updated.clanID }
        if !updated.logo.isEmpty { merged.logo = updated.logo }
        if !updated.clanName.isEmpty { merged.clanName = updated.clanName }
        merged.isForSale = updated.isForSale || existing.isForSale
        return merged
    }

    private func recordFromAddRequest(
        req: Mezon_Api_ClanEmojiCreateRequest,
        source: String,
        shortname: String,
        category: String,
        isForSale: Bool
    ) -> CachedClanEmojiRecord {
        let creatorID = Int64(context.currentUser?.id ?? "") ?? 0
        return CachedClanEmojiRecord(
            id: req.id,
            src: source,
            shortname: shortname,
            category: category,
            creatorID: creatorID,
            clanID: req.clanID,
            logo: "",
            clanName: "",
            isForSale: isForSale
        )
    }

    private static func isEmptyApiEmojiResponse(_ emoji: Mezon_Api_ClanEmoji) -> Bool {
        emoji.id == 0 && emoji.shortname.isEmpty && emoji.src.isEmpty
    }

    private static func removeInvalidPlaceholderEmojis(_ emojis: inout [CachedClanEmojiRecord]) {
        emojis.removeAll { $0.id == 0 }
    }

    private func mutateEmojiCache(_ mutate: (inout [CachedClanEmojiRecord]) -> Void) {
        let postbox = context.engine.account.postbox
        var cache = postbox.getSetting(key: MediaPanelPostboxKeys.emojiListByUser, type: MediaPanelEmojiListCache.self)
            ?? MediaPanelEmojiListCache(fetchedAt: Date().timeIntervalSince1970, emojis: [])
        mutate(&cache.emojis)
        Self.removeInvalidPlaceholderEmojis(&cache.emojis)
        cache.emojis = cache.emojis.deduplicatedByEmojiId()
        cache.fetchedAt = Date().timeIntervalSince1970
        postbox.setSetting(key: MediaPanelPostboxKeys.emojiListByUser, value: cache)
        NotificationCenter.default.post(name: .mezonEmojiListDidUpdate, object: nil)
    }
}
