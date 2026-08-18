import UIKit
import QuartzCore
import SwiftProtobuf

struct ChannelListState: Equatable {
    var categories: [ChannelCategory]
    var allChannels: [Mezon_Api_ChannelDescription] = []
    var selectedChannelId: Int64?
    var isLoading: Bool
    var errorMessage: String?
    var voiceUsersByChannel: [Int64: [String]] = [:]

    static let empty = ChannelListState(
        categories: [], allChannels: [], selectedChannelId: nil,
        isLoading: false, errorMessage: nil)

    static func == (lhs: ChannelListState, rhs: ChannelListState) -> Bool {
        guard lhs.isLoading == rhs.isLoading
            && lhs.selectedChannelId == rhs.selectedChannelId
            && lhs.errorMessage == rhs.errorMessage
            && lhs.categories.count == rhs.categories.count
            && lhs.allChannels.count == rhs.allChannels.count
            && lhs.voiceUsersByChannel == rhs.voiceUsersByChannel
            && categoriesChannelStructureEqual(lhs.categories, rhs.categories)
        else { return false }
        return zip(lhs.allChannels, rhs.allChannels).allSatisfy {
            $0.channelID == $1.channelID
            && $0.countMessUnread == $1.countMessUnread
            && $0.lastSentMessage.timestampSeconds == $1.lastSentMessage.timestampSeconds
            && $0.lastSeenMessage.timestampSeconds == $1.lastSeenMessage.timestampSeconds
            && $0.channelLabel == $1.channelLabel
            && $0.topic == $1.topic
        }
    }
}

func channelIdsInCategory(_ cat: ChannelCategory) -> [Int64] {
    var ids: [Int64] = []
    if let fav = cat.favoriteFlatChannels {
        ids.append(contentsOf: fav.map(\.channelID))
    }
    ids.append(contentsOf: cat.channels.map(\.channelID))
    for key in cat.orderedThreadChildren.keys.sorted() {
        if let threads = cat.orderedThreadChildren[key] {
            ids.append(contentsOf: threads.map(\.channelID))
        }
    }
    return ids
}

func categoriesChannelStructureEqual(_ lhs: [ChannelCategory], _ rhs: [ChannelCategory]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).allSatisfy { l, r in
        l.id == r.id
            && l.isCollapsed == r.isCollapsed
            && l.name == r.name
            && channelIdsInCategory(l) == channelIdsInCategory(r)
    }
}

func categoriesChannelTreeEqual(_ lhs: [ChannelCategory], _ rhs: [ChannelCategory]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).allSatisfy { l, r in
        l.id == r.id
            && l.isCollapsed == r.isCollapsed
            && channelIdsInCategory(l) == channelIdsInCategory(r)
    }
}

private func filterCategoriesToKnownChannels(
    _ cats: [ChannelCategory],
    channels: [Mezon_Api_ChannelDescription]
) -> [ChannelCategory] {
    let byId = Dictionary(channels.map { ($0.channelID, $0) }, uniquingKeysWith: { _, new in new })
    return cats.compactMap { cat in
        if cat.id == ChannelCategory.favoritesCategoryId {
            guard let fav = cat.favoriteFlatChannels else { return nil }
            let filtered = fav.compactMap { byId[$0.channelID] }
            guard !filtered.isEmpty else { return nil }
            return ChannelCategory(
                id: cat.id,
                name: cat.name,
                isCollapsed: cat.isCollapsed,
                channels: [],
                orderedThreadChildren: [:],
                favoriteFlatChannels: filtered
            )
        }
        let parents = cat.channels.compactMap { byId[$0.channelID] }
        let parentIds = Set(parents.map(\.channelID))
        var threads: [Int64: [Mezon_Api_ChannelDescription]] = [:]
        for (parentId, arr) in cat.orderedThreadChildren {
            guard parentIds.contains(parentId) else { continue }
            let filtered = arr.compactMap { byId[$0.channelID] }
            if !filtered.isEmpty {
                threads[parentId] = filtered
            }
        }
        return ChannelCategory(
            id: cat.id,
            name: cat.name,
            isCollapsed: cat.isCollapsed,
            channels: parents,
            orderedThreadChildren: threads,
            favoriteFlatChannels: nil
        )
    }
}

enum ChannelFetchError: Error {
    case noSession
    case network(Error)

    var localizedDescription: String {
        switch self {
        case .noSession: return "No active session. Please log in."
        case .network(let e): return e.localizedDescription
        }
    }
}

struct ChannelCategory {
    let id: Int64
    let name: String
    var isCollapsed: Bool = false
    var channels: [Mezon_Api_ChannelDescription]

    var orderedThreadChildren: [Int64: [Mezon_Api_ChannelDescription]] = [:]

    var favoriteFlatChannels: [Mezon_Api_ChannelDescription]? = nil

    static let favoritesCategoryId: Int64 = Int64.min
}

enum ChannelListRow {
    case channel(Mezon_Api_ChannelDescription, isInFavoriteSection: Bool)
    case thread(Mezon_Api_ChannelDescription, isLast: Bool, isInFavoriteSection: Bool)
    case voiceMembersCollapsed(Mezon_Api_ChannelDescription, userIds: [String])
    case voiceMemberExpanded(Mezon_Api_ChannelDescription, userId: String)

    var channelDesc: Mezon_Api_ChannelDescription {
        switch self {
        case .channel(let ch, _): return ch
        case .thread(let ch, _, _): return ch
        case .voiceMembersCollapsed(let ch, _): return ch
        case .voiceMemberExpanded(let ch, _): return ch
        }
    }
}

enum ChannelType: Int32 {
    case text = 1
    case voice = 10
    case group = 3
    case thread = 4
    case streaming = 6
    case app = 8
    case forum = 11
    case unknown = 0

    var icon: String {
        switch self {
        case .text: return "Channel/channel"
        case .voice: return "Chat/SpeakerIcon"
        case .thread: return "Channel/ChevronRight"
        case .streaming: return "Channel/channelStream"
        case .app: return "Channel/channelApp"
        case .forum: return "Channel/channel"
        default: return "Channel/channel"
        }
    }

    var isSystemImage: Bool { true }
}

private func localizedFavoriteChannelsCategoryTitle() -> String {
    NSLocalizedString("favorite_channel_section", tableName: nil, bundle: .main, value: "Favorite channels", comment: "Channel list section header")
}

private func prioritizeChannels(_ channels: [Mezon_Api_ChannelDescription]) -> [Mezon_Api_ChannelDescription] {
    channels
}

private func normalizedCategoryDescs(
    _ categoryDescs: [Mezon_Api_CategoryDesc],
    channels: [Mezon_Api_ChannelDescription]
) -> [Mezon_Api_CategoryDesc] {
    guard !categoryDescs.isEmpty else { return inferredCategoryDescs(from: channels) }
    var result = categoryDescs.enumerated().sorted { lhs, rhs in
        if lhs.element.categoryOrder != rhs.element.categoryOrder {
            return lhs.element.categoryOrder < rhs.element.categoryOrder
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
    let knownIds = Set(categoryDescs.map(\.categoryID))
    for inferred in inferredCategoryDescs(from: channels) where !knownIds.contains(inferred.categoryID) {
        result.append(inferred)
    }
    return result
}

private func sortChannelsForCategory(_ channels: [Mezon_Api_ChannelDescription], categoryId: Int64) -> [Mezon_Api_ChannelDescription] {
    var sortedChannels: [Mezon_Api_ChannelDescription] = []

    let parents = channels
        .filter { $0.parentID == 0 && $0.categoryID == categoryId }
        .sorted { String($0.channelID) < String($1.channelID) }
    let threads = channels.filter { $0.parentID != 0 }

    var threadsByParent: [Int64: [Mezon_Api_ChannelDescription]] = [:]
    for thread in threads {
        threadsByParent[thread.parentID, default: []].append(thread)
    }

    for parent in parents {
        sortedChannels.append(parent)
        if let childThreads = threadsByParent[parent.channelID] {
            sortedChannels.append(contentsOf: childThreads)
        }
    }

    return sortedChannels
}

private func inferredCategoryDescs(from channels: [Mezon_Api_ChannelDescription]) -> [Mezon_Api_CategoryDesc] {
    var seen = Set<Int64>()
    var result: [Mezon_Api_CategoryDesc] = []
    for ch in channels {
        let id = ch.categoryID
        guard id != 0 else { continue }
        if let idx = result.firstIndex(where: { $0.categoryID == id }) {
            if result[idx].categoryName.isEmpty, !ch.categoryName.isEmpty {
                result[idx].categoryName = ch.categoryName
            }
            continue
        }
        guard !seen.contains(id) else { continue }
        seen.insert(id)
        var c = Mezon_Api_CategoryDesc()
        c.categoryID = id
        c.categoryName = ch.categoryName
        c.clanID = ch.clanID
        result.append(c)
    }
    if result.isEmpty {
        for ch in channels where ch.parentID == 0 {
            let id = ch.categoryID
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            var c = Mezon_Api_CategoryDesc()
            c.categoryID = id
            c.categoryName = ch.categoryName
            c.clanID = ch.clanID
            result.append(c)
        }
    }
    return result
}

private func categoryNameLookup(
    from channels: [Mezon_Api_ChannelDescription],
    categoryDescs: [Mezon_Api_CategoryDesc]
) -> [Int64: String] {
    var names: [Int64: String] = [:]
    for d in categoryDescs where !d.categoryName.isEmpty {
        names[d.categoryID] = d.categoryName
    }
    for ch in channels where ch.categoryID != 0 && !ch.categoryName.isEmpty {
        if names[ch.categoryID]?.isEmpty != false {
            names[ch.categoryID] = ch.categoryName
        }
    }
    return names
}

private func enrichCategoryNames(
    _ cats: [ChannelCategory],
    channels: [Mezon_Api_ChannelDescription],
    categoryDescs: [Mezon_Api_CategoryDesc]
) -> [ChannelCategory] {
    let lookup = categoryNameLookup(from: channels, categoryDescs: categoryDescs)
    guard !lookup.isEmpty else { return cats }
    return cats.map { cat in
        guard cat.id != ChannelCategory.favoritesCategoryId else { return cat }
        if !cat.name.isEmpty { return cat }
        guard let name = lookup[cat.id], !name.isEmpty else { return cat }
        return ChannelCategory(
            id: cat.id,
            name: name,
            isCollapsed: cat.isCollapsed,
            channels: cat.channels,
            orderedThreadChildren: cat.orderedThreadChildren,
            favoriteFlatChannels: cat.favoriteFlatChannels
        )
    }
}

private func overlayCategoryNames(preferred: [ChannelCategory], onto target: [ChannelCategory]) -> [ChannelCategory] {
    let byId = Dictionary(preferred.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
    return target.map { cat in
        guard cat.id != ChannelCategory.favoritesCategoryId else { return cat }
        if !cat.name.isEmpty { return cat }
        guard let src = byId[cat.id], !src.name.isEmpty else { return cat }
        return ChannelCategory(
            id: cat.id,
            name: src.name,
            isCollapsed: cat.isCollapsed,
            channels: cat.channels,
            orderedThreadChildren: cat.orderedThreadChildren,
            favoriteFlatChannels: cat.favoriteFlatChannels
        )
    }
}

private let voiceChannelTypesForCategoryRepair: Set<Int32> = [
    MezonConstants.ChannelType.mezonVoice.rawValue,
    MezonConstants.ChannelType.streaming.rawValue,
    MezonConstants.ChannelType.app.rawValue,
]

private func categoryDescIdMatchingName(_ descs: [Mezon_Api_CategoryDesc], keyword: String) -> Int64? {
    descs.first(where: { $0.categoryName.localizedCaseInsensitiveContains(keyword) })?.categoryID
}

private func inferCategoryId(
    for channel: Mezon_Api_ChannelDescription,
    categoryDescs: [Mezon_Api_CategoryDesc]
) -> Int64? {
    guard !categoryDescs.isEmpty else { return nil }
    if voiceChannelTypesForCategoryRepair.contains(channel.type),
       let id = categoryDescIdMatchingName(categoryDescs, keyword: "voice") {
        return id
    }
    if channel.channelPrivate == 1,
       let id = categoryDescIdMatchingName(categoryDescs, keyword: "private") {
        return id
    }
    if let id = categoryDescIdMatchingName(categoryDescs, keyword: "public") {
        return id
    }
    return categoryDescs.sorted(by: { $0.categoryOrder < $1.categoryOrder }).first?.categoryID
}

private func channelsMissingCategoryIds(_ channels: [Mezon_Api_ChannelDescription]) -> Bool {
    let topLevel = channels.filter { $0.parentID == 0 }
    guard !topLevel.isEmpty else { return false }
    return topLevel.allSatisfy { $0.categoryID == 0 }
}

private func categoryPlacementFromSnapshot(_ cats: [ChannelCategory]) -> [Int64: (categoryId: Int64, categoryName: String)] {
    var map: [Int64: (Int64, String)] = [:]
    for cat in cats where cat.id != 0 && cat.id != ChannelCategory.favoritesCategoryId {
        let name = cat.name
        for ch in cat.channels {
            map[ch.channelID] = (cat.id, name)
        }
        for (_, threads) in cat.orderedThreadChildren {
            for ch in threads {
                map[ch.channelID] = (cat.id, name)
            }
        }
        if let fav = cat.favoriteFlatChannels {
            for ch in fav {
                map[ch.channelID] = (cat.id, name)
            }
        }
    }
    return map
}

private func repairChannelsFromSnapshotPlacement(
    _ channels: [Mezon_Api_ChannelDescription],
    snapshot: [ChannelCategory],
    categoryDescs: [Mezon_Api_CategoryDesc]
) -> [Mezon_Api_ChannelDescription] {
    let placement = categoryPlacementFromSnapshot(snapshot)
    guard !placement.isEmpty else { return channels }
    let descNames = Dictionary(categoryDescs.map { ($0.categoryID, $0.categoryName) }, uniquingKeysWith: { _, new in new })
    return channels.map { ch in
        guard ch.categoryID == 0, let place = placement[ch.channelID], place.categoryId != 0 else { return ch }
        var repaired = ch
        repaired.categoryID = place.categoryId
        if repaired.categoryName.isEmpty {
            let name = descNames[place.categoryId] ?? place.categoryName
            if !name.isEmpty {
                repaired.categoryName = name
            }
        }
        return repaired
    }
}

private func repairChannelsMissingCategoryIds(
    _ channels: [Mezon_Api_ChannelDescription],
    categoryDescs: [Mezon_Api_CategoryDesc]
) -> [Mezon_Api_ChannelDescription] {
    guard !categoryDescs.isEmpty else { return channels }
    let descNames = Dictionary(categoryDescs.map { ($0.categoryID, $0.categoryName) }, uniquingKeysWith: { _, new in new })
    var parentCategoryById: [Int64: Int64] = [:]
    for ch in channels where ch.parentID == 0 {
        if ch.categoryID != 0 {
            parentCategoryById[ch.channelID] = ch.categoryID
        } else if let id = inferCategoryId(for: ch, categoryDescs: categoryDescs) {
            parentCategoryById[ch.channelID] = id
        }
    }
    return channels.map { ch in
        guard ch.categoryID == 0 else { return ch }
        let catId: Int64?
        if ch.parentID != 0 {
            catId = parentCategoryById[ch.parentID] ?? inferCategoryId(for: ch, categoryDescs: categoryDescs)
        } else {
            catId = parentCategoryById[ch.channelID] ?? inferCategoryId(for: ch, categoryDescs: categoryDescs)
        }
        guard let catId, catId != 0 else { return ch }
        var repaired = ch
        repaired.categoryID = catId
        if repaired.categoryName.isEmpty, let name = descNames[catId], !name.isEmpty {
            repaired.categoryName = name
        }
        return repaired
    }
}

private func hasOrphanZeroCategoryBucket(
    _ cats: [ChannelCategory],
    categoryDescs: [Mezon_Api_CategoryDesc]
) -> Bool {
    guard !categoryDescs.isEmpty else { return false }
    let namedIds = Set(categoryDescs.map(\.categoryID))
    guard let zero = cats.first(where: { $0.id == 0 && !$0.channels.isEmpty }) else { return false }
    let namedCats = cats.filter { namedIds.contains($0.id) }
    guard !namedCats.isEmpty else { return false }
    let namedHaveChannels = namedCats.contains {
        !$0.channels.isEmpty || $0.orderedThreadChildren.values.contains(where: { !$0.isEmpty })
    }
    return !namedHaveChannels && !zero.channels.isEmpty
}

private func parentChannelOrderFromSnapshot(_ snapshot: [ChannelCategory]) -> [Int64: [Int64]] {
    var result: [Int64: [Int64]] = [:]
    for cat in snapshot where cat.id != ChannelCategory.favoritesCategoryId {
        var ids: [Int64] = []
        var seen = Set<Int64>()
        for ch in cat.channels where seen.insert(ch.channelID).inserted {
            ids.append(ch.channelID)
        }
        if !ids.isEmpty {
            result[cat.id] = ids
        }
    }
    if let orphan = snapshot.first(where: { $0.id == 0 && !$0.channels.isEmpty }) {
        result[0] = orphan.channels.map(\.channelID)
    }
    return result
}

private func threadOrderFromSnapshot(_ snapshot: [ChannelCategory]) -> [Int64: [Int64: [Int64]]] {
    var result: [Int64: [Int64: [Int64]]] = [:]
    for cat in snapshot {
        for (parentId, threads) in cat.orderedThreadChildren where !threads.isEmpty {
            result[cat.id, default: [:]][parentId] = threads.map(\.channelID)
        }
    }
    return result
}

private func globalParentChannelOrderFromSnapshot(_ snapshot: [ChannelCategory]) -> [Int64] {
    var order: [Int64] = []
    var seen = Set<Int64>()
    for cat in snapshot where cat.id != ChannelCategory.favoritesCategoryId {
        for ch in cat.channels where seen.insert(ch.channelID).inserted {
            order.append(ch.channelID)
        }
    }
    if let orphan = snapshot.first(where: { $0.id == 0 }) {
        for ch in orphan.channels where seen.insert(ch.channelID).inserted {
            order.append(ch.channelID)
        }
    }
    return order
}

private func globalParentOrder(from channels: [Mezon_Api_ChannelDescription]) -> [Int64] {
    var order: [Int64] = []
    var seen = Set<Int64>()
    for ch in channels where ch.parentID == 0 {
        if seen.insert(ch.channelID).inserted {
            order.append(ch.channelID)
        }
    }
    return order
}

private func reorderChannels(
    _ channels: [Mezon_Api_ChannelDescription],
    preferredOrder: [Int64]
) -> [Mezon_Api_ChannelDescription] {
    guard !preferredOrder.isEmpty else { return channels }
    let byId = Dictionary(channels.map { ($0.channelID, $0) }, uniquingKeysWith: { _, new in new })
    var used = Set<Int64>()
    var result: [Mezon_Api_ChannelDescription] = []
    for id in preferredOrder {
        if let ch = byId[id], used.insert(id).inserted {
            result.append(ch)
        }
    }
    for ch in channels where !used.contains(ch.channelID) {
        result.append(ch)
    }
    return result
}

private func applySnapshotChannelOrder(
    _ cats: [ChannelCategory],
    snapshot: [ChannelCategory],
    globalFallbackOrder: [Int64]
) -> [ChannelCategory] {
    let perCategoryOrder = parentChannelOrderFromSnapshot(snapshot)
    let threadOrders = threadOrderFromSnapshot(snapshot)
    return cats.map { cat in
        guard cat.id != ChannelCategory.favoritesCategoryId else { return cat }
        let parentOrder = perCategoryOrder[cat.id] ?? globalFallbackOrder
        let orderedParents = reorderChannels(cat.channels, preferredOrder: parentOrder)
        var newThreads: [Int64: [Mezon_Api_ChannelDescription]] = [:]
        let catThreadOrders = threadOrders[cat.id] ?? [:]
        for (parentId, threads) in cat.orderedThreadChildren {
            let preferred = catThreadOrders[parentId] ?? []
            newThreads[parentId] = reorderChannels(threads, preferredOrder: preferred)
        }
        return ChannelCategory(
            id: cat.id,
            name: cat.name,
            isCollapsed: cat.isCollapsed,
            channels: orderedParents,
            orderedThreadChildren: newThreads,
            favoriteFlatChannels: cat.favoriteFlatChannels
        )
    }
}

private func splitParentsAndOrderedThreads(from flatSorted: [Mezon_Api_ChannelDescription])
    -> (parents: [Mezon_Api_ChannelDescription], threadsByParent: [Int64: [Mezon_Api_ChannelDescription]])
{
    var parents: [Mezon_Api_ChannelDescription] = []
    var threadsByParent: [Int64: [Mezon_Api_ChannelDescription]] = [:]
    var i = 0
    while i < flatSorted.count {
        let ch = flatSorted[i]
        if ch.parentID == 0 {
            parents.append(ch)
            i += 1
            var threads: [Mezon_Api_ChannelDescription] = []
            while i < flatSorted.count, flatSorted[i].parentID == ch.channelID {
                threads.append(flatSorted[i])
                i += 1
            }
            if !threads.isEmpty {
                threadsByParent[ch.channelID] = threads
            }
        } else {
            i += 1
        }
    }
    return (parents, threadsByParent)
}

private func favoriteChannelsInTreeOrder(
    _ categories: [ChannelCategory],
    channels: [Mezon_Api_ChannelDescription],
    favoriteChannelIds: Set<Int64>
) -> [Mezon_Api_ChannelDescription] {
    guard !favoriteChannelIds.isEmpty else { return [] }
    var result: [Mezon_Api_ChannelDescription] = []
    var seen = Set<Int64>()
    for cat in categories where cat.id != ChannelCategory.favoritesCategoryId {
        for parent in cat.channels {
            if favoriteChannelIds.contains(parent.channelID), seen.insert(parent.channelID).inserted {
                result.append(parent)
            }
            for thread in cat.orderedThreadChildren[parent.channelID] ?? []
            where favoriteChannelIds.contains(thread.channelID) && seen.insert(thread.channelID).inserted {
                result.append(thread)
            }
        }
    }
    for ch in channels where favoriteChannelIds.contains(ch.channelID) && seen.insert(ch.channelID).inserted {
        result.append(ch)
    }
    return result
}

private func injectFavoritesCategoryIfNeeded(
    _ cats: [ChannelCategory],
    channels: [Mezon_Api_ChannelDescription],
    favoriteChannelIds: Set<Int64>,
    collapsedIds: Set<Int64>?
) -> [ChannelCategory] {
    guard !favoriteChannelIds.isEmpty else {
        return cats.filter { $0.id != ChannelCategory.favoritesCategoryId }
    }
    let favorFlat = favoriteChannelsInTreeOrder(cats, channels: channels, favoriteChannelIds: favoriteChannelIds)
    guard !favorFlat.isEmpty else {
        return cats.filter { $0.id != ChannelCategory.favoritesCategoryId }
    }
    var result = cats.filter { $0.id != ChannelCategory.favoritesCategoryId }
    let previousCollapsed = cats.first(where: { $0.id == ChannelCategory.favoritesCategoryId })?.isCollapsed ?? false
    let collapsed = collapsedIds?.contains(ChannelCategory.favoritesCategoryId) ?? previousCollapsed
    result.insert(
        ChannelCategory(
            id: ChannelCategory.favoritesCategoryId,
            name: localizedFavoriteChannelsCategoryTitle(),
            isCollapsed: collapsed,
            channels: [],
            orderedThreadChildren: [:],
            favoriteFlatChannels: favorFlat
        ),
        at: 0
    )
    return result
}

private func buildChannelCategories(
    _ channels: [Mezon_Api_ChannelDescription],
    categoryDescs: [Mezon_Api_CategoryDesc],
    favoriteChannelIds: Set<Int64>,
    collapsedIds: Set<Int64>? = nil
) -> [ChannelCategory] {
    let useCategories = normalizedCategoryDescs(categoryDescs, channels: channels)

    var nonFavorite: [ChannelCategory] = []
    for cat in useCategories {
        let flatSorted = sortChannelsForCategory(channels, categoryId: cat.categoryID)
        let (parents, threadsMap) = splitParentsAndOrderedThreads(from: flatSorted)
        let collapsed = collapsedIds?.contains(cat.categoryID) ?? false
        nonFavorite.append(ChannelCategory(
            id: cat.categoryID,
            name: cat.categoryName,
            isCollapsed: collapsed,
            channels: parents,
            orderedThreadChildren: threadsMap,
            favoriteFlatChannels: nil
        ))
    }

    let favorFlat = favoriteChannelsInTreeOrder(nonFavorite, channels: channels, favoriteChannelIds: favoriteChannelIds)

    var out: [ChannelCategory] = []
    if !favorFlat.isEmpty {
        out.append(ChannelCategory(
            id: ChannelCategory.favoritesCategoryId,
            name: localizedFavoriteChannelsCategoryTitle(),
            isCollapsed: collapsedIds?.contains(ChannelCategory.favoritesCategoryId) ?? false,
            channels: [],
            orderedThreadChildren: [:],
            favoriteFlatChannels: favorFlat
        ))
    }
    out.append(contentsOf: nonFavorite)
    return out
}

func buildThreadLookup(_ allChannels: [Mezon_Api_ChannelDescription]) -> [Int64: [Mezon_Api_ChannelDescription]] {
    var lookup: [Int64: [Mezon_Api_ChannelDescription]] = [:]
    for ch in allChannels where ch.parentID != 0 {
        lookup[ch.parentID, default: []].append(ch)
    }
    return lookup
}

func flattenCategoryToRows(_ category: ChannelCategory, allChannels: [Mezon_Api_ChannelDescription]) -> [ChannelListRow] {
    let lookup = buildThreadLookup(allChannels)
    return flattenCategoryToRows(category, threadLookup: lookup)
}

func flattenCategoryToRows(_ category: ChannelCategory, threadLookup: [Int64: [Mezon_Api_ChannelDescription]]) -> [ChannelListRow] {
    if let flat = category.favoriteFlatChannels {
        var rows: [ChannelListRow] = []
        for ch in flat {
            if ch.parentID == 0 {
                rows.append(.channel(ch, isInFavoriteSection: true))
            } else {
                rows.append(.thread(ch, isLast: true, isInFavoriteSection: true))
            }
        }
        return rows
    }
    var rows: [ChannelListRow] = []
    for ch in category.channels {
        rows.append(.channel(ch, isInFavoriteSection: false))
        let threads: [Mezon_Api_ChannelDescription]
        if let o = category.orderedThreadChildren[ch.channelID], !o.isEmpty {
            let allowedThreadIds = Set((threadLookup[ch.channelID] ?? []).map(\.channelID))
            threads = o.filter { allowedThreadIds.contains($0.channelID) }
        } else if let t = threadLookup[ch.channelID] {
            threads = t
        } else {
            threads = []
        }
        for (i, thread) in threads.enumerated() {
            rows.append(.thread(thread, isLast: i == 0, isInFavoriteSection: false))
        }
    }
    return rows
}

private enum FetchResult {
    case success([Mezon_Api_ChannelDescription], [Mezon_Api_CategoryDesc], Set<Int64>)
    case failure(String)
}

final class ChannelListViewController: ViewController {

    private let context: AccountContext
    private let initialSessionEpoch: Int
    private var isCurrentSessionAlive: Bool { context.isStillCurrentSession(epoch: initialSessionEpoch) }
    private let fetchDisposable = MetaDisposable()
    private let dataDisposable = MetaDisposable()
    private let clanUsersDisposable = MetaDisposable()
    private let clanEventsDisposable = MetaDisposable()
    private var processedBadgeKeys = Set<String>()
    private var pendingMentionUnreadFloorByClanId: [Int64: [Int64: Int32]] = [:]

    private func indexOfChannelInAllChannels(_ channelId: Int64) -> Int? {
        allChannels.firstIndex { $0.channelID == channelId }
    }

    private func parentChannelIdForThreadBadge(topicId: Int64, messageChannelId: Int64) -> Int64 {
        guard topicId != 0 else { return messageChannelId }
        if let row = allChannels.first(where: { $0.channelID == topicId }), row.parentID != 0 {
            return row.parentID
        }
        if messageChannelId != 0, messageChannelId != topicId {
            return messageChannelId
        }
        return messageChannelId
    }

    private func recordTimestampSentinelForMention(
        clanId: Int64, channelIds: [Int64], ts: UInt32?
    ) {
        guard let ts, ts != 0, clanId != 0 else { return }
        for w in -2...2 {
            let t = Int64(ts) + Int64(w)
            for c in channelIds where c != 0 {
                processedBadgeKeys.insert("ts:\(clanId)_\(c)_\(t)")
            }
        }
    }

    private func hasRecentMentionSentinel(
        clanId: Int64, channelId: Int64, ts: UInt32?
    ) -> Bool {
        guard let ts, ts != 0, clanId != 0 else { return false }
        for w in -2...2 {
            let t = Int64(ts) + Int64(w)
            if processedBadgeKeys.contains("ts:\(clanId)_\(channelId)_\(t)") { return true }
        }
        return false
    }

    private func pendingMentionUnreadFloor(clanId: Int64, channelId: Int64) -> Int32 {
        pendingMentionUnreadFloorByClanId[clanId]?[channelId] ?? 0
    }

    private func setPendingMentionUnreadFloor(clanId: Int64, channelId: Int64, count: Int32) {
        guard clanId != 0, channelId != 0, count > 0 else { return }
        var floors = pendingMentionUnreadFloorByClanId[clanId] ?? [:]
        floors[channelId] = max(floors[channelId] ?? 0, count)
        pendingMentionUnreadFloorByClanId[clanId] = floors
    }

    private func clearPendingMentionUnreadFloor(clanId: Int64, channelId: Int64) {
        guard clanId != 0, channelId != 0 else { return }
        pendingMentionUnreadFloorByClanId[clanId]?[channelId] = nil
        if pendingMentionUnreadFloorByClanId[clanId]?.isEmpty == true {
            pendingMentionUnreadFloorByClanId[clanId] = nil
        }
    }

    @discardableResult
    private func bumpMentionUnread(clanId: Int64, channelId: Int64) -> Bool {
        guard clanId != 0, channelId != 0 else { return false }
        if let index = indexOfChannelInAllChannels(channelId) {
            allChannels[index].countMessUnread += 1
            setPendingMentionUnreadFloor(
                clanId: clanId,
                channelId: channelId,
                count: allChannels[index].countMessUnread
            )
            return true
        }
        let currentFloor = pendingMentionUnreadFloor(clanId: clanId, channelId: channelId)
        let nextFloor = currentFloor == Int32.max ? currentFloor : currentFloor + 1
        setPendingMentionUnreadFloor(clanId: clanId, channelId: channelId, count: nextFloor)
        return false
    }

    private func mergeCachedUnreadCounts(
        into channels: [Mezon_Api_ChannelDescription],
        cached: [Mezon_Api_ChannelDescription]
    ) -> [Mezon_Api_ChannelDescription] {
        guard !cached.isEmpty else { return channels }
        let byId = Dictionary(cached.map { ($0.channelID, $0) }, uniquingKeysWith: { _, new in new })
        return channels.map { ch in
            guard let prev = byId[ch.channelID] else { return ch }
            var merged = ch
            if prev.countMessUnread > merged.countMessUnread {
                let fetchedSaysRead = ch.hasLastSeenMessage && ch.hasLastSentMessage
                    && ch.lastSeenMessage.timestampSeconds >= ch.lastSentMessage.timestampSeconds
                if !fetchedSaysRead {
                    merged.countMessUnread = prev.countMessUnread
                }
            }
            if prev.hasLastSeenMessage,
               !merged.hasLastSeenMessage
                   || prev.lastSeenMessage.timestampSeconds > merged.lastSeenMessage.timestampSeconds {
                merged.lastSeenMessage = prev.lastSeenMessage
            }
            if prev.hasLastSentMessage {
                if !merged.hasLastSentMessage {
                    merged.lastSentMessage = prev.lastSentMessage
                } else {
                    let pi = prev.lastSentMessage
                    let ci = merged.lastSentMessage
                    if pi.timestampSeconds > ci.timestampSeconds {
                        merged.lastSentMessage = pi
                    } else if pi.timestampSeconds == ci.timestampSeconds,
                              ci.content.isEmpty,
                              !pi.content.isEmpty {
                        var inc = ci
                        inc.content = pi.content
                        if inc.senderID == 0 { inc.senderID = pi.senderID }
                        if inc.id == 0 { inc.id = pi.id }
                        merged.lastSentMessage = inc
                    }
                }
            }
            return merged
        }
    }

    private func preservePendingMentionUnread(
        in channels: [Mezon_Api_ChannelDescription],
        clanId: Int64
    ) -> [Mezon_Api_ChannelDescription] {
        guard clanId != 0,
              let floors = pendingMentionUnreadFloorByClanId[clanId],
              !floors.isEmpty else {
            return channels
        }

        var result = channels
        var existingById: [Int64: Mezon_Api_ChannelDescription] = [:]
        for channel in allChannels where channel.clanID == 0 || channel.clanID == clanId {
            existingById[channel.channelID] = channel
        }
        for index in result.indices {
            let channelId = result[index].channelID
            guard let floor = floors[channelId], floor > 0 else { continue }
            if result[index].countMessUnread < floor {
                result[index].countMessUnread = floor
            }
            if let existing = existingById[channelId],
               existing.hasLastSentMessage,
               (!result[index].hasLastSentMessage
                || existing.lastSentMessage.timestampSeconds > result[index].lastSentMessage.timestampSeconds) {
                result[index].lastSentMessage = existing.lastSentMessage
            }
        }
        return result
    }

    @discardableResult
    private func applyMentionEventUnreadIfNeeded(
        clanId: Int64,
        messageId: Int64,
        parentChannelId: Int64,
        threadChannelId: Int64?,
        ts: UInt32? = nil
    ) -> Bool {
        guard clanId != 0, messageId != 0, parentChannelId != 0 else { return false }
        let targetChannelIds = [parentChannelId, threadChannelId ?? 0]
            .filter { $0 != 0 }
            .reduce(into: [Int64]()) { result, channelId in
                if !result.contains(channelId) {
                    result.append(channelId)
                }
            }
        recordTimestampSentinelForMention(
            clanId: clanId,
            channelIds: targetChannelIds,
            ts: ts
        )
        var didChange = false
        for channelId in targetChannelIds {
            let ekey = "m:\(clanId)_\(messageId)_\(channelId)"
            if processedBadgeKeys.contains(ekey) { continue }
            processedBadgeKeys.insert(ekey)
            if bumpMentionUnread(clanId: clanId, channelId: channelId) {
                didChange = true
            }
        }
        if processedBadgeKeys.count > 1500 { processedBadgeKeys.removeAll() }
        return didChange
    }

    deinit {
        fetchDisposable.dispose()
        dataDisposable.dispose()
        clanUsersDisposable.dispose()
        clanEventsDisposable.dispose()
        NotificationCenter.default.removeObserver(self)
    }

    private let categoriesPipe = ValuePipe<[ChannelCategory]>()
    private let selectedChannelIdPipe = ValuePipe<Int64?>()
    private let selectedChannelPipe = ValuePipe<Mezon_Api_ChannelDescription?>()
    private let isLoadingPipe = ValuePipe<Bool>()
    private let errorMessagePipe = ValuePipe<String?>()
    private let needsReloadPipe = ValuePipe<Void>()

    private var voicePresenceReloadScheduled = false
    private let voicePresenceCoalesceInterval: TimeInterval = 0.4
    private var clanUsersReloadScheduled = false
    private var channelListStateEmitCoalesceScheduled = false
    private var categoryDescsRefreshScheduled = false

    private let channelsLoadedPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    var channelsLoadedSignal: Signal<Bool, NoError> { channelsLoadedPromise.get() }

    var selectedChannelSignal: Signal<Mezon_Api_ChannelDescription?, NoError> { selectedChannelPipe.signal() }

    private let searchTappedPipe = ValuePipe<Void>()
    var searchTappedSignal: Signal<Void, NoError> { searchTappedPipe.signal() }

    private(set) var categories: [ChannelCategory] = []
    private var showEmptyCategoriesEnabled: Bool = false
    private(set) var selectedChannelId: Int64?
    private(set) var selectedChannel: Mezon_Api_ChannelDescription?
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var clanId: Int64 = 0
    private(set) var clanName: String = ""
    private(set) var clanLogoURL: String = ""
    private var sidebarMemberCount: Int = 0
    private var onboardingMemberFetchInFlight = false
    private var lastOnboardingMemberFetchAt: Date?
    private let onboardingMemberFetchCooldown: TimeInterval = 3.0
    private var lastOnboardingState: ClanOnboardingViewState = .hidden
    private var lastMemberOnboardingState: MemberOnboardingViewState = .hidden
    private var memberOnboardingFetchInFlight = false
    private var memberOnboardingFetchedClanId: Int64?

    private var pendingSkeletonRevealItem: DispatchWorkItem?
    private let skeletonRevealDelay: TimeInterval = 0.4

    private var channelListCategoryDescs: [Mezon_Api_CategoryDesc] = []

    private var channelListFavoriteIds: Set<Int64> = []

    private struct HeaderConfiguration: Equatable {
        let clanId: Int64
        let clanName: String
        let logoURL: String
        let bannerURL: String
        let memberCount: Int
        let isCommunity: Bool
    }

    private var lastHeaderConfiguration: HeaderConfiguration?

    private var channelListNode: ChannelListContainerNode { displayNode as! ChannelListContainerNode }

    private var enclosingNavigationController: NavigationController? {
        var current: UIViewController? = self
        while let node = current {
            if let nav = node as? NavigationController {
                return nav
            }
            if let nav = node.navigationController as? NavigationController {
                return nav
            }
            current = node.parent
        }
        return nil
    }

    init(context: AccountContext) {
        self.context = context
        self.initialSessionEpoch = context.sessionEpoch
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let interaction = ChannelListInteraction(
            onSelectChannel: { [weak self] ch in self?.handleChannelTap(ch) },
            onLongPressChannel: { [weak self] ch in self?.presentChannelActionSheet(ch) },
            onToggleCollapse: { [weak self] id in self?.toggleCollapse(categoryId: id) },
            onRefresh: { [weak self] in self?.fetchChannels() },
            onPresentSettings: { [weak self] in self?.presentSettings() },
            onInviteClan: { [weak self] in self?.presentInviteClanSheet() },
            onCreateCategory: { [weak self] in self?.presentCreateCategory() },
            canCreateCategory: { [weak self] in
                guard let self, self.clanId != 0 else { return false }
                return self.context.rolePermissions.canManageRoles(clanId: self.clanId)
            },
            isClanOwner: { [weak self] in
                guard let self, self.clanId != 0 else { return false }
                return self.context.rolePermissions.isClanOwner(clanId: self.clanId)
            },
            onLeaveClan: { [weak self] in self?.presentLeaveClanConfirm() },
            onDeleteClan: { [weak self] in self?.presentDeleteClanConfirm() },
            onSearchTapped: { [weak self] in self?.searchTappedPipe.putNext(()) },
            onQRTapped: { [weak self] in
                guard let self else { return }
                let vc = QRScannerViewController(context: self.context)
                self.enclosingNavigationController?.pushViewController(vc, animated: true)
            },
            onEventTapped: { [weak self] in self?.presentEventBottomSheet() },
            onSelectChannelApp: { [weak self] app in self?.openChannelApp(app) },
            onClearCurrentChannelSelection: { [weak self] in self?.clearCurrentChannelSelection() },
            isShowEmptyCategoriesEnabled: { [weak self] in
                guard let self, self.clanId != 0 else { return false }
                return self.loadShowEmptyCategoriesPreference(clanId: self.clanId)
            },
            onToggleShowEmptyCategories: { [weak self] value in self?.setShowEmptyCategories(value) },
            onLongPressCategory: { [weak self] category in self?.presentCategoryActionSheet(category) },
            onBecameVisible: { [weak self] in self?.reconcileChannelListDataIfNeeded() },
            onOnboardingBannerTapped: { [weak self] in self?.presentOnboardingBottomSheet() },
            onClanSwitchChannelListApplied: { [weak self] in self?.prepareOnboardingStateForClanSwitch() }
        )
        let initialClan = effectiveClanIdForChannelAppsHydration()
        let initialApps = initialClan != 0 ? channelAppsRawFromCache(clanId: initialClan) : []
        let container = ChannelListContainerNode(
            signal: stateSignal(),
            interaction: interaction,
            initialChannelApps: initialApps
        )
        container.voiceMemberResolver = { [weak self] uid in
            self?.resolveVoiceMember(uid)
        }
        displayNode = container
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshShowEmptyCategoriesPreferenceFromCache()
        refreshChannelEventStatuses()
        reconcileChannelListDataIfNeeded()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        channelListNode.applyTheme()
        if clanId == 0 {
            let earlyClanId = effectiveClanIdForChannelAppsHydration()
            if earlyClanId != 0, let payload = resolveChannelCachePayloadForDisplay(clanId: earlyClanId) {
                clanId = earlyClanId
                showEmptyCategoriesEnabled = loadShowEmptyCategoriesPreference(clanId: earlyClanId)
                applyResolvedChannelCachePayload(clanId: earlyClanId, channels: payload.channels, meta: payload.meta, layoutOrdered: payload.layoutOrdered)
                cancelDeferredSkeletonReveal()
                needsReloadPipe.putNext(())
                refreshMemberOnboardingState()
                scheduleAuthoritativeNetworkReconcileIfNeeded(reason: "viewDidLoadEarlyCache")
            }
        }
        hydrateChannelAppsFromCacheForEffectiveClan()
        if clanId != 0, NetworkMonitor.shared.isConnected {
            fetchChannelAppsInBackground()
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.context.waitForSessionReady()
            guard self.clanId != 0, self.allChannels.isEmpty else { return }
            self.reconcileChannelListDataIfNeeded()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleChannelMarkedAsRead(_:)), name: Notification.Name("MezonChannelMarkedAsRead"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleNewMessageReceived(_:)), name: Notification.Name("MezonNewMessageReceived"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleMentionReceived(_:)), name: Notification.Name("MezonMentionReceived"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSocketStatusForChannelBadges(_:)), name: .mezonSocketStatusChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleJoinedClanForChannelBadges(_:)), name: Notification.Name("MezonJoinedClanChatForBadges"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleVoicePresenceChanged(_:)), name: .mezonVoicePresenceChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleNetworkStatusChanged(_:)), name: NetworkMonitor.statusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWillEnterForegroundForChannelBadges), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleUserChannelAddedFromSocket(_:)), name: .mezonUserChannelAddedFromSocket, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleChannelDescriptionDidUpdate(_:)), name: .mezonChannelDescriptionDidUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleChannelDeletedLocally(_:)), name: .mezonChannelDeletedLocally, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleMemberOnboardingDidUpdate(_:)), name: .mezonMemberOnboardingDidUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAccountCurrentUserDidChangeForOnboarding(_:)), name: .mezonAccountCurrentUserDidChange, object: nil)
        clanUsersDisposable.set(
            (context.engine.clanData.clanUsersUpdated.signal() |> deliverOnMainQueue).start(next: { [weak self] updatedClanId in
                guard let self, self.clanId != 0, updatedClanId == self.clanId else { return }
                self.scheduleCoalescedClanUsersReload()
            })
        )
        clanEventsDisposable.set(
            (context.engine.clanData.clanEventsUpdated.signal() |> deliverOnMainQueue).start(next: { [weak self] updatedClanId in
                guard let self, self.clanId != 0, updatedClanId == self.clanId else { return }
                self.refreshChannelEventStatuses()
            })
        )
        refreshChannelEventStatuses()
    }

    private func refreshChannelEventStatuses() {
        let statuses = clanId == 0
            ? [:]
            : context.engine.clanData.channelEventStatuses(clanId: clanId)
        channelListNode.updateChannelEventStatuses(statuses)
    }

    @objc private func handleAccountCurrentUserDidChangeForOnboarding(_ notification: Notification) {
        guard clanId != 0 else { return }
        guard memberOnboardingFetchedClanId != clanId else { return }
        scheduleMemberOnboardingDataFetch()
    }

    @objc private func handleMemberOnboardingDidUpdate(_ notification: Notification) {
        guard let gid = notification.userInfo?["clanId"] as? Int64 else { return }
        guard gid == clanId, clanId != 0 else { return }
        refreshMemberOnboardingState()
    }

    @objc private func handleChannelDescriptionDidUpdate(_ notification: Notification) {
        guard let gid = notification.userInfo?["clanId"] as? Int64 else { return }
        guard gid == clanId, clanId != 0 else { return }
        if let channelId = notification.userInfo?["channelId"] as? Int64,
           let idx = allChannels.firstIndex(where: { $0.channelID == channelId }),
           let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)),
           let updated = decodeChannelList(data).first(where: { $0.channelID == channelId }) {
            allChannels[idx] = updated
            let cats = applyCategoriesAfterFetch(
                mergedChannels: allChannels,
                categoryDescs: channelListCategoryDescs,
                favoriteIds: channelListFavoriteIds
            )
            categories = cats
            categoriesPipe.putNext(categories)
            needsReloadPipe.putNext(())
            refreshOnboardingState()
            scheduleMemberOnboardingDataFetch()
            return
        }
        if NetworkMonitor.shared.isConnected {
            lastChannelFetchAtByClanId.removeValue(forKey: clanId)
            scheduleChannelListNetworkFetch(allowEmptyChannelAppsOverwrite: false)
        }
        refreshOnboardingState()
        scheduleMemberOnboardingDataFetch()
    }

    @objc private func handleChannelDeletedLocally(_ notification: Notification) {
        guard let gid = notification.userInfo?["clanId"] as? Int64, gid == self.clanId else { return }
        guard let cid = notification.userInfo?["channelId"] as? Int64 else { return }
        removeChannelLocally(channelId: cid)
    }

    private func effectiveClanIdForChannelAppsHydration() -> Int64 {
        if clanId != 0 { return clanId }
        return persistedSelectedClanId()
    }

    private func channelAppsRawFromCache(clanId: Int64) -> [Mezon_Api_ChannelAppResponse] {
        guard clanId != 0 else { return [] }
        let key = PreferencesKeys.channelApps(clanId: clanId)
        guard let data = context.account.postbox.getPreferenceData(key: key), !data.isEmpty else { return [] }
        return channelAppsForClan(decodeChannelApps(data), clanId: clanId, fromCache: true)
    }

    private func hydrateChannelAppsFromCacheForEffectiveClan() {
        let id = effectiveClanIdForChannelAppsHydration()
        guard id != 0 else { return }
        restoreCachedChannelApps(clanId: id)
    }

    private func persistedSelectedClanId() -> Int64 {
        let udValue = UserDefaults.standard.integer(forKey: "mezon_selectedClanId")
        if udValue != 0 { return Int64(udValue) }
        if let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.selectedClanId), data.count >= 8 {
            return data.withUnsafeBytes { $0.loadUnaligned(as: Int64.self).littleEndian }
        }
        return 0
    }

    @objc private func handleUserChannelAddedFromSocket(_ notification: Notification) {
        guard let gid = notification.userInfo?["clanId"] as? Int64 else { return }
        guard gid == clanId, clanId != 0 else { return }
        if let ch = notification.userInfo?["channel"] as? Mezon_Api_ChannelDescription,
           ch.parentID != 0 {
            insertJoinedThreadIntoCategoriesSnapshotIfNeeded(ch)
        }
        if let ch = notification.userInfo?["channel"] as? Mezon_Api_ChannelDescription {
            var merged = allChannels
            if let idx = merged.firstIndex(where: { $0.channelID == ch.channelID }) {
                merged[idx] = ch
            } else {
                merged.append(ch)
            }
            allChannels = preservePendingMentionUnread(in: merged, clanId: clanId)
            let cats = applyCategoriesAfterFetch(
                mergedChannels: allChannels,
                categoryDescs: channelListCategoryDescs,
                favoriteIds: channelListFavoriteIds
            )
            categories = cats
            categoriesPipe.putNext(categories)
            persistFullChannelListCache(
                clanId: clanId,
                channels: allChannels,
                categoryDescs: channelListCategoryDescs,
                favoriteIds: channelListFavoriteIds,
                categories: cats
            )
        } else if NetworkMonitor.shared.isConnected {
            lastChannelFetchAtByClanId.removeValue(forKey: clanId)
            fetchChannelsWithoutLoadingSignal(allowEmptyChannelAppsOverwrite: false)
        }
        syncSelectedChannelFromStoredPreferences()
        needsReloadPipe.putNext(())
    }

    private func insertJoinedThreadIntoCategoriesSnapshotIfNeeded(_ thread: Mezon_Api_ChannelDescription) {
        guard clanId != 0, thread.channelID != 0, thread.parentID != 0 else { return }
        guard var snap = readCategoriesSnapshotFromCache(clanId: clanId), !snap.isEmpty else { return }

        var didUpdate = false
        for idx in snap.indices {
            guard snap[idx].channels.contains(where: { $0.channelID == thread.parentID }) else { continue }
            var cat = snap[idx]
            var threads = cat.orderedThreadChildren[thread.parentID] ?? []
            if let existingIdx = threads.firstIndex(where: { $0.channelID == thread.channelID }) {
                threads[existingIdx] = thread
            } else {
                threads.insert(thread, at: 0)
            }
            cat.orderedThreadChildren[thread.parentID] = threads
            snap[idx] = cat
            didUpdate = true
            break
        }
        guard didUpdate else { return }
        context.account.postbox.setPreferenceDataSync(
            key: PreferencesKeys.channelListCategories(clanId: clanId),
            value: encodeCategoriesSnapshot(snap)
        )
    }

    @objc private func handleVoicePresenceChanged(_ notification: Notification) {
        guard let n = notification.userInfo?["clanId"] as? NSNumber else { return }
        guard n.int64Value == clanId, clanId != 0 else { return }
        scheduleCoalescedVoicePresenceReload()
    }

    private func scheduleCoalescedVoicePresenceReload() {
        guard !voicePresenceReloadScheduled else { return }
        voicePresenceReloadScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + voicePresenceCoalesceInterval) { [weak self] in
            guard let self else { return }
            self.voicePresenceReloadScheduled = false
            guard self.clanId != 0 else { return }
            self.needsReloadPipe.putNext(())
        }
    }

    private func scheduleCoalescedClanUsersReload() {
        guard !clanUsersReloadScheduled else { return }
        clanUsersReloadScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + voicePresenceCoalesceInterval) { [weak self] in
            guard let self else { return }
            self.clanUsersReloadScheduled = false
            guard self.clanId != 0 else { return }
            self.needsReloadPipe.putNext(())
            self.channelListNode.reloadVoiceMemberRows()
        }
    }

    @objc private func handleNetworkStatusChanged(_ notification: Notification) {
        let connected = (notification.userInfo?["isConnected"] as? Bool) ?? NetworkMonitor.shared.isConnected
        guard connected, clanId != 0 else { return }
        refreshChannelListAfterConnectivityRestored()
    }

    @objc private func handleJoinedClanForChannelBadges(_ notification: Notification) {
        guard let joinedClan = notification.userInfo?["clanId"] as? Int64 else { return }
        guard joinedClan == clanId, joinedClan != 0 else { return }
        if let last = lastBadgeCountFetchAtByClanId[joinedClan],
           Date().timeIntervalSince(last) < badgeCountFetchCooldown {
            return
        }
        Task { @MainActor in
            await self.applyChannelBadgeCounts(clanId: joinedClan)
        }
    }

    @objc private func handleSocketStatusForChannelBadges(_ notification: Notification) {
        guard let connected = notification.userInfo?["isConnected"] as? Bool, connected else { return }
        guard clanId != 0 else { return }
        refetchChannelEventsAfterConnectivityRestored()
        refreshChannelListAfterConnectivityRestored()
    }

    @objc private func handleWillEnterForegroundForChannelBadges() {
        guard clanId != 0 else { return }
        if allChannels.isEmpty {
            if NetworkMonitor.shared.isConnected {
                scheduleChannelListNetworkFetch(allowEmptyChannelAppsOverwrite: false)
            }
            return
        }
        Task { @MainActor [weak self] in
            guard let self, self.clanId != 0 else { return }
            await self.applyChannelBadgeCounts(clanId: self.clanId)
        }
    }

    private func refetchChannelEventsAfterConnectivityRestored() {
        let clanId = self.clanId
        guard clanId != 0 else { return }
        Task { @MainActor [weak self] in
            guard let self, self.clanId == clanId else { return }
            guard let token = await self.context.getTokenPreferringCachedSkipSessionReadyWait() else { return }
            guard self.clanId == clanId else { return }
            await self.context.engine.clanData.refetchEvents(clanId: clanId, token: token)
        }
    }

    private func refreshChannelListAfterConnectivityRestored() {
        guard clanId != 0 else { return }
        if allChannels.isEmpty {
            scheduleChannelListNetworkFetch(allowEmptyChannelAppsOverwrite: false)
            return
        }
        if let last = lastBadgeCountFetchAtByClanId[clanId],
           Date().timeIntervalSince(last) < badgeCountFetchCooldown {
            return
        }
        Task { @MainActor [weak self] in
            guard let self, self.clanId != 0 else { return }
            await self.applyChannelBadgeCounts(clanId: self.clanId)
        }
    }

    private func channelListRowsVisuallyEqual(_ a: [Mezon_Api_ChannelDescription], _ b: [Mezon_Api_ChannelDescription]) -> Bool {
        guard a.count == b.count else { return false }
        let byId = Dictionary(b.map { ($0.channelID, $0) }, uniquingKeysWith: { _, new in new })
        for ch in a {
            guard let o = byId[ch.channelID] else { return false }
            if ch.countMessUnread != o.countMessUnread { return false }
            if ch.channelLabel != o.channelLabel { return false }
            if ch.type != o.type { return false }
            if ch.channelPrivate != o.channelPrivate { return false }
            if ch.ageRestricted != o.ageRestricted { return false }
            if ch.lastSeenMessage.timestampSeconds != o.lastSeenMessage.timestampSeconds { return false }
            if ch.lastSentMessage.timestampSeconds != o.lastSentMessage.timestampSeconds { return false }
            if ch.hasLastSentMessage != o.hasLastSentMessage { return false }
            let uA = ch.countMessUnread > 0
                || (ch.hasLastSentMessage && ch.lastSeenMessage.timestampSeconds < ch.lastSentMessage.timestampSeconds)
            let uB = o.countMessUnread > 0
                || (o.hasLastSentMessage && o.lastSeenMessage.timestampSeconds < o.lastSentMessage.timestampSeconds)
            if uA != uB { return false }
        }
        return true
    }

    private var inflightBadgeCountTask: [Int64: Task<[Mezon_Api_ChannelDescription]?, Never>] = [:]
    private var lastBadgeCountFetchAtByClanId: [Int64: Date] = [:]
    private var badgeCountEmptyRetryCountByClanId: [Int64: Int] = [:]
    private let badgeCountFetchCooldown: TimeInterval = 5.0
    private let maxBadgeCountEmptyRetries = 3

    @MainActor
    private func fetchMergedChannelsWithBadgeCounts(
        base: [Mezon_Api_ChannelDescription],
        clanId: Int64,
        force: Bool = false
    ) async -> [Mezon_Api_ChannelDescription] {
        guard clanId != 0 else { return base }
        guard clanId == self.clanId else { return base }

        if !force, let inflight = inflightBadgeCountTask[clanId] {
            let rows = await inflight.value
            guard isCurrentSessionAlive else { return base }
            guard clanId == self.clanId else { return base }
            return mergeBadgeFetchResult(rows, base: base, clanId: clanId)
        }

        if !force,
           let last = lastBadgeCountFetchAtByClanId[clanId],
           Date().timeIntervalSince(last) < badgeCountFetchCooldown {
            return preservePendingMentionUnread(in: base, clanId: clanId)
        }

        let token = await context.getTokenPreferringCachedSkipSessionReadyWait()
        guard clanId == self.clanId else { return base }
        guard let token else { return preservePendingMentionUnread(in: base, clanId: clanId) }

        let task: Task<[Mezon_Api_ChannelDescription]?, Never> = Task.detached(priority: .utility) {
            do {
                return try await MezonHTTPClient.shared.listChannelBadgeCount(clanId: clanId, token: token).channeldesc
            } catch {
                return nil
            }
        }
        inflightBadgeCountTask[clanId] = task
        let rows = await task.value
        inflightBadgeCountTask[clanId] = nil

        guard isCurrentSessionAlive else { return base }
        guard clanId == self.clanId else { return base }
        return mergeBadgeFetchResult(rows, base: base, clanId: clanId)
    }

    @MainActor
    private func mergeBadgeFetchResult(
        _ rows: [Mezon_Api_ChannelDescription]?,
        base: [Mezon_Api_ChannelDescription],
        clanId: Int64
    ) -> [Mezon_Api_ChannelDescription] {
        guard let rows else {
            scheduleBadgeCountRetryIfNeeded(clanId: clanId)
            return preservePendingMentionUnread(in: base, clanId: clanId)
        }
        lastBadgeCountFetchAtByClanId[clanId] = Date()
        badgeCountEmptyRetryCountByClanId[clanId] = 0
        guard !rows.isEmpty else {
            return preservePendingMentionUnread(in: base, clanId: clanId)
        }
        var merged = base
        ChannelUnreadBadgeSync.mergeSocketBadgeRows(into: &merged, badgeRows: rows)
        return preservePendingMentionUnread(in: merged, clanId: clanId)
    }

    @MainActor
    private func scheduleBadgeCountRetryIfNeeded(clanId: Int64) {
        guard clanId != 0 else { return }
        let attempts = badgeCountEmptyRetryCountByClanId[clanId, default: 0]
        guard attempts < maxBadgeCountEmptyRetries else { return }
        badgeCountEmptyRetryCountByClanId[clanId] = attempts + 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, self.clanId == clanId else { return }
            await self.applyChannelBadgeCounts(clanId: clanId, force: true)
        }
    }

    @MainActor
    private func applyChannelBadgeCounts(clanId: Int64, force: Bool = false, emitReload: Bool = true) async {
        guard clanId != 0 else { return }
        guard clanId == self.clanId else { return }
        let updated = await fetchMergedChannelsWithBadgeCounts(base: allChannels, clanId: clanId, force: force)
        guard isCurrentSessionAlive else { return }
        guard clanId == self.clanId else { return }
        guard updated.count == allChannels.count,
              zip(updated, allChannels).allSatisfy({ $0.channelID == $1.channelID }) else { return }
        if channelListRowsVisuallyEqual(allChannels, updated) {
            let total = updated.reduce(Int32(0)) { $0 + $1.countMessUnread }
            NotificationCenter.default.post(
                name: Notification.Name("MezonClanChannelUnreadDerived"),
                object: nil,
                userInfo: ["clanId": clanId, "totalUnread": total]
            )
            return
        }
        allChannels = updated
        let cats = applyCategoriesAfterFetch(
            mergedChannels: updated,
            categoryDescs: channelListCategoryDescs,
            favoriteIds: channelListFavoriteIds
        )
        categories = cats
        categoriesPipe.putNext(categories)
        persistFullChannelListCache(
            clanId: clanId,
            channels: updated,
            categoryDescs: channelListCategoryDescs,
            favoriteIds: channelListFavoriteIds,
            categories: categories
        )
        if emitReload {
            needsReloadPipe.putNext(())
        }
        postClanSidebarUnreadDerivedFromCurrentChannels()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        channelListNode.updateLayout(layout: layout, transition: transition)
    }

    func configure(clanId: Int64, clanName: String, logoURL: String? = nil, bannerURL: String? = nil, memberCount: Int = 0, isCommunity: Bool = false) {
        let headerConfiguration = HeaderConfiguration(
            clanId: clanId,
            clanName: clanName,
            logoURL: logoURL ?? "",
            bannerURL: bannerURL ?? "",
            memberCount: memberCount,
            isCommunity: isCommunity
        )
        self.clanName = clanName
        self.clanLogoURL = logoURL ?? ""
        self.sidebarMemberCount = memberCount
        guard clanId != self.clanId else {
            refreshShowEmptyCategoriesPreferenceFromCache()
            if lastHeaderConfiguration != headerConfiguration {
                channelListNode.configure(clanName: clanName, clanId: clanId, logoURL: logoURL, bannerURL: bannerURL, memberCount: memberCount, isCommunity: isCommunity)
                lastHeaderConfiguration = headerConfiguration
            }
            refreshOnboardingState()
            if clanId != 0 {
                restoreCachedChannelApps(clanId: clanId)
            }
            if clanId != 0 && allChannels.isEmpty {
                if let payload = resolveChannelCachePayloadForDisplay(clanId: clanId) {
                    applyResolvedChannelCachePayload(clanId: clanId, channels: payload.channels, meta: payload.meta, layoutOrdered: payload.layoutOrdered)
                    cancelDeferredSkeletonReveal()
                    needsReloadPipe.putNext(())
                    scheduleAuthoritativeNetworkReconcileIfNeeded(reason: "configureSameClanHydrate")
                } else {
                    reconcileChannelListDataIfNeeded()
                }
            }
            scheduleAuthoritativeNetworkReconcileIfNeeded(reason: "configureSameClan")
            return
        }
        let previousClanId = self.clanId
        if previousClanId != clanId {
            fetchDisposable.set(nil)
            inflightChannelFetchClanId = 0
            badgeCountEmptyRetryCountByClanId.removeValue(forKey: previousClanId)
        }
        if previousClanId != 0 {
            context.clearPersistedSelectedChannelPreference(forClanId: previousClanId)
        }
        setSelectedChannelId(nil)
        setSelectedChannel(nil)
        let hasCachedChannels = clanId != 0 && resolveChannelCachePayloadForDisplay(clanId: clanId) != nil
        if !hasCachedChannels {
            channelListNode.markClanSwitching()
        }
        lastOnboardingState = .hidden
        lastMemberOnboardingState = .hidden
        self.clanId = clanId
        self.clanName = clanName
        channelListNode.configure(clanName: clanName, clanId: clanId, logoURL: logoURL, bannerURL: bannerURL, memberCount: memberCount, isCommunity: isCommunity)
        lastHeaderConfiguration = headerConfiguration
        refreshMemberOnboardingState()
        load(clanId: clanId, clanName: clanName)
    }

    func updateMemberCount(_ count: Int) {
        sidebarMemberCount = count
        channelListNode.updateMemberCount(count)
        if let current = lastHeaderConfiguration, current.clanId == clanId {
            lastHeaderConfiguration = HeaderConfiguration(
                clanId: current.clanId,
                clanName: current.clanName,
                logoURL: current.logoURL,
                bannerURL: current.bannerURL,
                memberCount: count,
                isCommunity: current.isCommunity
            )
        }
        refreshOnboardingState()
    }

    private func currentOnboardingState() -> ClanOnboardingViewState {
        ClanOnboardingProgress.compute(
            context: context,
            clanId: clanId,
            channels: allChannels,
            memberCount: sidebarMemberCount
        )
    }

    private func prepareOnboardingStateForClanSwitch() {
        guard clanId != 0 else { return }
        let state = currentOnboardingState()
        lastOnboardingState = state
        channelListNode.updateOnboardingState(state)
        if state.isVisible && !state.inviteCompleted {
            scheduleOnboardingMemberCountRefresh()
        } else if !state.isVisible {
            scheduleMemberOnboardingDataFetch()
            refreshMemberOnboardingState()
        }
    }

    private func refreshOnboardingState() {
        guard clanId != 0 else { return }
        if !(lastOnboardingState == .hidden && !ClanOnboardingProgress.isEligible(context: context, clanId: clanId)) {
            let state = currentOnboardingState()
            if state != lastOnboardingState {
                lastOnboardingState = state
                channelListNode.updateOnboardingState(state)
                if state.isVisible && !state.inviteCompleted {
                    scheduleOnboardingMemberCountRefresh()
                }
            }
        }

        guard !lastOnboardingState.isVisible else {
            if lastMemberOnboardingState.isVisible {
                lastMemberOnboardingState = .hidden
                channelListNode.updateMemberOnboardingState(.hidden)
            }
            return
        }
        refreshMemberOnboardingState()
    }

    private func refreshMemberOnboardingState() {
        guard clanId != 0, !lastOnboardingState.isVisible else { return }
        let state = MemberOnboardingProgress.compute(context: context, clanId: clanId)
        guard state != lastMemberOnboardingState else { return }
        lastMemberOnboardingState = state
        channelListNode.updateMemberOnboardingState(state)
    }

    private var lastMemberOnboardingFetchAtByClanId: [Int64: Date] = [:]
    private let onboardingCacheTTL: TimeInterval = 300

    private func scheduleMemberOnboardingDataFetch() {
        guard clanId != 0, !memberOnboardingFetchInFlight else { return }
        let clanId = self.clanId
        if let last = lastMemberOnboardingFetchAtByClanId[clanId],
           Date().timeIntervalSince(last) < onboardingCacheTTL {
            return
        }
        memberOnboardingFetchInFlight = true
        Task { @MainActor [weak self] in
            defer { self?.memberOnboardingFetchInFlight = false }
            guard let self, self.clanId == clanId else { return }
            await MemberOnboardingProgress.fetchData(context: self.context, clanId: clanId)
            guard self.clanId == clanId else { return }
            self.lastMemberOnboardingFetchAtByClanId[clanId] = Date()
            self.memberOnboardingFetchedClanId = clanId
            self.refreshMemberOnboardingState()
        }
    }

    private func scheduleOnboardingMemberCountRefresh() {
        guard clanId != 0 else { return }
        if let cachedCount = context.engine.clanData.getClanUsers(clanId: clanId)?.clanUsers.count,
           cachedCount > 0 {
            if cachedCount != sidebarMemberCount {
                updateMemberCount(cachedCount)
            }
            return
        }
        guard !onboardingMemberFetchInFlight else { return }
        if let last = lastOnboardingMemberFetchAt,
           Date().timeIntervalSince(last) < onboardingMemberFetchCooldown {
            return
        }
        onboardingMemberFetchInFlight = true
        Task { @MainActor [weak self] in
            defer { self?.onboardingMemberFetchInFlight = false }
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            do {
                let response = try await self.context.account.network.listClanUsers(
                    clanId: self.clanId,
                    token: token
                )
                self.lastOnboardingMemberFetchAt = Date()
                let count = response.clanUsers.count
                if count != self.sidebarMemberCount {
                    self.updateMemberCount(count)
                }
            } catch {}
        }
    }

    private func presentOnboardingBottomSheet() {
        refreshOnboardingState()
        if lastOnboardingState.isVisible {
            presentCreatorOnboardingBottomSheet()
            return
        }
        presentMemberOnboardingBottomSheet()
    }

    private func presentCreatorOnboardingBottomSheet() {
        let onboardingState = lastOnboardingState
        guard onboardingState.isVisible else { return }

        let createItem = ClanOnboardingActionItem(
            title: L(L10n.OnboardingClan.createChannel),
            iconName: "ClanSetting/CreateChannelIcon",
            iconBackgroundColor: UIColor(red: 0.00, green: 0.80, blue: 0.67, alpha: 1),
            isCompleted: onboardingState.createChannelCompleted,
            onPress: { [weak self] in
                self?.handleOnboardingCreateChannel(categoryId: onboardingState.welcomeChannelCategoryId)
            }
        )
        let inviteItem = ClanOnboardingActionItem(
            title: L(L10n.OnboardingClan.invite),
            iconName: "ClanSetting/InviteFriendIcon",
            iconBackgroundColor: UIColor(red: 0.98, green: 0.78, blue: 0.20, alpha: 1),
            isCompleted: onboardingState.inviteCompleted,
            onPress: { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self?.presentInviteClanSheet()
                }
            }
        )
        let sendMessageItem = ClanOnboardingActionItem(
            title: L(L10n.OnboardingClan.sendMessage),
            iconName: "ClanSetting/ChatIcon",
            iconBackgroundColor: UIColor(red: 0.20, green: 0.55, blue: 0.98, alpha: 1),
            isCompleted: onboardingState.sendMessageCompleted,
            onPress: { [weak self] in
                self?.handleOnboardingSendMessage(welcomeChannelId: onboardingState.welcomeChannelId)
            }
        )

        let vc = ClanOnboardingBottomSheetViewController(
            finishedStep: onboardingState.completedSteps,
            actionItems: [createItem, inviteItem, sendMessageItem]
        )
        present(vc, animated: true)
    }

    private func presentMemberOnboardingBottomSheet() {
        let state = lastMemberOnboardingState
        guard state.isVisible else { return }

        let rows = state.missions.enumerated().map { index, mission in
            let channelLabel = MemberOnboardingProgress.resolveChannelLabel(
                channelId: mission.channelId,
                context: context,
                clanId: clanId,
                channels: allChannels
            )
            return MemberOnboardingMissionRow(
                title: mission.title,
                subtitle: MemberOnboardingProgress.missionActionSubtitle(
                    taskType: mission.taskType,
                    channelLabel: channelLabel
                ),
                isCompleted: index < state.completedSteps,
                isActionable: index == state.completedSteps,
                onPress: { [weak self] in
                    guard let self else { return }
                    self.handleMemberOnboardingMission(
                        mission,
                        at: index,
                        completedSteps: self.lastMemberOnboardingState.completedSteps
                    )
                }
            )
        }

        present(MemberOnboardingBottomSheetViewController(
            finishedStep: state.completedSteps,
            totalSteps: state.missions.count,
            missions: rows
        ), animated: true)
    }

    private func handleMemberOnboardingMission(
        _ mission: MemberOnboardingMission,
        at index: Int,
        completedSteps: Int
    ) {
        MemberOnboardingProgress.performMission(
            mission,
            at: index,
            completedSteps: completedSteps,
            context: context,
            clanId: clanId,
            channels: allChannels,
            navigation: memberOnboardingChannelNavigation()
        )
    }

    private func memberOnboardingChannelNavigation() -> MemberOnboardingChannelNavigation {
        MemberOnboardingChannelNavigation(
            openChat: { [weak self] channel in
                self?.openChannelForOnboarding(channel)
            },
            presentVoice: { [weak self] channel in
                self?.presentJoinVoiceSheet(for: channel)
            },
            presentStream: { [weak self] channel in
                self?.presentJoinStreamSheet(for: channel)
            }
        )
    }

    private func handleOnboardingCreateChannel(categoryId: Int64) {
        guard clanId != 0 else { return }
        let resolvedCategoryId: Int64 = {
            if categoryId != 0 { return categoryId }
            if let first = categories.first(where: { $0.id != ChannelCategory.favoritesCategoryId }) {
                return first.id
            }
            return 0
        }()
        let createVc = CreateChannelViewController(
            context: context,
            clanId: clanId,
            categoryId: resolvedCategoryId
        )
        enclosingNavigationController?.pushViewController(createVc, animated: true)
    }

    private func handleOnboardingSendMessage(welcomeChannelId: Int64) {
        guard welcomeChannelId != 0 else { return }
        if let channel = allChannels.first(where: { $0.channelID == welcomeChannelId }) {
            openChannelForOnboarding(channel)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            do {
                let channels = try await MezonHTTPClient.shared.listChannelDescs(clanId: self.clanId, token: token)
                if let channel = channels.first(where: { $0.channelID == welcomeChannelId }) {
                    self.openChannelForOnboarding(channel)
                }
            } catch {}
        }
    }

    private func openChannelForOnboarding(_ channel: Mezon_Api_ChannelDescription) {
        if let home = parent as? HomeViewController {
            home.openChannelForOnboarding(channel)
            return
        }
        if let home = (enclosingNavigationController as? MezonRootController)?.homeController {
            home.openChannelForOnboarding(channel)
            return
        }
        select(channel: channel)
    }

    private func presentSettings() {
        let vc = ClanSettingsViewController(
            context: context,
            clanId: clanId,
            clanName: clanName,
            avatarURL: clanLogoURL
        )
        self.enclosingNavigationController?.pushViewController(vc, animated: true)
    }

    private func homeViewController() -> HomeViewController? {
        if let home = parent as? HomeViewController { return home }
        return (enclosingNavigationController as? MezonRootController)?.homeController
    }

    private func popToHomeIfNeeded() {
        guard let nav = enclosingNavigationController else { return }
        if let home = nav.viewControllers.first(where: { $0 is HomeViewController }) {
            nav.popToViewController(home, animated: false)
        }
    }

    private func presentLeaveClanConfirm() {
        presentClanRemovalConfirm(isLeaveClan: true)
    }

    private func presentDeleteClanConfirm() {
        presentClanRemovalConfirm(isLeaveClan: false)
    }

    private func presentClanRemovalConfirm(isLeaveClan: Bool) {
        guard clanId != 0 else { return }
        guard let presenter = topModalPresenter() else { return }
        let title = isLeaveClan
            ? L(L10n.DeleteClanModal.titleLeaveClan)
            : L(L10n.DeleteClanModal.title)
        let descriptionKey = isLeaveClan
            ? L10n.DeleteClanModal.descriptionLeaveClan
            : L10n.DeleteClanModal.description
        let content = String(format: L(descriptionKey), clanName)
        MezonConfirm.present(
            from: presenter,
            title: title,
            content: content,
            confirmTitle: L(L10n.DeleteClanModal.confirm),
            isDanger: true
        ) { [weak self] in
            if isLeaveClan {
                self?.handleLeaveClan()
            } else {
                self?.handleDeleteClan()
            }
        }
    }

    private func handleLeaveClan() {
        guard clanId != 0 else { return }
        guard let userId = Int64(context.account.id) else {
            Toast.error(L(L10n.DeleteClanModal.error))
            return
        }
        let removedClanId = clanId
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.DeleteClanModal.error))
                return
            }
            do {
                try await MezonHTTPClient.shared.removeClanUsers(
                    clanId: removedClanId,
                    userIds: [userId],
                    token: token
                )
                self.finishClanRemoval(removedClanId: removedClanId)
            } catch {
                Toast.error(L(L10n.DeleteClanModal.error))
            }
        }
    }

    private func handleDeleteClan() {
        guard clanId != 0 else { return }
        let removedClanId = clanId
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.DeleteClanModal.error))
                return
            }
            do {
                try await MezonHTTPClient.shared.deleteClanDesc(clanId: removedClanId, token: token)
                self.finishClanRemoval(removedClanId: removedClanId)
            } catch {
                Toast.error(L(L10n.DeleteClanModal.error))
            }
        }
    }

    private func finishClanRemoval(removedClanId: Int64) {
        popToHomeIfNeeded()
        homeViewController()?.clanListVC.removeClanAndSelectNext(removedClanId: removedClanId)
    }

    private func presentEventBottomSheet() {
        guard clanId != 0 else { return }
        let vc = EventViewerBottomSheetViewController(
            context: context,
            clanId: clanId,
            clanName: clanName,
            clanLogoURL: clanLogoURL,
            channels: allChannels
        )
        vc.onOpenChannel = { [weak self] channel in
            self?.dismissEventBottomSheets(animated: false) {
                self?.select(channel: channel)
            }
        }
        vc.onPresentJoinVoice = { [weak self] channel in
            guard let self, let presenter = self.topModalPresenter() else { return }
            self.presentJoinVoiceSheet(
                for: channel,
                from: presenter,
                onChat: { [weak self] in
                    self?.dismissEventBottomSheets(animated: false) {
                        self?.select(channel: channel)
                    }
                },
                onJoinVoice: { [weak self] in
                    self?.dismissEventBottomSheets(animated: false) {
                        self?.pushVoiceChannelRoom(for: channel)
                    }
                }
            )
        }
        present(vc, animated: true)
    }

    private func presentCreateCategory() {
        guard clanId != 0 else { return }
        guard context.rolePermissions.canManageRoles(clanId: clanId) else { return }
        let vc = CreateCategoryViewController(
            context: context,
            clanId: clanId,
            existingCategories: channelListCategoryDescs,
            onCreated: { [weak self] newCategory in
                self?.applyCreatedCategory(newCategory)
            }
        )
        enclosingNavigationController?.pushViewController(vc, animated: true)
    }

    private func applyCreatedCategory(_ category: Mezon_Api_CategoryDesc) {
        guard category.clanID == clanId || category.clanID == 0 else { return }
        if channelListCategoryDescs.contains(where: { $0.categoryID == category.categoryID }) { return }
        channelListCategoryDescs.append(category)

        let built = buildChannelCategories(
            allChannels,
            categoryDescs: channelListCategoryDescs,
            favoriteChannelIds: channelListFavoriteIds,
            collapsedIds: loadCollapsedCategoryIds()
        )
        let cats = applyBuiltCategoriesPreservingCollapse(built)
        categories = cats
        categoriesPipe.putNext(cats)
        persistFullChannelListCache(
            clanId: clanId,
            channels: allChannels,
            categoryDescs: channelListCategoryDescs,
            favoriteIds: channelListFavoriteIds,
            categories: cats
        )
        needsReloadPipe.putNext(())
    }

    private func presentInviteClanSheet() {
        guard clanId != 0 else { return }
        let vc = ClanInviteSheetViewController(context: context, clanId: clanId)
        vc.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            if let sheet = vc.sheetPresentationController {
                sheet.prefersGrabberVisible = true
                sheet.detents = [.medium(), .large()]
                sheet.selectedDetentIdentifier = .medium
            }
        }
        present(vc, animated: true)
    }

    private func presentCategoryActionSheet(_ category: ChannelCategory) {
        if category.id == ChannelCategory.favoritesCategoryId { return }
        if !self.context.rolePermissions.canManageChannel(clanId: self.clanId) { return }
        
        let vc = CategoryActionSheetController(
            categoryId: category.id,
            categoryName: category.name,
            clanName: clanName,
            clanAvatarURL: clanLogoURL,
            onAction: { [weak self] (action: CategoryAction) in
                guard let self else { return }
                switch action {
                case .createChannel:
                    let createVc = CreateChannelViewController(context: self.context, clanId: self.clanId, categoryId: category.id)
                    self.enclosingNavigationController?.pushViewController(createVc, animated: true)
                }
            }
        )
        if let window = self.view.window as? WindowHost {
            window.present(vc, on: .root, blockInteraction: false, completion: {})
        }
    }

    private func presentChannelActionSheet(_ channel: Mezon_Api_ChannelDescription) {
        let (isMuted, welcomeChannelId): (Bool, Int64?) = context.account.postbox.read { tx in
            let muted: Bool = {
                guard let record = tx.getNotificationSetting(entityId: channel.channelID) else { return false }
                return record.timeMuteSeconds != 0
            }()
            let welcome: Int64? = {
                guard let data = tx.getClan(id: self.clanId)?.data, !data.isEmpty,
                      let desc = try? Mezon_Api_ClanDesc(serializedBytes: data) else { return nil }
                return desc.welcomeChannelID
            }()
            return (muted, welcome)
        }
        let isFavorite = self.channelListFavoriteIds.contains(channel.channelID)
        let isThread = channel.type == MezonConstants.ChannelType.thread.rawValue
        let isGeneralChannel: Bool = {
            guard let welcomeChannelId else { return false }
            return channel.channelID == welcomeChannelId
        }()

        let canManage: Bool
        let canLeaveThread: Bool
        if isThread {
            let currentUserId = Int64(self.context.account.id) ?? 0
            let isCreator = channel.creatorID == currentUserId
            let isOwner = self.context.rolePermissions.isClanOwner(clanId: self.clanId)
            let isAdmin = self.context.rolePermissions.hasClanPermission(.administrator, clanId: self.clanId)
            let canManageThread = self.context.rolePermissions.canManageThread(clanId: self.clanId, channelId: channel.channelID)

            canManage = (isCreator && canManageThread) || isAdmin || isOwner
            canLeaveThread = !isCreator
        } else {
            canManage = self.context.rolePermissions.canManageChannel(clanId: self.clanId)
            canLeaveThread = false
        }

        let actionSheet = ChannelActionSheetController(
            channelId: channel.channelID,
            channelName: channel.channelLabel,
            clanName: clanName,
            clanAvatarURL: clanLogoURL,
            isFavorite: isFavorite,
            isMuted: isMuted,
            isThread: isThread,
            channelType: channel.type,
            canManageChannel: canManage,
            canLeaveThread: canLeaveThread,
            isGeneralChannel: isGeneralChannel,
            onAction: { [weak self] action in
                guard let self else { return }
                switch action {
                case .markAsRead:
                    self.handleMarkAsRead(channel)
                case .markFavorite:
                    self.handleMarkFavorite(channel)
                case .unmarkFavorite:
                    self.handleUnmarkFavorite(channel)
                case .copyLink:
                    let link = "https://mezon.ai/chat/clans/\(channel.clanID)/channels/\(channel.channelID)"
                    UIPasteboard.general.string = link
                    Toast.success(L(L10n.MessageAction.copied))
                case .mute:
                    self.presentMuteDurationSheet(channel)
                case .unmute:
                    self.handleMuteChannel(channel, mute: false)
                case .notificationSettings:
                    self.presentNotificationSettings(channel)
                case .threads:
                    let vc = ThreadListViewController(
                        context: self.context,
                        clanId: channel.clanID,
                        parentChannelId: channel.channelID,
                        parentCategoryId: channel.categoryID,
                        parentChannelLabel: channel.channelLabel,
                        composerParentChannel: channel
                    )
                    self.enclosingNavigationController?.pushViewController(vc, animated: true)
                case .editChannel:
                    self.presentChannelSettings(channel)
                case .deleteChannel:
                    self.presentDeleteChannelConfirm(channel)
                case .leaveThread:
                    self.presentLeaveThreadConfirm(channel)
                }
            }
        )
        if let window = self.view.window as? WindowHost {
            window.present(actionSheet, on: .root, blockInteraction: false, completion: {})
        }
        
        fetchNotificationSettingForBottomsheet(channelId: channel.channelID)
    }
    
    private func fetchNotificationSettingForBottomsheet(channelId: Int64) {
        Task { @MainActor in
            let startEpoch = context.sessionEpoch
            guard let token = await context.getTokenPreferringCachedSkipSessionReadyWait() else { return }
            do {
                let noti = try await MezonHTTPClient.shared.getNotificationChannel(channelId: channelId, token: token)
                guard context.isStillCurrentSession(epoch: startEpoch) else { return }
                let record = NotificationSettingRecord(id: 0, entityId: channelId, scope: .channel, notificationSettingType: noti.notificationSettingType, timeMuteSeconds: UInt32(bitPattern: noti.timeMuteSeconds), active: noti.active)
                context.account.postbox.write { tx in
                    tx.updateNotificationSetting(record)
                }

                NotificationCenter.default.post(
                    name: .mezonNotificationSettingDidUpdate,
                    object: nil,
                    userInfo: ["channelId": channelId, "record": record]
                )
            } catch {
            }
        }
    }

    private func handleMarkAsRead(_ channel: Mezon_Api_ChannelDescription) {
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                try await MezonHTTPClient.shared.markAsRead(channelId: channel.channelID, clanId: channel.clanID, categoryId: channel.categoryID, token: token)
                NotificationCenter.default.post(
                    name: Notification.Name("MezonChannelMarkedAsRead"),
                    object: nil,
                    userInfo: ["channelId": channel.channelID, "clanId": channel.clanID]
                )
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func handleMarkFavorite(_ channel: Mezon_Api_ChannelDescription) {
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                let _ = try await MezonHTTPClient.shared.addFavoriteChannel(channelId: channel.channelID, clanId: channel.clanID, token: token)
                channelListFavoriteIds.insert(channel.channelID)
                
                let built = buildChannelCategories(
                    allChannels,
                    categoryDescs: channelListCategoryDescs,
                    favoriteChannelIds: channelListFavoriteIds,
                    collapsedIds: loadCollapsedCategoryIds()
                )
                let cats = applyBuiltCategoriesPreservingCollapse(built)
                categories = cats
                categoriesPipe.putNext(cats)
                persistFullChannelListCache(clanId: clanId, channels: allChannels, categoryDescs: channelListCategoryDescs, favoriteIds: channelListFavoriteIds, categories: cats)
                needsReloadPipe.putNext(())
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func handleUnmarkFavorite(_ channel: Mezon_Api_ChannelDescription) {
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                try await MezonHTTPClient.shared.removeFavoriteChannel(channelId: channel.channelID, clanId: channel.clanID, token: token)
                channelListFavoriteIds.remove(channel.channelID)
                
                let built = buildChannelCategories(
                    allChannels,
                    categoryDescs: channelListCategoryDescs,
                    favoriteChannelIds: channelListFavoriteIds,
                    collapsedIds: loadCollapsedCategoryIds()
                )
                let cats = applyBuiltCategoriesPreservingCollapse(built)
                categories = cats
                categoriesPipe.putNext(cats)
                persistFullChannelListCache(clanId: clanId, channels: allChannels, categoryDescs: channelListCategoryDescs, favoriteIds: channelListFavoriteIds, categories: cats)
                needsReloadPipe.putNext(())
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func presentMuteDurationSheet(_ channel: Mezon_Api_ChannelDescription) {
        let isThread = channel.type == MezonConstants.ChannelType.thread.rawValue
        let vc = MuteDurationViewController(
            channelName: channel.channelLabel,
            channelId: channel.channelID,
            clanId: channel.clanID,
            context: self.context,
            isThread: isThread
        ) { [weak self] duration in
            self?.handleMuteChannel(channel, muteTimeSeconds: duration.seconds)
        }
        self.enclosingNavigationController?.pushViewController(vc)
    }

    private func handleMuteChannel(_ channel: Mezon_Api_ChannelDescription, mute: Bool) {
        handleMuteChannel(channel, muteTimeSeconds: 0)
    }

    private func handleMuteChannel(_ channel: Mezon_Api_ChannelDescription, muteTimeSeconds: Int32) {
        ChannelMuteHelper.setMuteChannel(
            context: context,
            channelId: channel.channelID,
            clanId: channel.clanID,
            muteTimeSeconds: muteTimeSeconds
        )
    }

    private func presentNotificationSettings(_ channel: Mezon_Api_ChannelDescription) {
        let currentTypeInt = context.account.postbox.read { tx in
            tx.getNotificationSetting(entityId: channel.channelID)?.notificationSettingType
        }
        let currentType: ChannelNotificationType
        if let typeInt = currentTypeInt, let type = ChannelNotificationType(rawValue: typeInt) {
            currentType = type
        } else {
            currentType = .useDefault
        }
        
        let sheet = NotificationSettingsSheetController(
            channelId: channel.channelID,
            clanId: channel.clanID,
            context: context,
            currentType: currentType,
            defaultLabel: L(L10n.NotificationSettings.allMessages)
        )
        if let window = self.view.window as? WindowHost {
            window.present(sheet, on: .root, blockInteraction: false, completion: {})
            sheet.animateIn()
        }
    }

    private func presentDeleteChannelConfirm(_ channel: Mezon_Api_ChannelDescription) {
        let isThread = channel.type == MezonConstants.ChannelType.thread.rawValue
        let title = isThread ? L(L10n.ChannelAction.deleteThread) : L(L10n.Channel.delete)
        let message = isThread ? L(L10n.Channel.deleteThreadConfirm) : L(L10n.Channel.deleteConfirm)

        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        alert.addAction(UIAlertAction(title: title, style: .destructive, handler: { [weak self] _ in
            self?.handleDeleteChannel(channel)
        }))
        if let rootVC = self.view.window?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController { topVC = presented }
            topVC.present(alert, animated: true)
        }
    }

    private func presentLeaveThreadConfirm(_ channel: Mezon_Api_ChannelDescription) {
        let title = L(L10n.ChannelAction.leaveThread)
        let message = L(L10n.ChannelAction.leaveThreadConfirm)

        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        alert.addAction(UIAlertAction(title: title, style: .destructive, handler: { [weak self] _ in
            self?.handleLeaveThread(channel)
        }))
        if let rootVC = self.view.window?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController { topVC = presented }
            topVC.present(alert, animated: true)
        }
    }

    private func removeChannelLocally(channelId: Int64) {
        clearPendingMentionUnreadFloor(clanId: clanId, channelId: channelId)
        allChannels.removeAll { $0.channelID == channelId }

        let cats = applyCategoriesAfterFetch(
            mergedChannels: allChannels,
            categoryDescs: channelListCategoryDescs,
            favoriteIds: channelListFavoriteIds
        )
        categories = cats
        categoriesPipe.putNext(categories)
        persistFullChannelListCache(clanId: clanId, channels: allChannels, categoryDescs: channelListCategoryDescs, favoriteIds: channelListFavoriteIds, categories: categories)
        reconcileSelectionWithLoadedChannels()
        needsReloadPipe.putNext(())
    }

    private func handleDeleteChannel(_ channel: Mezon_Api_ChannelDescription) {
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                try await MezonHTTPClient.shared.deleteChannelDesc(channelId: channel.channelID, clanId: channel.clanID, token: token)
                NotificationCenter.default.post(
                    name: .mezonChannelDeletedLocally,
                    object: nil,
                    userInfo: ["clanId": channel.clanID, "channelId": channel.channelID]
                )
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func handleLeaveThread(_ channel: Mezon_Api_ChannelDescription) {
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                try await MezonHTTPClient.shared.leaveThread(clanId: channel.clanID, channelId: channel.channelID, token: token)
                NotificationCenter.default.post(
                    name: .mezonChannelDeletedLocally,
                    object: nil,
                    userInfo: ["clanId": channel.clanID, "channelId": channel.channelID]
                )
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func presentChannelSettings(_ channel: Mezon_Api_ChannelDescription) {
        let vc = ChannelSettingsViewController(
            context: context,
            clanId: channel.clanID,
            channelId: channel.channelID,
            categoryId: channel.categoryID,
            categoryName: channel.categoryName,
            channelType: channel.type,
            channelPrivate: channel.channelPrivate == 1,
            channelName: channel.channelLabel,
            channelTopic: channel.topic
        )
        self.enclosingNavigationController?.pushViewController(vc, animated: true)
    }

    func refresh() { fetchChannels() }

    func fetchChannels() {
        guard clanId != 0 else { return }
        if !allChannels.isEmpty || !categories.isEmpty {
            channelListNode.suppressNextLoadingFinishedReveal()
        }
        isLoading = true
        errorMessage = nil

        needsReloadPipe.putNext(())
        lastChannelFetchAtByClanId.removeValue(forKey: clanId)
        lastBadgeCountFetchAtByClanId.removeValue(forKey: clanId)
        fetchChannelsWithoutLoadingSignal(allowEmptyChannelAppsOverwrite: true, force: true)
    }

    @objc private func handleThemeChange() { channelListNode.applyTheme() }

    private static func int64UserInfo(_ value: Any?) -> Int64? {
        if let n = value as? Int64 { return n }
        if let n = value as? Int { return Int64(n) }
        if let n = value as? NSNumber { return n.int64Value }
        return nil
    }

    @objc private func handleNewMessageReceived(_ notification: Notification) {
        let rawChannelId = notification.userInfo?["channelId"]
        let rawClanId = notification.userInfo?["clanId"]

        guard let channelId = Self.int64UserInfo(rawChannelId),
              let clanId = Self.int64UserInfo(rawClanId) else { return }

        let senderId: String? = {
            let v = notification.userInfo?["senderId"]
            if let s = v as? String { return s }
            if let n = v as? Int64 { return String(n) }
            if let n = v as? Int { return String(n) }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }()
        guard let senderId else { return }

        let ts: UInt32
        if let t = notification.userInfo?["timestampSeconds"] as? UInt32 { ts = t }
        else if let t = notification.userInfo?["timestampSeconds"] as? Int { ts = UInt32(clamping: t) }
        else { ts = UInt32(Date().timeIntervalSince1970) }

        guard clanId == self.clanId, clanId != 0 else { return }
        guard senderId != context.currentUser?.id else { return }

        let apiMessage: Mezon_Api_ChannelMessage? = (notification.userInfo?["serializedChannelMessage"] as? Data).flatMap { try? Mezon_Api_ChannelMessage(serializedBytes: $0) }
        var topicId = Self.int64UserInfo(notification.userInfo?["topicId"]) ?? 0
        if let m = apiMessage, topicId == 0, m.topicID != 0 { topicId = m.topicID }
        if topicId != 0 {
            if ActiveChannelTracker.currentChannelId == topicId { return }
        } else {
            if ActiveChannelTracker.currentChannelId == channelId { return }
        }

        var updated = false
        for i in 0..<allChannels.count {
            if allChannels[i].channelID == channelId {
                var header = allChannels[i].lastSentMessage
                header.timestampSeconds = ts
                allChannels[i].lastSentMessage = header
                updated = true
            }
        }

        if topicId != 0 {
            for i in 0..<allChannels.count {
                if allChannels[i].channelID == topicId {
                    var header = allChannels[i].lastSentMessage
                    header.timestampSeconds = ts
                    allChannels[i].lastSentMessage = header
                    updated = true
                }
            }
        }

        if let apiMessage {
            let currentUserId = context.currentUser?.id
            let roleIds = ClanListViewController.getCurrentUserRoleIds(context: context)
            let isMentioned = ClanListViewController.checkMessageMentionsUser(
                apiMessage,
                currentUserId: currentUserId,
                currentUserRoleIds: roleIds
            )
            if isMentioned, apiMessage.messageID != 0 {
                if topicId != 0 {
                    let parentId = parentChannelIdForThreadBadge(topicId: topicId, messageChannelId: channelId)
                    if applyMentionEventUnreadIfNeeded(
                        clanId: clanId, messageId: apiMessage.messageID, parentChannelId: parentId, threadChannelId: topicId, ts: ts
                    ) { updated = true }
                } else {
                    if applyMentionEventUnreadIfNeeded(
                        clanId: clanId, messageId: apiMessage.messageID, parentChannelId: channelId, threadChannelId: nil, ts: ts
                    ) { updated = true }
                }
            }
        }

        guard updated else { return }
        rebuildAndReload()
    }

    @objc private func handleMentionReceived(_ notification: Notification) {
        guard let channelId = Self.int64UserInfo(notification.userInfo?["channelId"]),
              let clanId = Self.int64UserInfo(notification.userInfo?["clanId"]) else { return }
        guard clanId == self.clanId, clanId != 0 else { return }
        let isParentOfTopic = notification.userInfo?["isParentOfTopic"] as? Bool == true
        let messageId = notification.userInfo?["messageId"] as? String ?? ""
        let ts = notification.userInfo?["timestampSeconds"]
        let tsU32: UInt32? = {
            if let t = ts as? UInt32 { return t }
            if let t = ts as? Int { return UInt32(clamping: t) }
            if let t = ts as? NSNumber { return t.uint32Value }
            return nil
        }()
        if !messageId.isEmpty, messageId != "0", let mid = Int64(messageId), mid != 0 {
            var updated = false
            let topicFromNoti = Self.int64UserInfo(notification.userInfo?["topicId"]) ?? 0
            if topicFromNoti != 0 {
                let parentId = isParentOfTopic
                    ? channelId
                    : parentChannelIdForThreadBadge(topicId: topicFromNoti, messageChannelId: channelId)
                if applyMentionEventUnreadIfNeeded(
                    clanId: clanId, messageId: mid, parentChannelId: parentId, threadChannelId: topicFromNoti, ts: tsU32
                ) { updated = true }
            } else {
                if applyMentionEventUnreadIfNeeded(
                    clanId: clanId, messageId: mid, parentChannelId: channelId, threadChannelId: nil, ts: tsU32
                ) { updated = true }
            }
            if updated { rebuildAndReload() }
            return
        }
        if hasRecentMentionSentinel(clanId: clanId, channelId: channelId, ts: tsU32) { return }
        let dedupKey: String
        if !messageId.isEmpty, messageId != "0" {
            dedupKey = "\(channelId)_\(messageId)"
        } else {
            dedupKey = "\(channelId)_\(ts ?? 0)"
        }
        guard !processedBadgeKeys.contains(dedupKey) else { return }
        processedBadgeKeys.insert(dedupKey)
        if processedBadgeKeys.count > 1500 { processedBadgeKeys.removeAll() }
        if bumpMentionUnread(clanId: clanId, channelId: channelId) {
            rebuildAndReload()
        }
    }

    private func applyBuiltCategoriesPreservingCollapse(_ built: [ChannelCategory]) -> [ChannelCategory] {
        built.map { cat in
            if let existing = categories.first(where: { $0.id == cat.id }) {
                return ChannelCategory(
                    id: cat.id,
                    name: cat.name,
                    isCollapsed: existing.isCollapsed,
                    channels: cat.channels,
                    orderedThreadChildren: cat.orderedThreadChildren,
                    favoriteFlatChannels: cat.favoriteFlatChannels
                )
            }
            return cat
        }
    }

    private func threadChildrenIdsByParent(_ cat: ChannelCategory) -> [Int64: [Int64]] {
        cat.orderedThreadChildren.mapValues { $0.map(\.channelID) }
    }

    private func categoriesStructureMatches(_ built: [ChannelCategory], _ existing: [ChannelCategory]) -> Bool {
        guard !existing.isEmpty, built.count == existing.count else { return false }
        return zip(built, existing).allSatisfy { builtCat, existingCat in
            builtCat.id == existingCat.id
            && builtCat.name == existingCat.name
            && builtCat.isCollapsed == existingCat.isCollapsed
            && (builtCat.favoriteFlatChannels?.map(\.channelID) ?? []) == (existingCat.favoriteFlatChannels?.map(\.channelID) ?? [])
            && builtCat.channels.map(\.channelID) == existingCat.channels.map(\.channelID)
            && threadChildrenIdsByParent(builtCat) == threadChildrenIdsByParent(existingCat)
        }
    }

    private func resolvedFavoriteIdsForFetch(_ fetched: Set<Int64>) -> Set<Int64> {
        if !fetched.isEmpty { return fetched }
        return channelListFavoriteIds
    }

    private func applyCategoriesAfterFetch(
        mergedChannels: [Mezon_Api_ChannelDescription],
        categoryDescs: [Mezon_Api_CategoryDesc],
        favoriteIds: Set<Int64>
    ) -> [ChannelCategory] {
        let collapsed = loadCollapsedCategoryIds()
        let built = buildChannelCategories(
            mergedChannels,
            categoryDescs: categoryDescs,
            favoriteChannelIds: favoriteIds,
            collapsedIds: collapsed
        )
        let resolved = applyBuiltCategoriesPreservingCollapse(built)
        let final = injectFavoritesCategoryIfNeeded(
            enrichCategoryNames(resolved, channels: mergedChannels, categoryDescs: categoryDescs),
            channels: mergedChannels,
            favoriteChannelIds: favoriteIds,
            collapsedIds: collapsed
        )
        let ordered: [ChannelCategory]
        if categories.isEmpty {
            ordered = final
        } else {
            let fallback = globalParentOrder(from: mergedChannels)
            ordered = applySnapshotChannelOrder(final, snapshot: categories, globalFallbackOrder: fallback)
        }
        return filterCategoriesToKnownChannels(ordered, channels: mergedChannels)
    }

    @MainActor
    private func applyNetworkChannelListResult(
        clanId: Int64,
        channels: [Mezon_Api_ChannelDescription],
        categoryDescs: [Mezon_Api_CategoryDesc],
        favoriteIds: Set<Int64>,
        allowEmptyApps: Bool,
        source: String
    ) {
        guard isCurrentSessionAlive else {
            clearInflightChannelFetchIfMatches(clanId: clanId)
            return
        }
        guard self.clanId == clanId else {
            clearInflightChannelFetchIfMatches(clanId: clanId)
            return
        }

        let resolvedCategoryDescs = categoryDescs.isEmpty ? channelListCategoryDescs : categoryDescs
        let resolvedFavoriteIds = resolvedFavoriteIdsForFetch(favoriteIds)
        channelListCategoryDescs = resolvedCategoryDescs
        channelListFavoriteIds = resolvedFavoriteIds

        let previousChannels = allChannels
        var immediate = preservePendingMentionUnread(in: channels, clanId: clanId)
        immediate = mergeCachedUnreadCounts(into: immediate, cached: previousChannels)
        allChannels = immediate
        emptyChannelRetryCountByClanId[clanId] = 0
        let cats = applyCategoriesAfterFetch(
            mergedChannels: immediate,
            categoryDescs: resolvedCategoryDescs,
            favoriteIds: resolvedFavoriteIds
        )
        categories = cats
        channelsLoadedPromise.set(true)
        syncSelectedChannelFromStoredPreferences()
        categoriesPipe.putNext(cats)
        scheduleCategoryDescsRefreshIfNeeded()
        fetchChannelApps(allowEmptyOverwrite: allowEmptyApps)
        persistFullChannelListCache(
            clanId: clanId,
            channels: immediate,
            categoryDescs: resolvedCategoryDescs,
            favoriteIds: resolvedFavoriteIds,
            categories: cats
        )

        needsAuthoritativeNetworkReconcile = false
        channelListNode.endRefreshing()
        isLoadingPipe.putNext(false)
        postClanSidebarUnreadDerivedFromCurrentChannels()
        refreshOnboardingState()
        clearInflightChannelFetchIfMatches(clanId: clanId)

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.applyChannelBadgeCounts(clanId: clanId, force: true, emitReload: false)
            self.needsReloadPipe.putNext(())
        }
    }

    private func scheduleCategoryDescsRefreshIfNeeded() {
        guard clanId != 0, NetworkMonitor.shared.isConnected else { return }
        let hasUnnamedCategory = categories.contains(where: {
            $0.id != ChannelCategory.favoritesCategoryId && $0.name.isEmpty
        })
        guard hasUnnamedCategory || channelListCategoryDescs.isEmpty else { return }
        guard !categoryDescsRefreshScheduled else { return }
        categoryDescsRefreshScheduled = true
        let clanId = self.clanId
        Task { @MainActor [weak self] in
            defer { self?.categoryDescsRefreshScheduled = false }
            for attempt in 0..<4 {
                guard let self, self.clanId == clanId else { return }
                guard self.categories.contains(where: {
                    $0.id != ChannelCategory.favoritesCategoryId && $0.name.isEmpty
                }) || self.channelListCategoryDescs.isEmpty else { return }
                guard let token = await self.context.getTokenPreferringCachedSkipSessionReadyWait() else { return }
                let descs = await Self.listCategoryDescsOrEmpty(
                    network: MezonHTTPClient.shared, clanId: clanId, token: token
                )
                if self.clanId == clanId, !descs.isEmpty {
                    self.channelListCategoryDescs = descs
                    let cats = self.applyCategoriesAfterFetch(
                        mergedChannels: self.allChannels,
                        categoryDescs: descs,
                        favoriteIds: self.channelListFavoriteIds
                    )
                    self.categories = cats
                    self.categoriesPipe.putNext(cats)
                    self.needsReloadPipe.putNext(())
                    self.persistFullChannelListCache(
                        clanId: clanId,
                        channels: self.allChannels,
                        categoryDescs: descs,
                        favoriteIds: self.channelListFavoriteIds,
                        categories: cats
                    )
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000)
            }
        }
    }

    private func rebuildAndReload() {
        let cats = applyCategoriesAfterFetch(
            mergedChannels: allChannels,
            categoryDescs: channelListCategoryDescs,
            favoriteIds: channelListFavoriteIds
        )
        categories = cats
        categoriesPipe.putNext(categories)
        needsReloadPipe.putNext(())
        postClanSidebarUnreadDerivedFromCurrentChannels()
        refreshOnboardingState()
    }

    private func postClanSidebarUnreadDerivedFromCurrentChannels() {
        guard clanId != 0 else { return }
        guard !allChannels.isEmpty else { return }
        let total = allChannels.reduce(Int32(0)) { $0 + $1.countMessUnread }
        NotificationCenter.default.post(
            name: Notification.Name("MezonClanChannelUnreadDerived"),
            object: nil,
            userInfo: ["clanId": clanId, "totalUnread": total]
        )
    }

    @objc private func handleChannelMarkedAsRead(_ notification: Notification) {
        guard let channelId = Self.int64UserInfo(notification.userInfo?["channelId"]) else { return }
        let notificationClanId = Self.int64UserInfo(notification.userInfo?["clanId"]) ?? clanId
        guard notificationClanId == 0 || notificationClanId == clanId else { return }
        clearPendingMentionUnreadFloor(clanId: notificationClanId == 0 ? clanId : notificationClanId, channelId: channelId)
        let now = UInt32(Date().timeIntervalSince1970)
        var didClearUnreadState = false
        for i in 0..<allChannels.count {
            if allChannels[i].channelID == channelId {
                let ch = allChannels[i]
                if ch.countMessUnread != 0
                    || (ch.hasLastSentMessage
                        && ch.lastSeenMessage.timestampSeconds < ch.lastSentMessage.timestampSeconds) {
                    didClearUnreadState = true
                }
                allChannels[i].countMessUnread = 0
                allChannels[i].lastSeenMessage.timestampSeconds = now
            }
        }
        rebuildAndReload()
        if didClearUnreadState, clanId != 0 {
            persistFullChannelListCache(
                clanId: clanId,
                channels: allChannels,
                categoryDescs: channelListCategoryDescs,
                favoriteIds: channelListFavoriteIds,
                categories: categories
            )
        }
    }

    private func setCategories(_ v: [ChannelCategory]) { categories = v; categoriesPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setSelectedChannelId(_ v: Int64?) {
        guard selectedChannelId != v else { return }
        selectedChannelId = v
        selectedChannelIdPipe.putNext(v)
    }

    private func setSelectedChannel(_ v: Mezon_Api_ChannelDescription?) {
        guard selectedChannel != v else { return }
        selectedChannel = v
        selectedChannelPipe.putNext(v)
    }
    private func setIsLoading(_ v: Bool) {
        if !v { cancelDeferredSkeletonReveal() }
        isLoading = v
        isLoadingPipe.putNext(v)
        needsReloadPipe.putNext(())
    }
    private func setErrorMessage(_ v: String?) { errorMessage = v; errorMessagePipe.putNext(v) }

    private func scheduleDeferredSkeletonRevealIfStillEmpty() {
        let pendingClanId = clanId
        cancelDeferredSkeletonReveal()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.clanId == pendingClanId, self.clanId != 0 else { return }
            guard self.categories.isEmpty else { return }
            guard NetworkMonitor.shared.isConnected else { return }
            self.isLoading = true
            self.isLoadingPipe.putNext(true)
            self.needsReloadPipe.putNext(())
        }
        pendingSkeletonRevealItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + skeletonRevealDelay, execute: item)
    }

    private func cancelDeferredSkeletonReveal() {
        pendingSkeletonRevealItem?.cancel()
        pendingSkeletonRevealItem = nil
    }

    private func clearCurrentChannelSelection() {
        guard selectedChannelId != nil || selectedChannel != nil else { return }
        setSelectedChannelId(nil)
        setSelectedChannel(nil)
        if clanId != 0 {
            context.clearPersistedSelectedChannelPreference(forClanId: clanId)
        }
        needsReloadPipe.putNext(())
    }

    func load(clanId: Int64, clanName: String) {
        if clanId != self.clanId {
            fetchDisposable.set(nil)
            inflightChannelFetchClanId = 0
        }
        self.clanId = clanId
        self.clanName = clanName
        refreshChannelEventStatuses()
        emptyChannelRetryCountByClanId[clanId] = 0
        self.showEmptyCategoriesEnabled = loadShowEmptyCategoriesPreference(clanId: clanId)
        errorMessage = nil

        restoreSelectionFromPostboxForCurrentClanOnly()

        let pendingCache: (channels: [Mezon_Api_ChannelDescription], meta: ChannelListCachedMeta?, layoutOrdered: Bool)? =
            clanId != 0 ? resolveChannelCachePayloadForDisplay(clanId: clanId) : nil
        var appliedCacheOnLoad = false

        if clanId != 0, let cache = pendingCache {
            appliedCacheOnLoad = true
            applyResolvedChannelCachePayload(clanId: clanId, channels: cache.channels, meta: cache.meta, layoutOrdered: cache.layoutOrdered)
        } else {
            channelsLoadedPromise.set(false)
            channelListCategoryDescs = []
            channelListFavoriteIds = []
            allChannels = []
            categories = []
        }
        restoreCachedChannelApps(clanId: clanId)
        if clanId == 0 || !NetworkMonitor.shared.isConnected {
            channelListNode.setChannelAppsLoadingIndicator(false)
        } else {
            fetchChannelAppsInBackground()
        }
        let willFetchFromNetwork = clanId != 0 && NetworkMonitor.shared.isConnected
        if willFetchFromNetwork && (pendingCache == nil || categoriesContainOrphanUnnamedBucket()) {
            isLoading = true
            cancelDeferredSkeletonReveal()
        } else {
            isLoading = false
            cancelDeferredSkeletonReveal()
        }
        needsReloadPipe.putNext(())
        if clanId != 0, !allChannels.isEmpty {
            postClanSidebarUnreadDerivedFromCurrentChannels()
        }

        if NetworkMonitor.shared.isConnected {
            if appliedCacheOnLoad {
                scheduleAuthoritativeNetworkReconcileIfNeeded(reason: "loadAfterCache")
            } else {
                scheduleChannelListNetworkFetch(allowEmptyChannelAppsOverwrite: false)
            }
        }
        refreshMemberOnboardingState()
        scheduleMemberOnboardingDataFetch()
    }

    private func scheduleAuthoritativeNetworkReconcileIfNeeded(reason: String) {
        guard clanId != 0 else { return }
        guard needsAuthoritativeNetworkReconcile else {
            return
        }
        guard NetworkMonitor.shared.isConnected else {
            return
        }
        needsAuthoritativeNetworkReconcile = false
        lastChannelFetchAtByClanId.removeValue(forKey: clanId)
        fetchChannelsWithoutLoadingSignal(allowEmptyChannelAppsOverwrite: false, force: true)
    }

    private func scheduleChannelListNetworkFetch(allowEmptyChannelAppsOverwrite: Bool) {
        guard clanId != 0 else { return }
        if inflightChannelFetchClanId == clanId {
            return
        }
        if let last = lastChannelFetchAtByClanId[clanId],
           Date().timeIntervalSince(last) < channelFetchCooldown {
            if recoverChannelListDisplayFromCache() { return }
            if !allChannels.isEmpty {
                cancelDeferredSkeletonReveal()
                isLoading = false
                isLoadingPipe.putNext(false)
                needsReloadPipe.putNext(())
                return
            }
        }
        fetchChannelsWithoutLoadingSignal(allowEmptyChannelAppsOverwrite: allowEmptyChannelAppsOverwrite)
    }

    private var inflightChannelFetchClanId: Int64 = 0
    private var needsAuthoritativeNetworkReconcile = false
    private var lastChannelFetchAtByClanId: [Int64: Date] = [:]
    private let channelFetchCooldown: TimeInterval = 5.0
    private var emptyChannelRetryCountByClanId: [Int64: Int] = [:]
    private let maxEmptyChannelFetchRetries = 4

    private var channelListNeedsFetch: Bool {
        guard clanId != 0 else { return false }
        return allChannels.isEmpty
    }

    private func reconcileChannelListDataIfNeeded() {
        guard channelListNeedsFetch else { return }
        guard NetworkMonitor.shared.isConnected else { return }
        guard inflightChannelFetchClanId != clanId else { return }
        scheduleChannelListNetworkFetch(allowEmptyChannelAppsOverwrite: false)
    }

    private func fetchChannelsWithoutLoadingSignal(allowEmptyChannelAppsOverwrite: Bool = false, force: Bool = false) {
        guard clanId != 0 else {
            cancelDeferredSkeletonReveal()
            isLoading = false
            channelListNode.setChannelAppsLoadingIndicator(false)
            needsReloadPipe.putNext(())
            return
        }
        guard NetworkMonitor.shared.isConnected else {
            cancelDeferredSkeletonReveal()
            isLoading = false
            isLoadingPipe.putNext(false)
            channelListNode.setChannelAppsLoadingIndicator(false)
            needsReloadPipe.putNext(())
            return
        }
        let clanId = self.clanId
        if inflightChannelFetchClanId == clanId {
            return
        }
        let bypassFetchCooldown = force || channelListNeedsFetch || needsCategoryMetaRefresh() || needsOrphanCategoryRepair()
        if !bypassFetchCooldown,
           let last = lastChannelFetchAtByClanId[clanId],
           Date().timeIntervalSince(last) < channelFetchCooldown {
            if channelListNeedsFetch {
                scheduleEmptyChannelRetryIfNeeded(clanId: clanId)
            }
            cancelDeferredSkeletonReveal()
            isLoading = false
            isLoadingPipe.putNext(false)
            channelListNode.setChannelAppsLoadingIndicator(false)
            needsReloadPipe.putNext(())
            return
        }
        inflightChannelFetchClanId = clanId
        lastChannelFetchAtByClanId[clanId] = Date()

        let signal = channelListSignal(clanId: clanId)
            |> map { payload -> FetchResult in .success(payload.channels, payload.categoryDescs, payload.favoriteChannelIds) }
            |> `catch` { (error: ChannelFetchError) -> Signal<FetchResult, NoError> in .single(.failure(error.localizedDescription)) }
            |> deliverOnMainQueue

        let allowEmptyApps = allowEmptyChannelAppsOverwrite
        let hadCachedChannels = !self.allChannels.isEmpty
        var didDeliverFetchResult = false
        fetchDisposable.set(signal.start(next: { [weak self] result in
                didDeliverFetchResult = true
                guard let self else { return }
                guard self.isCurrentSessionAlive else {
                    self.clearInflightChannelFetchIfMatches(clanId: clanId)
                    return
                }
                guard self.clanId == clanId else {
                    self.clearInflightChannelFetchIfMatches(clanId: clanId)
                    return
                }
                self.cancelDeferredSkeletonReveal()
                self.isLoading = false
                switch result {
                case .success(let channels, let categoryDescs, let favoriteIds):
                    if channels.isEmpty && hadCachedChannels {
                        if !categoryDescs.isEmpty || !favoriteIds.isEmpty {
                            let resolvedCategoryDescs = categoryDescs.isEmpty ? self.channelListCategoryDescs : categoryDescs
                            let resolvedFavoriteIds = self.resolvedFavoriteIdsForFetch(favoriteIds)
                            self.channelListCategoryDescs = resolvedCategoryDescs
                            self.channelListFavoriteIds = resolvedFavoriteIds
                            self.categories = self.applyCategoriesAfterFetch(
                                mergedChannels: self.allChannels,
                                categoryDescs: resolvedCategoryDescs,
                                favoriteIds: resolvedFavoriteIds
                            )
                            self.categoriesPipe.putNext(self.categories)
                        }
                        self.channelsLoadedPromise.set(true)
                        self.channelListNode.endRefreshing()
                        self.isLoadingPipe.putNext(false)
                        self.fetchChannelApps(allowEmptyOverwrite: allowEmptyApps)
                        self.needsReloadPipe.putNext(())
                        Task { @MainActor [weak self] in
                            await self?.applyChannelBadgeCounts(clanId: clanId, force: true)
                        }
                        if !categoryDescs.isEmpty {
                            self.lastChannelFetchAtByClanId.removeValue(forKey: clanId)
                        }
                        self.clearInflightChannelFetchIfMatches(clanId: clanId)
                        return
                    }
                    if channels.isEmpty, let recoveredChannels = self.recoveryChannelsForEmptyFetch(clanId: clanId) {
                        self.applyNetworkChannelListResult(
                            clanId: clanId,
                            channels: recoveredChannels,
                            categoryDescs: categoryDescs,
                            favoriteIds: favoriteIds,
                            allowEmptyApps: allowEmptyApps,
                            source: "recovery"
                        )
                        self.lastChannelFetchAtByClanId.removeValue(forKey: clanId)
                        return
                    }
                    if channels.isEmpty {
                        self.channelsLoadedPromise.set(!self.allChannels.isEmpty)
                        self.channelListNode.endRefreshing()
                        self.isLoadingPipe.putNext(false)
                        self.fetchChannelApps(allowEmptyOverwrite: allowEmptyApps)
                        self.needsReloadPipe.putNext(())
                        self.lastChannelFetchAtByClanId.removeValue(forKey: clanId)
                        self.clearInflightChannelFetchIfMatches(clanId: clanId)
                        if self.allChannels.isEmpty {
                            self.scheduleEmptyChannelRetryIfNeeded(clanId: clanId)
                        }
                        return
                    }
                    self.applyNetworkChannelListResult(
                        clanId: clanId,
                        channels: channels,
                        categoryDescs: categoryDescs,
                        favoriteIds: favoriteIds,
                        allowEmptyApps: allowEmptyApps,
                        source: "channelListSignal"
                    )
                    return
                case .failure(let msg):
                    self.errorMessage = msg
                    self.errorMessagePipe.putNext(msg)
                    self.channelListNode.setChannelAppsLoadingIndicator(false)
                    if !self.allChannels.isEmpty {
                        self.channelsLoadedPromise.set(true)
                    } else if !self.recoverChannelListDisplayFromCache() {
                        self.lastChannelFetchAtByClanId.removeValue(forKey: clanId)
                        self.scheduleEmptyChannelRetryIfNeeded(clanId: clanId)
                    }
                }
                self.channelListNode.endRefreshing()
                self.isLoadingPipe.putNext(false)
                self.needsReloadPipe.putNext(())
                self.clearInflightChannelFetchIfMatches(clanId: clanId)
            }, completed: { [weak self] in
                guard let self, !didDeliverFetchResult else { return }
                self.clearInflightChannelFetchIfMatches(clanId: clanId)
                guard self.clanId == clanId else { return }
                self.channelListNode.endRefreshing()
                if self.allChannels.isEmpty, NetworkMonitor.shared.isConnected {
                    if !self.recoverChannelListDisplayFromCache() {
                        self.isLoading = true
                        self.needsReloadPipe.putNext(())
                        self.scheduleEmptyChannelRetryIfNeeded(clanId: clanId)
                    }
                } else {
                    self.cancelDeferredSkeletonReveal()
                    self.isLoading = false
                    self.isLoadingPipe.putNext(false)
                    self.needsReloadPipe.putNext(())
                }
            }))
    }

    private func clearInflightChannelFetchIfMatches(clanId: Int64) {
        if inflightChannelFetchClanId == clanId {
            inflightChannelFetchClanId = 0
        }
    }

    private func scheduleEmptyChannelRetryIfNeeded(clanId: Int64) {
        guard clanId != 0, clanId == self.clanId, self.allChannels.isEmpty,
              NetworkMonitor.shared.isConnected else { return }
        let attempt = emptyChannelRetryCountByClanId[clanId, default: 0]
        guard attempt < maxEmptyChannelFetchRetries else { return }
        emptyChannelRetryCountByClanId[clanId] = attempt + 1
        let delayNanos = UInt64(700_000_000) * UInt64(attempt + 1)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard let self else { return }
            guard self.clanId == clanId, self.allChannels.isEmpty,
                  self.isCurrentSessionAlive, NetworkMonitor.shared.isConnected else { return }
            self.lastChannelFetchAtByClanId.removeValue(forKey: clanId)
            self.fetchChannelsWithoutLoadingSignal(allowEmptyChannelAppsOverwrite: false)
        }
    }

    func toggleCollapse(categoryId: Int64) {
        guard let idx = categories.firstIndex(where: { $0.id == categoryId }) else { return }
        var updated = categories
        updated[idx].isCollapsed.toggle()
        setCategories(updated)
        persistCollapseState()
    }

    func select(channel: Mezon_Api_ChannelDescription) {
        setSelectedChannelId(channel.channelID)
        selectedChannel = channel
        selectedChannelPipe.putNext(channel)
        if isCurrentSessionAlive {
            self.context.account.postbox.setPreferenceData(key: PreferencesKeys.selectedChannelId(clanId: clanId), value: encodeChannelId(channel.channelID))
        }
        needsReloadPipe.putNext(())
    }

    private func handleChannelTap(_ channel: Mezon_Api_ChannelDescription) {
        if channel.type == MezonConstants.ChannelType.mezonVoice.rawValue {
            presentJoinVoiceSheet(for: channel)
            if lastMemberOnboardingState.isVisible {
                MemberOnboardingProgress.completeVisitMissionIfNeeded(
                    context: context,
                    clanId: clanId,
                    channelId: channel.channelID
                )
            }
            return
        }
        if channel.type == MezonConstants.ChannelType.streaming.rawValue {
            presentJoinStreamSheet(for: channel)
            if lastMemberOnboardingState.isVisible {
                MemberOnboardingProgress.completeVisitMissionIfNeeded(
                    context: context,
                    clanId: clanId,
                    channelId: channel.channelID
                )
            }
            return
        }
        select(channel: channel)
        if lastMemberOnboardingState.isVisible {
            MemberOnboardingProgress.completeVisitMissionIfNeeded(
                context: context,
                clanId: clanId,
                channelId: channel.channelID
            )
        }
    }

    private func presentationWindowHostForChannelApp() -> WindowHost? {
        if let w = window { return w }
        if let nav = navigationController as? NavigationController, let cw = nav.currentWindow {
            return cw
        }
        return view.windowHost
    }

    private func navigationControllerForChannelAppGlobalOverlay() -> NavigationController? {
        if let nav = navigationController as? NavigationController { return nav }
        if let root = view.window?.rootViewController {
            return root.mezon_findDeepestNavigationController()
        }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        for w in scene.windows where !w.isHidden {
            if let nav = w.rootViewController?.mezon_findDeepestNavigationController() { return nav }
        }
        return nil
    }

    private func openChannelApp(_ app: Mezon_Api_ChannelAppResponse) {
        guard app.appID != 0, !app.appURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Toast.error("App unavailable")
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                Toast.error("Session unavailable")
                return
            }
            do {
                let webAppData = try await self.context.account.network.generateChannelAppHash(appId: app.appID, token: token)
                guard !webAppData.isEmpty else {
                    Toast.error("App unavailable")
                    return
                }
                guard let url = app.channelAppWebPageURL(webAppData: webAppData) else {
                    Toast.error("App unavailable")
                    return
                }
                let title = app.appName.trimmingCharacters(in: .whitespacesAndNewlines)
                let vc = ChannelAppWebViewController(
                    pageURL: url,
                    appTitle: title.isEmpty ? "App" : title)
                let navForOverlay = self.navigationControllerForChannelAppGlobalOverlay()
                if let nav = navForOverlay {
                    nav.presentOverlay(controller: vc, inGlobal: true)
                } else if let host = self.presentationWindowHostForChannelApp() {
                    host.presentInGlobalOverlay(vc)
                } else {
                    Toast.error("App unavailable")
                    return
                }
                DispatchQueue.main.async {
                    navForOverlay?.requestLayout(transition: .immediate)
                }
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func resolveVoiceMember(_ uid: String) -> VoiceMemberDisplay? {
        guard let uidInt = Int64(uid) else { return nil }

        let profile = context.account.postbox.read { $0.getProfile(userId: uid) }

        let member = context.account.postbox.read {
            $0.getClanMembers(clanId: self.clanId)
        }.first(where: { $0.userId == uidInt })

        let name: String
        let username: String
        if let m = member, !(m.clanNick.isEmpty && m.displayName.isEmpty && m.username.isEmpty) {
            if !m.clanNick.isEmpty {
                name = m.clanNick
            } else if !m.displayName.isEmpty {
                name = m.displayName
            } else {
                name = m.username
            }
            username = m.username
        } else if let profile, !((profile.displayName ?? "").isEmpty && profile.username.isEmpty) {
            name = (profile.displayName?.isEmpty == false ? profile.displayName : nil) ?? profile.username
            username = profile.username
        } else {
            name = ""
            username = ""
        }

        let avatar: String?
        if let m = member {
            avatar = m.resolvedAvatarURL(fallbackProfileAvatar: profile?.avatarUrl)
                .flatMap { raw -> String? in
                    let absolute = ImgproxyURL.absoluteResourceURL(from: raw)
                    return absolute.isEmpty ? nil : absolute
                }
        } else {
            avatar = profile?.avatarUrl.flatMap { raw -> String? in
                guard !raw.isEmpty else { return nil }
                let absolute = ImgproxyURL.absoluteResourceURL(from: raw)
                return absolute.isEmpty ? nil : absolute
            }
        }

        return VoiceMemberDisplay(name: name, username: username, avatarURL: avatar)
    }

    private func topModalPresenter() -> UIViewController? {
        guard let root = view.window?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private func dismissEventBottomSheets(animated: Bool = true, completion: @escaping () -> Void) {
        guard let root = view.window?.rootViewController else {
            completion()
            return
        }
        var parent = root
        while let presented = parent.presentedViewController {
            if presented is EventViewerBottomSheetViewController {
                parent.dismiss(animated: animated, completion: completion)
                return
            }
            parent = presented
        }
        completion()
    }

    private func presentJoinVoiceSheet(
        for channel: Mezon_Api_ChannelDescription,
        from presenter: UIViewController? = nil,
        onChat: (() -> Void)? = nil,
        onJoinVoice: (() -> Void)? = nil
    ) {
        presentJoinMediaSheet(
            for: channel,
            kind: .voice,
            from: presenter,
            onChat: onChat,
            onJoin: onJoinVoice
        )
    }

    private func presentJoinStreamSheet(
        for channel: Mezon_Api_ChannelDescription,
        from presenter: UIViewController? = nil,
        onChat: (() -> Void)? = nil,
        onJoinStream: (() -> Void)? = nil
    ) {
        presentJoinMediaSheet(
            for: channel,
            kind: .streaming,
            from: presenter,
            onChat: onChat,
            onJoin: onJoinStream
        )
    }

    private func presentJoinMediaSheet(
        for channel: Mezon_Api_ChannelDescription,
        kind: JoinChannelSheetKind,
        from presenter: UIViewController? = nil,
        onChat: (() -> Void)? = nil,
        onJoin: (() -> Void)? = nil
    ) {
        let title = channel.channelLabel.isEmpty
            ? NSLocalizedString("voiceChannel.defaultName", tableName: nil, bundle: .main, value: "Voice", comment: "")
            : channel.channelLabel

        var voiceUserIds: [String] = []
        if kind == .streaming {
            if let list = context.engine.clanData.getStreamUsers(clanId: clanId) {
                for vu in list.voiceChannelUsers where vu.channelID == channel.channelID {
                    for uid in vu.userIds where !uid.isEmpty && Int64(uid) != nil && !voiceUserIds.contains(uid) {
                        voiceUserIds.append(uid)
                    }
                }
            }
        } else {
            let sources: [Mezon_Api_VoiceChannelUserList?] = [
                context.engine.clanData.getVoiceUsers(clanId: clanId),
                context.engine.clanData.getStreamUsers(clanId: clanId),
            ]
            for list in sources.compactMap({ $0 }) {
                for vu in list.voiceChannelUsers where vu.channelID == channel.channelID {
                    for uid in vu.userIds where !uid.isEmpty && Int64(uid) != nil && !voiceUserIds.contains(uid) {
                        voiceUserIds.append(uid)
                    }
                }
            }
        }
        let resolvedMembers = voiceUserIds.compactMap { resolveVoiceMember($0) }
        let chatAction = onChat ?? { [weak self] in self?.pushChatViewController(for: channel) }
        let joinAction = onJoin ?? { [weak self] in
            guard let self else { return }
            if kind == .streaming {
                self.pushStreamingRoom(for: channel)
            } else {
                self.pushVoiceChannelRoom(for: channel)
            }
        }

        let sheet = JoinVoiceChannelSheetViewController(
            channelTitle: title,
            chatUnreadCount: Int(channel.countMessUnread),
            members: resolvedMembers,
            kind: kind,
            onChat: chatAction,
            onJoinVoice: joinAction,
            onInvite: {}
        )
        sheet.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            sheet.sheetPresentationController?.prefersGrabberVisible = false
            if #available(iOS 16.0, *) {
                let bottomInset = (presenter ?? self).view.window?.safeAreaInsets.bottom ?? 34
                let targetHeight = JoinVoiceChannelSheetViewController.preferredSheetHeight(
                    safeAreaBottomInset: bottomInset, hasMembers: !resolvedMembers.isEmpty)
                let detentId = JoinVoiceChannelSheetViewController.contentSizedDetentIdentifier
                let contentDetent = UISheetPresentationController.Detent.custom(identifier: detentId) { context in
                    min(targetHeight, context.maximumDetentValue)
                }
                sheet.sheetPresentationController?.detents = [contentDetent]
                sheet.sheetPresentationController?.selectedDetentIdentifier = detentId
            } else {
                sheet.sheetPresentationController?.detents = [.medium(), .large()]
            }
        }
        let resolvedPresenter = presenter ?? topModalPresenter() ?? view.window?.rootViewController ?? self
        CATransaction.begin()
        CATransaction.setAnimationDuration(JoinVoiceChannelSheetViewController.sheetTransitionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        if resolvedPresenter is ViewController {
            resolvedPresenter.view.window?.rootViewController?.present(sheet, animated: true)
        } else {
            resolvedPresenter.present(sheet, animated: true)
        }
        CATransaction.commit()
    }

    private func pushChatViewController(for channel: Mezon_Api_ChannelDescription) {
        select(channel: channel)
        guard let nav = enclosingNavigationController else { return }

        if let existing = nav.viewControllers.last(where: {
            ($0 as? ChatViewController)?.channel.channelID == channel.channelID
        }) {
            nav.popToViewController(existing, animated: true)
            return
        }

        let chatVC = ChatViewController(
            clanId: clanId,
            channel: channel,
            context: context,
            parentName: parentChannelName(for: channel)
        )
        if let mezonNav = nav as? NavigationController {
            mezonNav.pushViewController(
                chatVC,
                animated: true,
                stackPushAnimationDuration: NavigationController.channelListToChatPushAnimationDuration
            )
        } else {
            nav.pushViewController(chatVC, animated: true)
        }
    }

    private func pushVoiceChannelRoom(for channel: Mezon_Api_ChannelDescription) {
        select(channel: channel)
        guard let nav = enclosingNavigationController else { return }

        if let existing = nav.viewControllers.last(where: {
            ($0 as? VoiceChannelRoomViewController)?.voiceChannelId == channel.channelID
        }) {
            if nav.topViewController !== existing {
                nav.popToViewController(existing, animated: false)
            }
            return
        }

        let pip = VoiceChannelPiPOverlay.shared
        if pip.isActive {
            if pip.channel?.channelID == channel.channelID {
                let vc = VoiceChannelRoomViewController(
                    context: context, channel: channel,
                    parentChannelName: parentChannelName(for: channel),
                    voiceChannelCrossClanExitAlignClanId: pip.crossClanVoiceExitAlignClanId,
                    existingPiPOverlay: pip)
                nav.pushViewController(vc, animated: true)
                return
            } else {
                pip.dismiss()
            }
        }

        let vc = VoiceChannelRoomViewController(
            context: context, channel: channel,
            parentChannelName: parentChannelName(for: channel))
        nav.pushViewController(vc, animated: true)
    }

    private func pushStreamingRoom(for channel: Mezon_Api_ChannelDescription) {
        let streamChannel = enrichedStreamChannel(channel)
        select(channel: streamChannel)
        guard let nav = enclosingNavigationController else { return }

        let clanId = streamChannel.clanID != 0 ? streamChannel.clanID : self.clanId
        let pip = StreamingPiPOverlay.shared
        if pip.isActive, pip.channel?.channelID == streamChannel.channelID {
            pip.restoreFullScreen(animated: true)
            return
        }

        if let existing = nav.viewControllers.last(where: {
            ($0 as? StreamingRoomViewController)?.streamChannelId == streamChannel.channelID
        }) {
            StreamingRoomViewController.prepareJoiningStream(
                targetChannelId: streamChannel.channelID,
                clanId: clanId,
                context: context,
                navigationController: nav
            )
            if nav.topViewController !== existing {
                nav.popToViewController(existing, animated: false)
            }
            return
        }

        StreamingRoomViewController.prepareJoiningStream(
            targetChannelId: streamChannel.channelID,
            clanId: clanId,
            context: context,
            navigationController: nav
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken(),
                  let userId = self.context.currentUser?.id,
                  let username = self.context.currentUser?.username else { return }

            await StreamingWebRTCSession.shared.join(
                clanId: streamChannel.clanID != 0 ? streamChannel.clanID : self.clanId,
                channelId: streamChannel.channelID,
                streamId: streamChannel.channelID,
                userId: userId,
                username: username,
                token: token
            )

            if let uid = Int64(userId) {
                self.context.engine.clanData.applyStreamJoined(
                    clanId: streamChannel.clanID != 0 ? streamChannel.clanID : self.clanId,
                    channelId: streamChannel.channelID,
                    userId: uid
                )
            }

            let vc = StreamingRoomViewController(
                context: self.context,
                channel: streamChannel,
                parentChannelName: self.parentChannelName(for: streamChannel)
            )
            nav.pushViewController(vc, animated: true)
        }
    }

    private func parentChannelName(for channel: Mezon_Api_ChannelDescription) -> String? {
        guard channel.parentID != 0 else { return nil }
        return allChannels.first(where: { $0.channelID == channel.parentID })?.channelLabel
    }

    private func enrichedStreamChannel(_ channel: Mezon_Api_ChannelDescription) -> Mezon_Api_ChannelDescription {
        var merged = channel
        if merged.channelAvatar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let cached = allChannels.first(where: { $0.channelID == channel.channelID }),
           !cached.channelAvatar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.channelAvatar = cached.channelAvatar
        }
        if merged.channelAvatar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let resolvedClanId = channel.clanID != 0 ? channel.clanID : clanId
            if let resolved = context.account.postbox.resolvedChannelDescription(
                clanId: resolvedClanId,
                channelId: channel.channelID
            ), !resolved.channelAvatar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                merged.channelAvatar = resolved.channelAvatar
            }
        }
        return merged
    }

    func selectWithoutNavigation(channelId: Int64) {
        setSelectedChannelId(channelId)
        if let ch = allChannels.first(where: { $0.channelID == channelId }) {
            selectedChannel = ch
        }
        if isCurrentSessionAlive {
            context.account.postbox.setPreferenceData(
                key: PreferencesKeys.selectedChannelId(clanId: clanId),
                value: encodeChannelId(channelId)
            )
        }

        needsReloadPipe.putNext(())
    }

    func updateChannels(_ channels: [Mezon_Api_ChannelDescription]) {
        let resolvedChannels: [Mezon_Api_ChannelDescription]
        if channels.isEmpty {
            if let recoveredChannels = recoveryChannelsForEmptyFetch(clanId: clanId) {
                resolvedChannels = recoveredChannels
                lastChannelFetchAtByClanId.removeValue(forKey: clanId)
            } else {
                if !channelListCategoryDescs.isEmpty {
                    scheduleChannelListNetworkFetch(allowEmptyChannelAppsOverwrite: false)
                    return
                }
                resolvedChannels = channels
            }
        } else {
            resolvedChannels = channels
        }
        applyNetworkChannelListResult(
            clanId: clanId,
            channels: resolvedChannels,
            categoryDescs: channelListCategoryDescs,
            favoriteIds: channelListFavoriteIds,
            allowEmptyApps: false,
            source: "updateChannels"
        )
    }

    func ingestNotificationChannelData(
        channels: [Mezon_Api_ChannelDescription],
        categoryDescs: [Mezon_Api_CategoryDesc],
        favoriteIds: Set<Int64>,
        selectChannelId: Int64?
    ) {
        guard clanId != 0 else { return }
        if !categoryDescs.isEmpty {
            channelListCategoryDescs = categoryDescs
        }
        if !favoriteIds.isEmpty {
            channelListFavoriteIds = favoriteIds
        }
        updateChannels(channels)
        if let selectChannelId {
            selectWithoutNavigation(channelId: selectChannelId)
        }
    }

    private(set) var allChannels: [Mezon_Api_ChannelDescription] = []

    var currentState: ChannelListState {
        var voiceMap: [Int64: [String]] = [:]
        let sources: [Mezon_Api_VoiceChannelUserList?] = [
            context.engine.clanData.getVoiceUsers(clanId: clanId),
            context.engine.clanData.getStreamUsers(clanId: clanId),
        ]
        for list in sources.compactMap({ $0 }) {
            for vu in list.voiceChannelUsers {
                let filtered = vu.userIds.filter { !$0.isEmpty && Int64($0) != nil }
                if !filtered.isEmpty {
                    var existing = voiceMap[vu.channelID] ?? []
                    for uid in filtered where !existing.contains(uid) {
                        existing.append(uid)
                    }
                    voiceMap[vu.channelID] = existing
                }
            }
        }
        return ChannelListState(
            categories: displayedCategories,
            allChannels: allChannels,
            selectedChannelId: selectedChannelId,
            isLoading: isLoading,
            errorMessage: errorMessage,
            voiceUsersByChannel: voiceMap
        )
    }

    private var displayedCategories: [ChannelCategory] {
        if allChannels.isEmpty { return [] }
        if isLoading && categoriesContainOrphanUnnamedBucket() { return [] }
        guard !showEmptyCategoriesEnabled else { return categories }
        return categories.filter { cat in
            if let fav = cat.favoriteFlatChannels { return !fav.isEmpty }
            return !cat.channels.isEmpty
        }
    }

    private func categoriesContainOrphanUnnamedBucket() -> Bool {
        categories.contains { cat in
            cat.id == 0
                && cat.name.isEmpty
                && (!cat.channels.isEmpty
                    || cat.orderedThreadChildren.values.contains { !$0.isEmpty })
        }
    }

    private func setShowEmptyCategories(_ value: Bool) {
        guard clanId != 0 else { return }
        guard value != showEmptyCategoriesEnabled else { return }
        showEmptyCategoriesEnabled = value
        context.account.postbox.setPreferenceDataSync(
            key: PreferencesKeys.showEmptyCategories(clanId: clanId),
            value: Data([UInt8(value ? 1 : 0)])
        )
        needsReloadPipe.putNext(())
    }

    private func refreshShowEmptyCategoriesPreferenceFromCache() {
        guard clanId != 0 else { return }
        let loaded = loadShowEmptyCategoriesPreference(clanId: clanId)
        guard loaded != showEmptyCategoriesEnabled else { return }
        showEmptyCategoriesEnabled = loaded
        needsReloadPipe.putNext(())
    }

    private func loadShowEmptyCategoriesPreference(clanId: Int64) -> Bool {
        guard clanId != 0,
              let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.showEmptyCategories(clanId: clanId)),
              let first = data.first else { return false }
        return first != 0
    }

    func stateSignal() -> Signal<ChannelListState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            final class StateHolder {
                var value: ChannelListState
                init(_ value: ChannelListState) { self.value = value }
            }
            let lastEmitted = StateHolder(self.currentState)
            subscriber.putNext(lastEmitted.value)
            return (self.needsReloadPipe.signal()
                |> deliverOnMainQueue
            ).start(next: { [weak self] _ in
                guard let self else { return }
                guard !self.channelListStateEmitCoalesceScheduled else { return }
                self.channelListStateEmitCoalesceScheduled = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.channelListStateEmitCoalesceScheduled = false
                    let newState = self.currentState
                    guard newState != lastEmitted.value else { return }
                    lastEmitted.value = newState
                    subscriber.putNext(newState)
                }
            })
        }
    }

    private struct ChannelListFetchPayload {
        let channels: [Mezon_Api_ChannelDescription]
        let categoryDescs: [Mezon_Api_CategoryDesc]
        let favoriteChannelIds: Set<Int64>
    }

    private func channelListSignal(clanId: Int64) -> Signal<ChannelListFetchPayload, ChannelFetchError> {
        let context = self.context
        return Signal { subscriber in
            let task = Task {
                let startEpoch = await MainActor.run { context.sessionEpoch }
                let token = await Task { @MainActor in
                    await context.getTokenPreferringCachedSkipSessionReadyWait()
                }.value
                guard let token else {
                    await MainActor.run {
                        guard context.isStillCurrentSession(epoch: startEpoch) else {
                            subscriber.putCompletion()
                            return
                        }
                        subscriber.putError(.noSession)
                    }
                    return
                }
                let network = MezonHTTPClient.shared
                do {
                    async let channelsTask = network.listChannelDescs(clanId: clanId, token: token)
                    async let categoriesTask = Self.listCategoryDescsOrEmpty(network: network, clanId: clanId, token: token)
                    async let favoritesTask = Self.listFavoriteChannelIdsOrEmpty(network: network, clanId: clanId, token: token)
                    let channels = try await channelsTask
                    let categoryDescs = await categoriesTask
                    let favoriteIds = Set(await favoritesTask)
                    let payload = ChannelListFetchPayload(
                        channels: channels,
                        categoryDescs: categoryDescs,
                        favoriteChannelIds: favoriteIds
                    )
                    await MainActor.run {
                        guard context.isStillCurrentSession(epoch: startEpoch) else {
                            subscriber.putCompletion()
                            return
                        }
                        subscriber.putNext(payload)
                        subscriber.putCompletion()
                    }
                } catch {
                    await MainActor.run {
                        guard context.isStillCurrentSession(epoch: startEpoch) else {
                            subscriber.putCompletion()
                            return
                        }
                        subscriber.putError(.network(error))
                    }
                }
            }
            return ActionDisposable { task.cancel() }
        }
    }

    nonisolated private static func listCategoryDescsOrEmpty(network: MezonHTTPClient, clanId: Int64, token: String) async -> [Mezon_Api_CategoryDesc] {
        do {
            return try await network.listCategoryDescs(clanId: clanId, token: token)
        } catch {
            return []
        }
    }

    nonisolated private static func listFavoriteChannelIdsOrEmpty(network: MezonHTTPClient, clanId: Int64, token: String) async -> [Int64] {
        do {
            return try await network.listFavoriteChannelIds(clanId: clanId, token: token)
        } catch {
            return []
        }
    }

    private func restoreSelectionFromPostboxForCurrentClanOnly() {
        guard clanId != 0 else {
            setSelectedChannelId(nil)
            setSelectedChannel(nil)
            return
        }
        setSelectedChannel(nil)
        if let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.selectedChannelId(clanId: clanId)), data.count >= 8 {
            let id = data.withUnsafeBytes { $0.loadUnaligned(as: Int64.self).littleEndian }
            setSelectedChannelId(id)
        } else {
            setSelectedChannelId(nil)
        }
    }

    private func reconcileSelectionWithLoadedChannels() {
        guard !allChannels.isEmpty else { return }
        guard let sid = selectedChannelId, sid != 0 else { return }
        if !allChannels.contains(where: { $0.channelID == sid }) {
            setSelectedChannelId(nil)
            setSelectedChannel(nil)
        }
    }

    private func syncSelectedChannelFromStoredPreferences() {
        restoreSelectionFromPostboxForCurrentClanOnly()
        reconcileSelectionWithLoadedChannels()
    }

    private func encodeChannelId(_ id: Int64) -> Data {
        var le = id.littleEndian
        return withUnsafeBytes(of: &le) { Data($0) }
    }

    private func channelAppsForClan(
        _ apps: [Mezon_Api_ChannelAppResponse],
        clanId: Int64,
        fromCache: Bool = false
    ) -> [Mezon_Api_ChannelAppResponse] {
        guard clanId != 0 else { return [] }
        let channelIds = Set(
            allChannels
                .filter { $0.clanID == 0 || $0.clanID == clanId }
                .map(\.channelID)
        )
        return apps.filter { app in
            guard app.hasListableChannelAppContent else { return false }
            if app.clanID != 0 && app.clanID != clanId { return false }
            guard app.clanID == 0, app.channelID != 0 else { return true }
            if fromCache { return true }
            guard !channelIds.isEmpty else { return false }
            return channelIds.contains(app.channelID)
        }
    }

    private func applyResolvedChannelApps(_ apps: [Mezon_Api_ChannelAppResponse], clanId: Int64, cacheKey: String) {
        let sanitized = apps.filter { $0.hasListableChannelAppContent }
        channelListNode.updateChannelApps(sanitized)
        let encoded = encodeChannelApps(sanitized)
        let cachedData = context.account.postbox.getPreferenceData(key: cacheKey)
        if cachedData != encoded {
            context.account.postbox.setPreferenceDataSync(key: cacheKey, value: encoded)
        }
    }

    private var inflightChannelAppsFetchClanId: Int64 = 0
    private var lastChannelAppsFetchAtByClanId: [Int64: Date] = [:]
    private let channelAppsCacheTTL: TimeInterval = 300

    private func fetchChannelAppsInBackground() {
        fetchChannelApps(allowEmptyOverwrite: false)
    }

    private func fetchChannelApps(allowEmptyOverwrite _: Bool = false) {
        guard clanId != 0 else { return }
        let clanId = self.clanId
        if inflightChannelAppsFetchClanId == clanId { return }
        if let last = lastChannelAppsFetchAtByClanId[clanId],
           Date().timeIntervalSince(last) < channelAppsCacheTTL,
           context.account.postbox.getPreferenceData(key: PreferencesKeys.channelApps(clanId: clanId))?.isEmpty == false {
            return
        }
        inflightChannelAppsFetchClanId = clanId
        lastChannelAppsFetchAtByClanId[clanId] = Date()
        Task { @MainActor [weak self] in
            defer {
                if let self {
                    if self.clanId == clanId {
                        self.channelListNode.setChannelAppsLoadingIndicator(false)
                    }
                    if self.inflightChannelAppsFetchClanId == clanId {
                        self.inflightChannelAppsFetchClanId = 0
                    }
                }
            }
            guard let self else { return }
            let startEpoch = self.context.sessionEpoch
            guard let token = await self.resolveAuthTokenPreferringUnexpiredSessionStore() else { return }
            guard self.context.isStillCurrentSession(epoch: startEpoch) else { return }
            guard self.clanId == clanId else { return }

            let key = PreferencesKeys.channelApps(clanId: clanId)
            let cachedData = self.context.account.postbox.getPreferenceData(key: key)

            do {
                let apps = try await Task.detached(priority: .utility) {
                    try await MezonHTTPClient.shared.listChannelApps(clanId: clanId, token: token)
                }.value
                guard self.context.isStillCurrentSession(epoch: startEpoch) else { return }
                guard self.clanId == clanId else { return }
                let filtered = self.channelAppsForClan(apps, clanId: clanId)
                if filtered.isEmpty {
                    if !apps.isEmpty {
                        let permissive = self.channelAppsForClan(apps, clanId: clanId, fromCache: true)
                        if !permissive.isEmpty {
                            self.applyResolvedChannelApps(permissive, clanId: clanId, cacheKey: key)
                            return
                        }
                    }
                    if let cachedData, !cachedData.isEmpty {
                        let validCached = self.channelAppsForClan(self.decodeChannelApps(cachedData), clanId: clanId, fromCache: true)
                        if !validCached.isEmpty {
                            self.channelListNode.updateChannelApps(validCached)
                            return
                        }
                    }
                    self.applyResolvedChannelApps([], clanId: clanId, cacheKey: key)
                    return
                }
                self.applyResolvedChannelApps(filtered, clanId: clanId, cacheKey: key)
            } catch {
            }
        }
    }

    private func restoreCachedChannelApps(clanId: Int64) {
        guard clanId != 0 else {
            channelListNode.updateChannelApps([])
            return
        }
        let key = PreferencesKeys.channelApps(clanId: clanId)
        guard let data = context.account.postbox.getPreferenceData(key: key), !data.isEmpty else {
            channelListNode.updateChannelApps([])
            return
        }
        let decoded = decodeChannelApps(data)
        let apps = channelAppsForClan(decoded, clanId: clanId, fromCache: true)
        applyResolvedChannelApps(apps, clanId: clanId, cacheKey: key)
    }

    private func refreshChannelAppsLabelsFromChannelList() {
        guard clanId != 0 else { return }
        let key = PreferencesKeys.channelApps(clanId: clanId)
        guard let data = context.account.postbox.getPreferenceData(key: key), !data.isEmpty else {
            return
        }
        let apps = channelAppsForClan(decodeChannelApps(data), clanId: clanId, fromCache: true)
        applyResolvedChannelApps(apps, clanId: clanId, cacheKey: key)
    }

    private func encodeChannelApps(_ apps: [Mezon_Api_ChannelAppResponse]) -> Data {
        var r = Mezon_Api_ListChannelAppsResponse()
        r.channelApps = apps
        return (try? r.serializedData()) ?? Data()
    }

    private func decodeChannelApps(_ data: Data) -> [Mezon_Api_ChannelAppResponse] {
        if data.isEmpty { return [] }
        do {
            return try Mezon_Api_ListChannelAppsResponse(serializedBytes: data).channelApps
        } catch {
            return decodeChannelAppsLegacy(data)
        }
    }

    private func decodeChannelAppsLegacy(_ data: Data) -> [Mezon_Api_ChannelAppResponse] {
        guard data.count >= 4 else { return [] }
        let count = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        var result: [Mezon_Api_ChannelAppResponse] = []
        var offset = 4
        for _ in 0..<count {
            guard offset + 4 <= data.count else { break }
            let len = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            offset += 4
            guard offset + Int(len) <= data.count else { break }
            if let m = try? Mezon_Api_ChannelAppResponse(serializedBytes: data.subdata(in: offset..<(offset + Int(len)))) {
                result.append(m)
            }
            offset += Int(len)
        }
        return result
    }

    private func persistFavoriteChannelIds(_ ids: Set<Int64>, clanId: Int64) {
        guard isCurrentSessionAlive else { return }
        var resp = Mezon_Api_ListFavoriteChannelResponse()
        resp.channelIds = Array(ids)
        if let data = try? resp.serializedData() {
            context.account.postbox.setPreferenceDataSync(key: PreferencesKeys.favoriteChannelIds(clanId: clanId), value: data)
        }
    }

    private func resolvedFavoriteChannelIds(clanId: Int64, meta: ChannelListCachedMeta?) -> Set<Int64> {
        if let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.favoriteChannelIds(clanId: clanId)),
           let r = try? Mezon_Api_ListFavoriteChannelResponse(serializedBytes: data) {
            return Set(r.channelIds)
        }
        return meta?.favoriteIds ?? []
    }

    private func cachedChannelsMatchClan(_ channels: [Mezon_Api_ChannelDescription], clanId: Int64) -> Bool {
        for ch in channels where ch.clanID != 0 && ch.clanID != clanId {
            return false
        }
        return true
    }

    private func recoveryChannelsForEmptyFetch(clanId: Int64) -> [Mezon_Api_ChannelDescription]? {
        guard clanId != 0 else { return nil }
        if clanId == self.clanId, !allChannels.isEmpty {
            return allChannels
        }
        return nil
    }

    @discardableResult
    private func recoverChannelListDisplayFromCache() -> Bool {
        guard clanId != 0, allChannels.isEmpty else { return false }
        guard let payload = readChannelCachePayloadIfAvailable(clanId: clanId), !payload.channels.isEmpty else { return false }
        applyResolvedChannelCachePayload(clanId: clanId, channels: payload.channels, meta: payload.meta, layoutOrdered: payload.layoutOrdered)
        cancelDeferredSkeletonReveal()
        isLoading = false
        isLoadingPipe.putNext(false)
        needsReloadPipe.putNext(())
        return true
    }

    private func readChannelCachePayloadIfAvailable(clanId: Int64) -> (channels: [Mezon_Api_ChannelDescription], meta: ChannelListCachedMeta?, layoutOrdered: Bool)? {
        if let displayBlob = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelListDisplay(clanId: clanId)),
           let display = decodeChannelListDisplay(displayBlob),
           cachedChannelsMatchClan(display.channels, clanId: clanId) {
            let favIds = resolvedFavoriteChannelIds(clanId: clanId, meta: display.meta)
            return (display.channels, ChannelListCachedMeta(categoryDescs: display.meta.categoryDescs, favoriteIds: favIds), true)
        }
        if let strict = readValidatedChannelCache(clanId: clanId) {
            return (strict.channels, strict.meta, false)
        }
        if let lenient = readChannelCacheLenient(clanId: clanId) {
            return (lenient.channels, lenient.meta, false)
        }
        return nil
    }

    private func encodeChannelListDisplay(
        channels: [Mezon_Api_ChannelDescription],
        categoryDescs: [Mezon_Api_CategoryDesc],
        favoriteIds: Set<Int64>
    ) -> Data {
        let channelsBlob = encodeChannelList(channels)
        var d = Data()
        var len = UInt32(channelsBlob.count).littleEndian
        d.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
        d.append(channelsBlob)
        d.append(ChannelListMetaCodec.encode(categoryDescs: categoryDescs, favoriteIds: favoriteIds))
        return d
    }

    private func decodeChannelListDisplay(_ data: Data) -> (channels: [Mezon_Api_ChannelDescription], meta: ChannelListCachedMeta)? {
        guard data.count >= 4 else { return nil }
        let len = Int(data.subdata(in: 0..<4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
        guard len > 0, 4 + len <= data.count else { return nil }
        let channels = decodeChannelList(data.subdata(in: 4..<(4 + len)))
        guard !channels.isEmpty else { return nil }
        let meta = ChannelListMetaCodec.decode(data.subdata(in: (4 + len)..<data.count))
            ?? ChannelListCachedMeta(categoryDescs: [], favoriteIds: [])
        return (channels, meta)
    }

    private func resolveChannelCachePayloadForDisplay(clanId: Int64) -> (channels: [Mezon_Api_ChannelDescription], meta: ChannelListCachedMeta?, layoutOrdered: Bool)? {
        guard clanId != 0 else { return nil }
        return readChannelCachePayloadIfAvailable(clanId: clanId)
    }

    private static func isDirectMessageChannel(_ channel: Mezon_Api_ChannelDescription) -> Bool {
        channel.type == MezonConstants.ChannelType.dm.rawValue
            || channel.type == MezonConstants.ChannelType.group.rawValue
    }

    private func applyResolvedChannelCachePayload(
        clanId: Int64,
        channels: [Mezon_Api_ChannelDescription],
        meta: ChannelListCachedMeta?,
        layoutOrdered: Bool = false
    ) {
        let orderedChannels = layoutOrdered ? channels : reorderChannelsLikePersistedList(channels, clanId: clanId)
        let cachedChannels = preservePendingMentionUnread(
            in: orderedChannels,
            clanId: clanId
        )
        allChannels = cachedChannels
        needsAuthoritativeNetworkReconcile = true
        let resolvedMeta = meta ?? readChannelListMetaFromCache(clanId: clanId)
        channelListCategoryDescs = resolvedMeta.categoryDescs
        channelListFavoriteIds = resolvedMeta.favoriteIds
        applyCategoriesFromCache(
            clanId: clanId,
            cachedChannels: cachedChannels,
            categoryDescs: channelListCategoryDescs,
            favoriteIds: channelListFavoriteIds
        )
        channelsLoadedPromise.set(true)
        categoriesPipe.putNext(categories)
        syncSelectedChannelFromStoredPreferences()
        refreshChannelAppsLabelsFromChannelList()
        needsReloadPipe.putNext(())
    }

    private func applyCategoriesForCurrentChannels(
        channels: [Mezon_Api_ChannelDescription],
        clanId: Int64
    ) {
        guard clanId != 0 else { return }
        let cachedMeta = readChannelListMetaFromCache(clanId: clanId)
        if channelListCategoryDescs.isEmpty, !cachedMeta.categoryDescs.isEmpty {
            channelListCategoryDescs = cachedMeta.categoryDescs
        }
        if channelListFavoriteIds.isEmpty, !cachedMeta.favoriteIds.isEmpty {
            channelListFavoriteIds = cachedMeta.favoriteIds
        }
        applyCategoriesFromCache(
            clanId: clanId,
            cachedChannels: channels,
            categoryDescs: channelListCategoryDescs,
            favoriteIds: channelListFavoriteIds
        )
    }

    private func reorderChannelsLikePersistedList(
        _ channels: [Mezon_Api_ChannelDescription],
        clanId: Int64
    ) -> [Mezon_Api_ChannelDescription] {
        guard let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)) else {
            return channels
        }
        let order = decodeChannelList(data).map(\.channelID)
        guard !order.isEmpty else { return channels }
        let byId = Dictionary(channels.map { ($0.channelID, $0) }, uniquingKeysWith: { _, new in new })
        var result: [Mezon_Api_ChannelDescription] = []
        var used = Set<Int64>()
        for id in order {
            if let ch = byId[id] {
                result.append(ch)
                used.insert(id)
            }
        }
        for ch in channels where !used.contains(ch.channelID) {
            result.append(ch)
        }
        return result
    }

    private func readChannelListMetaFromCache(clanId: Int64) -> ChannelListCachedMeta {
        let metaFromBlob: ChannelListCachedMeta?
        if let metaData = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelListMeta(clanId: clanId)),
           let m = ChannelListMetaCodec.decode(metaData) {
            metaFromBlob = m
        } else {
            metaFromBlob = nil
        }
        let favIds = resolvedFavoriteChannelIds(clanId: clanId, meta: metaFromBlob)
        return ChannelListCachedMeta(
            categoryDescs: metaFromBlob?.categoryDescs ?? [],
            favoriteIds: favIds
        )
    }

    private func readCategoriesSnapshotFromCache(clanId: Int64) -> [ChannelCategory]? {
        guard let blob = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelListCategories(clanId: clanId)) else {
            return nil
        }
        return decodeCategoriesSnapshot(blob)
    }

    private func applyCategoriesFromCache(
        clanId: Int64,
        cachedChannels: [Mezon_Api_ChannelDescription],
        categoryDescs: [Mezon_Api_CategoryDesc],
        favoriteIds: Set<Int64>
    ) {
        let collapsed = loadCollapsedCategoryIds()
        let snapshot = readCategoriesSnapshotFromCache(clanId: clanId)
        var layoutChannels = cachedChannels
        if let snap = snapshot {
            layoutChannels = repairChannelsFromSnapshotPlacement(
                layoutChannels, snapshot: snap, categoryDescs: categoryDescs
            )
        }
        if !categoryDescs.isEmpty {
            layoutChannels = repairChannelsMissingCategoryIds(layoutChannels, categoryDescs: categoryDescs)
        }
        if layoutChannels != cachedChannels {
            allChannels = layoutChannels
        }

        let nameReference = buildChannelCategories(
            layoutChannels,
            categoryDescs: categoryDescs,
            favoriteChannelIds: favoriteIds,
            collapsedIds: collapsed
        )
        var built = applyBuiltCategoriesPreservingCollapse(nameReference)
        var finalBuilt = injectFavoritesCategoryIfNeeded(
            enrichCategoryNames(built, channels: layoutChannels, categoryDescs: categoryDescs),
            channels: layoutChannels,
            favoriteChannelIds: favoriteIds,
            collapsedIds: collapsed
        )
        if hasOrphanZeroCategoryBucket(finalBuilt, categoryDescs: categoryDescs) {
            finalBuilt = injectFavoritesCategoryIfNeeded(
                enrichCategoryNames(
                    applyBuiltCategoriesPreservingCollapse(nameReference),
                    channels: layoutChannels,
                    categoryDescs: categoryDescs
                ),
                channels: layoutChannels,
                favoriteChannelIds: favoriteIds,
                collapsedIds: collapsed
            )
            scheduleChannelListRefetchIfOrphanCategory()
        }
        categories = filterCategoriesToKnownChannels(finalBuilt, channels: layoutChannels)
        scheduleCategoryDescsRefreshIfNeeded()
    }

    private func needsOrphanCategoryRepair() -> Bool {
        hasOrphanZeroCategoryBucket(categories, categoryDescs: channelListCategoryDescs)
    }

    private var orphanCategoryRefetchScheduled = false

    private func scheduleChannelListRefetchIfOrphanCategory() {
        guard clanId != 0, NetworkMonitor.shared.isConnected else { return }
        guard needsOrphanCategoryRepair() else { return }
        guard !orphanCategoryRefetchScheduled else { return }
        orphanCategoryRefetchScheduled = true
        let clanId = self.clanId
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.orphanCategoryRefetchScheduled = false
            guard let self, self.clanId == clanId else { return }
            guard self.needsOrphanCategoryRepair() else { return }
            self.scheduleChannelListNetworkFetch(allowEmptyChannelAppsOverwrite: false)
        }
    }

    private func needsCategoryMetaRefresh() -> Bool {
        guard clanId != 0 else { return false }
        if channelListCategoryDescs.isEmpty {
            let meta = readChannelListMetaFromCache(clanId: clanId)
            if meta.categoryDescs.isEmpty {
                return !allChannels.isEmpty
            }
        }
        return categories.contains {
            $0.id != ChannelCategory.favoritesCategoryId && $0.name.isEmpty
        }
    }

    private func supplementSnapshotCategoriesWithMissingChannels(
        _ snap: [ChannelCategory],
        authoritative: [Mezon_Api_ChannelDescription],
        categoryDescs: [Mezon_Api_CategoryDesc],
        favoriteIds: Set<Int64>
    ) -> [ChannelCategory] {
        var presentIds = Set<Int64>()
        for cat in snap {
            if let fav = cat.favoriteFlatChannels {
                for ch in fav { presentIds.insert(ch.channelID) }
            }
            for ch in cat.channels { presentIds.insert(ch.channelID) }
            for (_, arr) in cat.orderedThreadChildren {
                for ch in arr { presentIds.insert(ch.channelID) }
            }
        }
        let missing = authoritative.filter { !presentIds.contains($0.channelID) }
        guard !missing.isEmpty else { return snap }

        let extras = buildChannelCategories(
            missing,
            categoryDescs: categoryDescs,
            favoriteChannelIds: favoriteIds,
            collapsedIds: nil
        )
        var result = snap
        for extra in extras {
            if extra.id == ChannelCategory.favoritesCategoryId {
                if let idx = result.firstIndex(where: { $0.id == ChannelCategory.favoritesCategoryId }),
                   let extraFav = extra.favoriteFlatChannels, !extraFav.isEmpty {
                    var cat = result[idx]
                    var existingIds = Set((cat.favoriteFlatChannels ?? []).map(\.channelID))
                    var mergedFav = cat.favoriteFlatChannels ?? []
                    for ch in extraFav where !existingIds.contains(ch.channelID) {
                        mergedFav.append(ch)
                        existingIds.insert(ch.channelID)
                    }
                    cat.favoriteFlatChannels = mergedFav
                    result[idx] = cat
                } else if extra.favoriteFlatChannels != nil {
                    result.insert(extra, at: 0)
                }
                continue
            }
            if let idx = result.firstIndex(where: { $0.id == extra.id }) {
                var cat = result[idx]
                var existingParentIds = Set(cat.channels.map(\.channelID))
                for ch in extra.channels where !existingParentIds.contains(ch.channelID) {
                    cat.channels.append(ch)
                    existingParentIds.insert(ch.channelID)
                }
                for (parentId, threads) in extra.orderedThreadChildren {
                    var merged = cat.orderedThreadChildren[parentId] ?? []
                    var existingThreadIds = Set(merged.map(\.channelID))
                    for ch in threads where !existingThreadIds.contains(ch.channelID) {
                        merged.append(ch)
                        existingThreadIds.insert(ch.channelID)
                    }
                    cat.orderedThreadChildren[parentId] = merged
                }
                result[idx] = cat
            } else if let insertAt = result.firstIndex(where: { $0.id != ChannelCategory.favoritesCategoryId && $0.id > extra.id }) {
                result.insert(extra, at: insertAt)
            } else {
                result.append(extra)
            }
        }
        return result
    }

    private func readValidatedChannelCache(clanId: Int64) -> (channels: [Mezon_Api_ChannelDescription], meta: ChannelListCachedMeta?)? {
        guard let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)) else { return nil }
        let channels = decodeChannelList(data)
        guard !channels.isEmpty, cachedChannelsMatchClan(channels, clanId: clanId) else { return nil }
        return channelListMetaAndChannels(channels: channels, clanId: clanId)
    }

    private func readChannelCacheLenient(clanId: Int64) -> (channels: [Mezon_Api_ChannelDescription], meta: ChannelListCachedMeta?)? {
        guard let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)) else { return nil }
        let raw = decodeChannelList(data)
        guard !raw.isEmpty else { return nil }
        let channels = raw.filter { $0.clanID == 0 || $0.clanID == clanId }
        guard !channels.isEmpty else { return nil }
        return channelListMetaAndChannels(channels: channels, clanId: clanId)
    }

    private func channelListMetaAndChannels(
        channels: [Mezon_Api_ChannelDescription],
        clanId: Int64
    ) -> (channels: [Mezon_Api_ChannelDescription], meta: ChannelListCachedMeta?) {
        (channels, readChannelListMetaFromCache(clanId: clanId))
    }

    private func resolveAuthTokenPreferringUnexpiredSessionStore() async -> String? {
        await context.getTokenPreferringCachedSkipSessionReadyWait()
    }

    private func applyChannelCachePayload(channels: [Mezon_Api_ChannelDescription], meta: ChannelListCachedMeta?) {
        guard clanId != 0 else { return }
        applyResolvedChannelCachePayload(clanId: clanId, channels: channels, meta: meta)
        postClanSidebarUnreadDerivedFromCurrentChannels()
    }

    private func pruneAllChannelsByUserCache(clanId: Int64, keeping channelIds: Set<Int64>) {
        guard var list = context.engine.clanData.getAllChannelsByUser() else { return }
        let originalCount = list.channeldesc.count
        list.channeldesc.removeAll { ch in
            ch.clanID == clanId && !channelIds.contains(ch.channelID)
        }
        guard list.channeldesc.count != originalCount,
              let data = try? list.serializedData() else { return }
        context.account.postbox.setPreferenceDataSync(key: PreferencesKeys.allChannelsByUser, value: data)
    }

    private func channelsOrderedByCategoryLayout(
        _ channels: [Mezon_Api_ChannelDescription],
        categories: [ChannelCategory]
    ) -> [Mezon_Api_ChannelDescription] {
        var rank: [Int64: Int] = [:]
        var next = 0
        for cat in categories where cat.id != ChannelCategory.favoritesCategoryId {
            for ch in cat.channels where rank[ch.channelID] == nil {
                rank[ch.channelID] = next; next += 1
                for t in cat.orderedThreadChildren[ch.channelID] ?? [] where rank[t.channelID] == nil {
                    rank[t.channelID] = next; next += 1
                }
            }
        }
        guard !rank.isEmpty else { return channels }
        let appendedBase = next
        return channels.enumerated().sorted { lhs, rhs in
            let l = rank[lhs.element.channelID] ?? (appendedBase + lhs.offset)
            let r = rank[rhs.element.channelID] ?? (appendedBase + rhs.offset)
            return l < r
        }.map(\.element)
    }

    private func persistFullChannelListCache(
        clanId: Int64,
        channels: [Mezon_Api_ChannelDescription],
        categoryDescs: [Mezon_Api_CategoryDesc],
        favoriteIds: Set<Int64>,
        categories: [ChannelCategory]
    ) {
        guard isCurrentSessionAlive else { return }
        guard clanId != 0 else { return }
        let layoutOrdered = channelsOrderedByCategoryLayout(channels, categories: categories)
        let priorDisplayDescs = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelListDisplay(clanId: clanId))
            .flatMap { decodeChannelListDisplay($0)?.meta.categoryDescs } ?? []
        let displayDescs = categoryDescs.isEmpty ? priorDisplayDescs : categoryDescs
        context.account.postbox.setPreferenceDataSync(
            key: PreferencesKeys.channelListDisplay(clanId: clanId),
            value: encodeChannelListDisplay(channels: layoutOrdered, categoryDescs: displayDescs, favoriteIds: favoriteIds)
        )
        pruneAllChannelsByUserCache(clanId: clanId, keeping: Set(channels.map(\.channelID)))
        context.account.postbox.setPreferenceDataSync(
            key: PreferencesKeys.channelList(clanId: clanId),
            value: encodeChannelList(layoutOrdered)
        )
        persistFavoriteChannelIds(favoriteIds, clanId: clanId)

        guard !categoryDescs.isEmpty else { return }
        context.account.postbox.setPreferenceDataSync(
            key: PreferencesKeys.channelListMeta(clanId: clanId),
            value: ChannelListMetaCodec.encode(categoryDescs: categoryDescs, favoriteIds: favoriteIds)
        )
        context.account.postbox.setPreferenceDataSync(
            key: PreferencesKeys.channelListCategories(clanId: clanId),
            value: encodeCategoriesSnapshot(categories)
        )
    }

    private func encodeCategoriesSnapshot(_ cats: [ChannelCategory]) -> Data {
        var d = Data()
        var ver: UInt32 = 1
        d.append(contentsOf: withUnsafeBytes(of: &ver) { Array($0) })
        var n = UInt32(cats.count)
        d.append(contentsOf: withUnsafeBytes(of: &n) { Array($0) })
        for cat in cats {
            var idLe = cat.id.littleEndian
            d.append(contentsOf: withUnsafeBytes(of: &idLe) { Array($0) })
            d.append(cat.isCollapsed ? 1 : 0)
            let nameD = Data(cat.name.utf8)
            var nl = UInt32(nameD.count)
            d.append(contentsOf: withUnsafeBytes(of: &nl) { Array($0) })
            d.append(nameD)
            let fav = cat.favoriteFlatChannels
            var favCount = UInt32(fav?.count ?? 0)
            d.append(contentsOf: withUnsafeBytes(of: &favCount) { Array($0) })
            if let fav {
                for ch in fav {
                    guard let sd = try? ch.serializedData() else { continue }
                    var len = UInt32(sd.count)
                    d.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
                    d.append(sd)
                }
            }
            var pCount = UInt32(cat.channels.count)
            d.append(contentsOf: withUnsafeBytes(of: &pCount) { Array($0) })
            for ch in cat.channels {
                guard let sd = try? ch.serializedData() else { continue }
                var len = UInt32(sd.count)
                d.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
                d.append(sd)
            }
            let keys = cat.orderedThreadChildren.keys.sorted()
            var mapCount = UInt32(keys.count)
            d.append(contentsOf: withUnsafeBytes(of: &mapCount) { Array($0) })
            for pk in keys {
                guard let threads = cat.orderedThreadChildren[pk] else { continue }
                var pkLe = pk.littleEndian
                d.append(contentsOf: withUnsafeBytes(of: &pkLe) { Array($0) })
                var tc = UInt32(threads.count)
                d.append(contentsOf: withUnsafeBytes(of: &tc) { Array($0) })
                for t in threads {
                    guard let sd = try? t.serializedData() else { continue }
                    var len = UInt32(sd.count)
                    d.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
                    d.append(sd)
                }
            }
        }
        return d
    }

    private func decodeCategoriesSnapshot(_ data: Data) -> [ChannelCategory]? {
        guard data.count >= 8 else { return nil }
        var o = 0
        let ver = data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        o += 4
        guard ver == 1 else { return nil }
        let count = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        o += 4
        guard count >= 0, count < 512 else { return nil }
        var out: [ChannelCategory] = []
        for _ in 0..<count {
            guard o + 9 <= data.count else { return nil }
            let id = data.subdata(in: o..<(o + 8)).withUnsafeBytes { $0.loadUnaligned(as: Int64.self).littleEndian }
            o += 8
            let collapsed = data[o] != 0
            o += 1
            guard o + 4 <= data.count else { return nil }
            let nl = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            o += 4
            guard o + nl <= data.count else { return nil }
            let name = String(data: data.subdata(in: o..<(o + nl)), encoding: .utf8) ?? ""
            o += nl
            guard o + 4 <= data.count else { return nil }
            let favc = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            o += 4
            var favFlat: [Mezon_Api_ChannelDescription]? = nil
            if favc > 0 {
                var fa: [Mezon_Api_ChannelDescription] = []
                for _ in 0..<favc {
                    guard o + 4 <= data.count else { return nil }
                    let len = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
                    o += 4
                    guard o + len <= data.count, len > 0 else { return nil }
                    if let ch = try? Mezon_Api_ChannelDescription(serializedBytes: data.subdata(in: o..<(o + len))) {
                        fa.append(ch)
                    }
                    o += len
                }
                favFlat = fa
            }
            guard o + 4 <= data.count else { return nil }
            let pc = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            o += 4
            var parents: [Mezon_Api_ChannelDescription] = []
            for _ in 0..<pc {
                guard o + 4 <= data.count else { return nil }
                let len = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
                o += 4
                guard o + len <= data.count, len > 0 else { return nil }
                if let ch = try? Mezon_Api_ChannelDescription(serializedBytes: data.subdata(in: o..<(o + len))) {
                    parents.append(ch)
                }
                o += len
            }
            guard o + 4 <= data.count else { return nil }
            let mc = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            o += 4
            var threadsMap: [Int64: [Mezon_Api_ChannelDescription]] = [:]
            for _ in 0..<mc {
                guard o + 8 <= data.count else { return nil }
                let pk = data.subdata(in: o..<(o + 8)).withUnsafeBytes { $0.loadUnaligned(as: Int64.self).littleEndian }
                o += 8
                guard o + 4 <= data.count else { return nil }
                let tc = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
                o += 4
                var tarr: [Mezon_Api_ChannelDescription] = []
                for _ in 0..<tc {
                    guard o + 4 <= data.count else { return nil }
                    let len = Int(data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
                    o += 4
                    guard o + len <= data.count, len > 0 else { return nil }
                    if let ch = try? Mezon_Api_ChannelDescription(serializedBytes: data.subdata(in: o..<(o + len))) {
                        tarr.append(ch)
                    }
                    o += len
                }
                threadsMap[pk] = tarr
            }
            out.append(ChannelCategory(
                id: id,
                name: name,
                isCollapsed: collapsed,
                channels: parents,
                orderedThreadChildren: threadsMap,
                favoriteFlatChannels: favFlat
            ))
        }
        guard o == data.count else { return nil }
        return out
    }

    private func categoriesSnapshotReferencesOnlyKnownChannels(
        _ cats: [ChannelCategory],
        authoritative: [Mezon_Api_ChannelDescription]
    ) -> Bool {
        let allowed = Set(authoritative.map(\.channelID))
        for cat in cats {
            if let fav = cat.favoriteFlatChannels {
                for ch in fav where !allowed.contains(ch.channelID) { return false }
            }
            for ch in cat.channels where !allowed.contains(ch.channelID) { return false }
            for (_, arr) in cat.orderedThreadChildren {
                for ch in arr where !allowed.contains(ch.channelID) { return false }
            }
        }
        return !cats.isEmpty
    }

    private func categoriesSnapshotConsistentWithChannels(
        _ cats: [ChannelCategory],
        authoritative: [Mezon_Api_ChannelDescription]
    ) -> Bool {
        let allowed = Set(authoritative.map(\.channelID))
        var presentTopLevel = Set<Int64>()
        var presentThreadIds = Set<Int64>()
        for cat in cats {
            if let fav = cat.favoriteFlatChannels {
                for ch in fav where !allowed.contains(ch.channelID) { return false }
            }
            for ch in cat.channels {
                if !allowed.contains(ch.channelID) { return false }
                presentTopLevel.insert(ch.channelID)
            }
            for (_, arr) in cat.orderedThreadChildren {
                for ch in arr {
                    if !allowed.contains(ch.channelID) { return false }
                    presentThreadIds.insert(ch.channelID)
                }
            }
        }
        let requiredTopLevel = Set(authoritative.filter { $0.parentID == 0 }.map(\.channelID))
        guard requiredTopLevel.isSubset(of: presentTopLevel) else { return false }
        let requiredThreadIds = Set(authoritative.filter { $0.parentID != 0 }.map(\.channelID))
        return requiredThreadIds.isSubset(of: presentThreadIds)
    }

    private func mergeChannelProtosIntoCategoriesSnapshot(
        _ cats: [ChannelCategory],
        authoritative: [Mezon_Api_ChannelDescription]
    ) -> [ChannelCategory] {
        let byId = Dictionary(authoritative.map { ($0.channelID, $0) }, uniquingKeysWith: { _, new in new })
        let allowed = Set(byId.keys)
        func mergeOne(_ ch: Mezon_Api_ChannelDescription) -> Mezon_Api_ChannelDescription? {
            guard let auth = byId[ch.channelID] else { return nil }
            if auth.categoryID == 0, ch.categoryID != 0 {
                var merged = auth
                merged.categoryID = ch.categoryID
                if merged.categoryName.isEmpty, !ch.categoryName.isEmpty {
                    merged.categoryName = ch.categoryName
                }
                return merged
            }
            return auth
        }
        return cats.map { cat in
            let mergedFav = cat.favoriteFlatChannels?.compactMap(mergeOne)
            let mergedParents = cat.channels.compactMap(mergeOne)
            let parentIds = Set(mergedParents.map(\.channelID))
            var newThreads: [Int64: [Mezon_Api_ChannelDescription]] = [:]
            for (k, arr) in cat.orderedThreadChildren {
                guard parentIds.contains(k), allowed.contains(k) else { continue }
                let merged = arr.compactMap(mergeOne)
                if !merged.isEmpty {
                    newThreads[k] = merged
                }
            }
            var resolvedName = cat.name
            if resolvedName.isEmpty {
                for ch in mergedParents where !ch.categoryName.isEmpty {
                    resolvedName = ch.categoryName
                    break
                }
            }
            return ChannelCategory(
                id: cat.id,
                name: resolvedName,
                isCollapsed: cat.isCollapsed,
                channels: mergedParents,
                orderedThreadChildren: newThreads,
                favoriteFlatChannels: mergedFav?.isEmpty == true ? nil : mergedFav
            )
        }
    }

    private func encodeChannelList(_ channels: [Mezon_Api_ChannelDescription]) -> Data {
        var result = Data()
        var count = UInt32(channels.count)
        result.append(contentsOf: withUnsafeBytes(of: &count) { Array($0) })
        for ch in channels {
            if let d = try? ch.serializedData() {
                var len = UInt32(d.count)
                result.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
                result.append(d)
            }
        }
        return result
    }

    private func decodeChannelList(_ data: Data) -> [Mezon_Api_ChannelDescription] {
        guard data.count >= 4 else { return [] }
        let count = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        var result: [Mezon_Api_ChannelDescription] = []
        var offset = 4
        for _ in 0..<count {
            guard offset + 4 <= data.count else { break }
            let len = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            offset += 4
            guard offset + Int(len) <= data.count else { break }
            if let m = try? Mezon_Api_ChannelDescription(serializedBytes: data.subdata(in: offset..<(offset + Int(len)))) {
                result.append(m)
            }
            offset += Int(len)
        }
        return result
    }

    private func persistCollapseState() {
        guard isCurrentSessionAlive else { return }
        let collapsed = Set(categories.filter(\.isCollapsed).map(\.id))
        let encoded = encodeCollapsedIds(collapsed)
        context.account.postbox.setPreferenceData(key: PreferencesKeys.collapsedCategories(clanId: clanId), value: encoded)
    }

    private func loadCollapsedCategoryIds() -> Set<Int64>? {
        guard let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.collapsedCategories(clanId: clanId)) else { return nil }
        return decodeCollapsedIds(data)
    }

    private func encodeCollapsedIds(_ ids: Set<Int64>) -> Data {
        var result = Data()
        var count = UInt32(ids.count)
        result.append(contentsOf: withUnsafeBytes(of: &count) { Array($0) })
        for id in ids {
            var le = id.littleEndian
            result.append(contentsOf: withUnsafeBytes(of: &le) { Array($0) })
        }
        return result
    }

    private func decodeCollapsedIds(_ data: Data) -> Set<Int64> {
        guard data.count >= 4 else { return [] }
        let count = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        var result = Set<Int64>()
        var offset = 4
        for _ in 0..<count {
            guard offset + 8 <= data.count else { break }
            let id = data.subdata(in: offset..<(offset + 8)).withUnsafeBytes { $0.loadUnaligned(as: Int64.self).littleEndian }
            result.insert(id)
            offset += 8
        }
        return result
    }
}

private extension UIViewController {
    func mezon_findDeepestNavigationController() -> NavigationController? {
        if let nav = self as? NavigationController {
            if let tab = nav.topViewController as? TabBarController,
               let current = tab.currentController {
                return current.mezon_findDeepestNavigationController() ?? nav
            }
            return nav
        }
        if let tab = self as? TabBarController, let current = tab.currentController {
            return current.mezon_findDeepestNavigationController()
        }
        if let tab = self as? UITabBarController, let sel = tab.selectedViewController {
            return sel.mezon_findDeepestNavigationController()
        }
        if let presented = presentedViewController {
            if let nav = presented.mezon_findDeepestNavigationController() { return nav }
        }
        for child in children {
            if let nav = child.mezon_findDeepestNavigationController() { return nav }
        }
        return nil
    }
}
