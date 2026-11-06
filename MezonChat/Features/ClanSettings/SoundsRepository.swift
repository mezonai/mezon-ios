import Foundation

@MainActor
final class SoundsRepository {
    private let context: AccountContext

    init(context: AccountContext) {
        self.context = context
    }

    func sounds(clanId: Int64) -> [CachedClanStickerRecord] {
        (context.engine.data.cachedStickerList(clanId: clanId)?.stickers ?? [])
            .filter { $0.clanID == clanId && $0.mediaType == StickerMediaType.audio.rawValue }
            .sorted { $0.createTimeSeconds > $1.createTimeSeconds }
    }

    func refresh() async throws {
        let token = try await requireToken()
        try await context.engine.refreshStickerListFromNetwork(token: token, allowEmpty: true)
    }

    func create(clanId: Int64, data: Data, fileExtension: String, name: String) async throws {
        let token = try await requireToken()
        let uploadId = Int64(Date().timeIntervalSince1970 * 1000)
        let contentType = fileExtension == "wav" ? "audio/wav" : "audio/mpeg"
        let upload = try await context.account.network.uploadAttachmentFile(
            filename: "sounds/\(uploadId).\(fileExtension)",
            filetype: contentType, size: data.count, width: 0, height: 0, token: token
        )
        guard let soundId = Self.soundId(fromUploadFilename: upload.filename) else {
            throw MezonError.invalidResponse
        }
        try await context.account.network.uploadToMinIO(url: upload.url, data: data, contentType: contentType)
        let source = try MezonConfig.attachmentViewURL(
            typeCdn: upload.typeCdn, fallback: MezonConfig.cloudflareCdnURL, filename: upload.filename
        )
        var request = Mezon_Api_ClanStickerAddRequest()
        request.id = soundId
        request.clanID = clanId
        request.source = source
        request.shortname = name
        request.category = "Among Us"
        request.mediaType = StickerMediaType.audio.rawValue
        request.isForSale = false
        let response = try await context.account.network.addClanSticker(request: request, token: token)
        let clan = context.account.postbox.read { $0.getClan(id: clanId) }
        let record = CachedClanStickerRecord(
            id: response.id == 0 ? request.id : response.id,
            source: source, shortname: name, category: request.category,
            creatorID: Int64(context.currentUser?.id ?? "") ?? 0,
            createTimeSeconds: UInt32(Date().timeIntervalSince1970),
            clanID: clanId, logo: clan?.icon ?? "", clanName: clan?.name ?? "",
            mediaType: StickerMediaType.audio.rawValue, isForSale: false
        )
        mutate { records in
            guard !records.contains(where: { $0.id == record.id }) else { return }
            records.insert(record, at: 0)
        }
        context.engine.scheduleStickerListNetworkSync()
    }

    static func soundId(fromUploadFilename filename: String) -> Int64? {
        let file = (filename as NSString).lastPathComponent as NSString
        guard !file.pathExtension.isEmpty else { return nil }
        let prefix = file.deletingPathExtension.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return Int64(prefix)
    }

    func rename(_ sound: CachedClanStickerRecord, name: String) async throws {
        let token = try await requireToken()
        var request = Mezon_Api_ClanStickerUpdateByIdRequest()
        request.id = sound.id
        request.clanID = sound.clanID
        request.source = sound.source
        request.shortname = name
        request.category = sound.category
        _ = try await context.account.network.updateClanSticker(request: request, token: token)
        mutate { records in
            guard let index = records.firstIndex(where: { $0.id == sound.id }) else { return }
            records[index].shortname = name
        }
    }

    func delete(_ sound: CachedClanStickerRecord) async throws {
        let token = try await requireToken()
        var request = Mezon_Api_ClanStickerDeleteRequest()
        request.id = sound.id
        request.clanID = sound.clanID
        request.stickerLabel = sound.shortname
        try await context.account.network.deleteClanSticker(request: request, token: token)
        mutate { $0.removeAll { $0.id == sound.id } }
    }

    private func requireToken() async throws -> String {
        guard let token = await context.getToken() else {
            throw NSError(domain: "ClanSounds", code: 401, userInfo: [
                NSLocalizedDescriptionKey: L(L10n.ClanInviteSheet.sessionNotFound)
            ])
        }
        return token
    }

    private func mutate(_ update: (inout [CachedClanStickerRecord]) -> Void) {
        var records = context.account.postbox.getSetting(
            key: MediaPanelPostboxKeys.stickerListByUser, type: MediaPanelStickerListCache.self
        )?.stickers ?? []
        update(&records)
        save(records)
    }

    private func save(_ records: [CachedClanStickerRecord]) {
        context.account.postbox.setSetting(
            key: MediaPanelPostboxKeys.stickerListByUser,
            value: MediaPanelStickerListCache(fetchedAt: Date().timeIntervalSince1970, stickers: records)
        )
        NotificationCenter.default.post(name: .mezonStickerListDidUpdate, object: nil)
    }
}
