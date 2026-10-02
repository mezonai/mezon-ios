import Foundation

enum ClanStickerNameValidator {
    static let minLength = 3
    static let maxLength = 64
    static let previewMaxLength = maxLength - 2
    private static let pattern = #"^[a-zA-Z0-9_-]+$"#

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValid(_ name: String) -> Bool {
        let trimmed = normalized(name)
        guard trimmed.count >= minLength, trimmed.count <= maxLength else { return false }
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    static func isValidForPreview(_ name: String) -> Bool {
        let trimmed = normalized(name)
        guard trimmed.count >= minLength, trimmed.count <= previewMaxLength else { return false }
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}

@MainActor
final class StickersRepository {
    static let maxSlots = 250

    private let context: AccountContext
    private let mediaType: StickerMediaType

    init(context: AccountContext, mediaType: StickerMediaType = .sticker) {
        self.context = context
        self.mediaType = mediaType
    }

    func stickers(clanId: Int64) -> [CachedClanStickerRecord] {
        guard let list = context.engine.data.cachedStickerList(clanId: clanId) else {
            return []
        }
        return list.stickers
            .filter { $0.clanID == clanId && $0.mediaType == mediaType.rawValue }
            .sorted { $0.createTimeSeconds > $1.createTimeSeconds }
    }

    func stickerCount(clanId: Int64) -> Int {
        stickers(clanId: clanId).count
    }

    func isAtUploadLimit(clanId: Int64) -> Bool {
        stickerCount(clanId: clanId) >= Self.maxSlots
    }

    func updateSticker(id: Int64, clanId: Int64, source: String, shortname: String, category: String) async throws {
        var req = Mezon_Api_ClanStickerUpdateByIdRequest()
        req.id = id
        req.clanID = clanId
        req.source = source
        req.shortname = shortname
        req.category = category
        guard let token = await context.getToken() else {
            Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
            return
        }
        let updated = try await context.account.network.updateClanSticker(request: req, token: token)
        mutateStickerCache { stickers in
            guard let idx = stickers.firstIndex(where: { $0.id == id }) else { return }
            stickers[idx] = Self.mergeStickerRecord(
                existing: stickers[idx],
                updated: updated.toCachedRecord(),
                fallbackShortname: shortname
            )
        }
    }

    private static func mergeStickerRecord(
        existing: CachedClanStickerRecord,
        updated: CachedClanStickerRecord,
        fallbackShortname: String
    ) -> CachedClanStickerRecord {
        var merged = existing
        if updated.id != 0 { merged.id = updated.id }
        if !updated.source.isEmpty { merged.source = updated.source }
        if !updated.shortname.isEmpty {
            merged.shortname = updated.shortname
        } else {
            merged.shortname = fallbackShortname
        }
        if !updated.category.isEmpty { merged.category = updated.category }
        if updated.creatorID != 0 { merged.creatorID = updated.creatorID }
        if updated.createTimeSeconds != 0 { merged.createTimeSeconds = updated.createTimeSeconds }
        if updated.clanID != 0 { merged.clanID = updated.clanID }
        if !updated.logo.isEmpty { merged.logo = updated.logo }
        if !updated.clanName.isEmpty { merged.clanName = updated.clanName }
        if updated.mediaType != 0 { merged.mediaType = updated.mediaType }
        merged.isForSale = updated.isForSale || existing.isForSale
        return merged
    }

    func deleteSticker(id: Int64, clanId: Int64, shortname: String) async throws {
        var req = Mezon_Api_ClanStickerDeleteRequest()
        req.id = id
        req.clanID = clanId
        req.stickerLabel = shortname
        guard let token = await context.getToken() else {
            Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
            return
        }
        try await context.account.network.deleteClanSticker(request: req, token: token)
        mutateStickerCache { stickers in
            stickers.removeAll { $0.id == id }
        }
    }

    func addSticker(
        clanId: Int64,
        source: String,
        shortname: String,
        category: String,
        isForSale: Bool = false,
        id: Int64? = nil
    ) async throws {
        var req = Mezon_Api_ClanStickerAddRequest()
        req.clanID = clanId
        req.source = source
        req.shortname = shortname
        req.category = category
        req.mediaType = mediaType.rawValue
        req.isForSale = isForSale
        req.id = id ?? Int64(Date().timeIntervalSince1970 * 1000)
        guard let token = await context.getToken() else {
            Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
            return
        }
        let created = try await context.account.network.addClanSticker(request: req, token: token)
        let record: CachedClanStickerRecord
        if Self.isEmptyApiStickerResponse(created) {
            record = recordFromAddRequest(
                req: req,
                source: source,
                shortname: shortname,
                category: category,
                isForSale: isForSale
            )
        } else {
            var parsed = created.toCachedRecord()
            parsed.mediaType = mediaType.rawValue
            parsed.isForSale = isForSale
            record = parsed
        }
        mutateStickerCache { stickers in
            Self.removeInvalidPlaceholderStickers(&stickers)
            if let idx = stickers.firstIndex(where: { $0.id == req.id }) {
                stickers[idx] = Self.mergeStickerRecord(
                    existing: stickers[idx],
                    updated: record,
                    fallbackShortname: shortname
                )
            } else if let idx = stickers.firstIndex(where: {
                $0.shortname == shortname
                    && $0.clanID == clanId
                    && $0.mediaType == mediaType.rawValue
            }) {
                stickers[idx] = Self.mergeStickerRecord(
                    existing: stickers[idx],
                    updated: record,
                    fallbackShortname: shortname
                )
            } else {
                stickers.insert(record, at: 0)
            }
        }
    }

    private func recordFromAddRequest(
        req: Mezon_Api_ClanStickerAddRequest,
        source: String,
        shortname: String,
        category: String,
        isForSale: Bool
    ) -> CachedClanStickerRecord {
        let creatorID = Int64(context.currentUser?.id ?? "") ?? 0
        return CachedClanStickerRecord(
            id: req.id,
            source: source,
            shortname: shortname,
            category: category,
            creatorID: creatorID,
            createTimeSeconds: UInt32(Date().timeIntervalSince1970),
            clanID: req.clanID,
            logo: "",
            clanName: "",
            mediaType: req.mediaType,
            isForSale: isForSale
        )
    }

    private static func isEmptyApiStickerResponse(_ sticker: Mezon_Api_ClanSticker) -> Bool {
        sticker.id == 0 && sticker.shortname.isEmpty && sticker.source.isEmpty
    }

    private static func removeInvalidPlaceholderStickers(_ stickers: inout [CachedClanStickerRecord]) {
        stickers.removeAll { $0.id == 0 }
    }

    private func mutateStickerCache(_ mutate: (inout [CachedClanStickerRecord]) -> Void) {
        let postbox = context.engine.account.postbox
        var cache = postbox.getSetting(key: MediaPanelPostboxKeys.stickerListByUser, type: MediaPanelStickerListCache.self)
            ?? MediaPanelStickerListCache(fetchedAt: Date().timeIntervalSince1970, stickers: [])
        mutate(&cache.stickers)
        Self.removeInvalidPlaceholderStickers(&cache.stickers)
        cache.fetchedAt = Date().timeIntervalSince1970
        postbox.setSetting(key: MediaPanelPostboxKeys.stickerListByUser, value: cache)
        NotificationCenter.default.post(name: .mezonStickerListDidUpdate, object: nil)
    }
}
