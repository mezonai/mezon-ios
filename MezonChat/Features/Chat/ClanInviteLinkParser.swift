import Foundation

enum ClanInviteLinkParser {
    static func firstInviteCode(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let range = trimmed.range(of: "mezon://invite/", options: .caseInsensitive) {
            let after = trimmed[range.upperBound...]
            let id = prefixDigits(String(after))
            if !id.isEmpty { return id }
        }

        let ns = trimmed as NSString
        let regex = try? NSRegularExpression(
            pattern: #"https?://[^\s]+/invite/(?:chat/)?(\d+)"#,
            options: [.caseInsensitive]
        )
        let fullRange = NSRange(location: 0, length: ns.length)
        for match in regex?.matches(in: trimmed, range: fullRange) ?? [] where match.numberOfRanges >= 2 {
            let link = ns.substring(with: match.range(at: 0))
            let code = ns.substring(with: match.range(at: 1))
            if !code.isEmpty, isMezonInviteHost(link) { return code }
        }

        return nil
    }

    private static func isMezonInviteHost(_ link: String) -> Bool {
        guard let host = URL(string: link)?.host?.lowercased() else { return false }
        if host == "mezon.ai" || host.hasSuffix(".mezon.ai") { return true }
        guard let configured = URL(string: MezonConfig.chatWebAppBaseURL)?.host?.lowercased() else { return false }
        return host == configured
    }

    private static func prefixDigits(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch.isNumber { out.append(ch) } else if !out.isEmpty { break }
        }
        return out
    }
}

@MainActor
enum ClanChannelDescsGate {
    private static var fetchedClanIds = Set<Int64>()
    private static var inflight = [Int64: Task<Void, Never>]()

    static func ensureFetchedBeforeJoin(
        context: AccountContext,
        clanId: Int64,
        force: Bool = false,
        maxWaitNanoseconds: UInt64 = 5_000_000_000
    ) async {
        guard clanId != 0 else { return }
        if !force, fetchedClanIds.contains(clanId) { return }
        if inflight[clanId] == nil {
            inflight[clanId] = Task { @MainActor in
                defer { inflight[clanId] = nil }
                guard let token = await context.getToken(), !token.isEmpty else { return }
                do {
                    _ = try await context.engine.channels.listChannelDescs(clanId: clanId, token: token)
                    fetchedClanIds.insert(clanId)
                } catch {}
            }
        }
        let stepNanoseconds: UInt64 = 50_000_000
        var waited: UInt64 = 0
        while inflight[clanId] != nil, waited < maxWaitNanoseconds {
            try? await Task.sleep(nanoseconds: stepNanoseconds)
            waited += stepNanoseconds
        }
    }
}

enum ClanInviteJoiner {
    static func join(
        context: AccountContext,
        code: String,
        clanId: Int64? = nil,
        attempts: Int = 3,
        initialDelayNanoseconds: UInt64 = 500_000_000
    ) async -> Int64? {
        var targetClanId = clanId ?? 0
        if targetClanId == 0 {
            let token = await context.getToken() ?? ""
            if !token.isEmpty,
               let info = try? await context.engine.clanData.getInviteInfo(code: code, token: token),
               let cid = info.clan_id.flatMap(Int64.init) {
                targetClanId = cid
            }
        }
        let total = max(attempts, 1)
        var delay = initialDelayNanoseconds
        for attempt in 0..<total {
            if targetClanId != 0 {
                await ClanChannelDescsGate.ensureFetchedBeforeJoin(context: context, clanId: targetClanId, force: true)
            }
            let token = await context.getToken() ?? ""
            do {
                let response = try await context.engine.clanData.joinClanWithInvite(code: code, token: token)
                return response.clanID
            } catch {
                if attempt < total - 1 {
                    try? await Task.sleep(nanoseconds: delay)
                    delay *= 2
                }
            }
        }
        return nil
    }
}
