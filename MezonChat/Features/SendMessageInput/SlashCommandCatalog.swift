import Foundation

@MainActor
final class SlashCommandCatalog {
    static let shared = SlashCommandCatalog()

    typealias MenuType = MezonConstants.QuickMenuType

    private struct Key: Hashable {
        let channelId: Int64
        let menuType: Int32
    }

    private struct Entry {
        let items: [Mezon_Api_QuickMenuAccess]
        let fetchedAt: Date
    }

    private static let freshnessInterval: TimeInterval = 5 * 60
    private static let failureRetryInterval: TimeInterval = 15

    private var entries: [Key: Entry] = [:]
    private var lastAttemptAt: [Key: Date] = [:]
    private var inflight: [Key: Task<[Mezon_Api_QuickMenuAccess]?, Never>] = [:]
    private var revisions: [Key: Int] = [:]

    func cached(channelId: Int64, menuType: MenuType = .flashMessage) -> [Mezon_Api_QuickMenuAccess]? {
        entries[Key(channelId: channelId, menuType: menuType.rawValue)]?.items
    }

    func isFresh(channelId: Int64, menuType: MenuType = .flashMessage) -> Bool {
        guard let entry = entries[Key(channelId: channelId, menuType: menuType.rawValue)] else { return false }
        return Date().timeIntervalSince(entry.fetchedAt) < Self.freshnessInterval
    }

    func replace(channelId: Int64, menuType: MenuType = .flashMessage, items: [Mezon_Api_QuickMenuAccess]) {
        let key = Key(channelId: channelId, menuType: menuType.rawValue)
        revisions[key, default: 0] += 1
        entries[key] = Entry(items: items.filter { !$0.menuName.isEmpty }, fetchedAt: Date())
        lastAttemptAt[key] = nil
    }

    func load(channelId: Int64, menuType: MenuType = .flashMessage, context: AccountContext) async -> [Mezon_Api_QuickMenuAccess] {
        let key = Key(channelId: channelId, menuType: menuType.rawValue)
        if isFresh(channelId: channelId, menuType: menuType), let entry = entries[key] {
            return entry.items
        }
        if let task = inflight[key] {
            return await task.value ?? entries[key]?.items ?? []
        }
        if let attempt = lastAttemptAt[key], Date().timeIntervalSince(attempt) < Self.failureRetryInterval {
            return entries[key]?.items ?? []
        }
        lastAttemptAt[key] = Date()
        let startRevision = revisions[key, default: 0]
        let task = Task<[Mezon_Api_QuickMenuAccess]?, Never> {
            await Self.fetch(channelId: channelId, menuType: menuType, context: context)
        }
        inflight[key] = task
        let fetched = await task.value
        inflight[key] = nil
        guard let fetched else {
            return entries[key]?.items ?? []
        }
        guard revisions[key, default: 0] == startRevision else {
            return entries[key]?.items ?? fetched
        }
        entries[key] = Entry(items: fetched, fetchedAt: Date())
        return fetched
    }

    private static func fetch(channelId: Int64, menuType: MenuType, context: AccountContext) async -> [Mezon_Api_QuickMenuAccess]? {
        guard let token = await context.getTokenPreferringCachedSkipSessionReadyWait() else { return nil }
        do {
            let items = try await MezonHTTPClient.shared.listQuickMenuAccess(
                channelId: channelId,
                menuType: menuType.rawValue,
                token: token
            )
            return items.filter { !$0.menuName.isEmpty }
        } catch {
            return nil
        }
    }
}
