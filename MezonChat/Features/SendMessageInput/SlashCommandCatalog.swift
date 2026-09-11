import Foundation

@MainActor
final class SlashCommandCatalog {
    static let shared = SlashCommandCatalog()

    private struct Entry {
        let items: [Mezon_Api_QuickMenuAccess]
        let fetchedAt: Date
    }

    private static let freshnessInterval: TimeInterval = 5 * 60
    private static let failureRetryInterval: TimeInterval = 15

    private var entries: [Int64: Entry] = [:]
    private var lastAttemptAt: [Int64: Date] = [:]
    private var inflight: [Int64: Task<[Mezon_Api_QuickMenuAccess]?, Never>] = [:]

    func cached(channelId: Int64) -> [Mezon_Api_QuickMenuAccess]? {
        entries[channelId]?.items
    }

    func isFresh(channelId: Int64) -> Bool {
        guard let entry = entries[channelId] else { return false }
        return Date().timeIntervalSince(entry.fetchedAt) < Self.freshnessInterval
    }

    func load(channelId: Int64, context: AccountContext) async -> [Mezon_Api_QuickMenuAccess] {
        if isFresh(channelId: channelId), let entry = entries[channelId] {
            return entry.items
        }
        if let task = inflight[channelId] {
            return await task.value ?? entries[channelId]?.items ?? []
        }
        if let attempt = lastAttemptAt[channelId], Date().timeIntervalSince(attempt) < Self.failureRetryInterval {
            return entries[channelId]?.items ?? []
        }
        lastAttemptAt[channelId] = Date()
        let task = Task<[Mezon_Api_QuickMenuAccess]?, Never> {
            await Self.fetch(channelId: channelId, context: context)
        }
        inflight[channelId] = task
        let fetched = await task.value
        inflight[channelId] = nil
        guard let fetched else {
            return entries[channelId]?.items ?? []
        }
        entries[channelId] = Entry(items: fetched, fetchedAt: Date())
        return fetched
    }

    private static func fetch(channelId: Int64, context: AccountContext) async -> [Mezon_Api_QuickMenuAccess]? {
        guard let token = await context.getTokenPreferringCachedSkipSessionReadyWait() else { return nil }
        do {
            let items = try await MezonHTTPClient.shared.listQuickMenuAccess(
                channelId: channelId,
                menuType: MezonConstants.QuickMenuType.flashMessage.rawValue,
                token: token
            )
            return items.filter { !$0.menuName.isEmpty }
        } catch {
            return nil
        }
    }
}
