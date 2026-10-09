import Foundation

struct BotFlashCommand: Equatable {
    let botId: Int64
    let menuName: String
    let actionMsg: String

    private var trimmedAction: String {
        actionMsg.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stillPrefixes(_ content: String) -> Bool {
        let action = trimmedAction
        guard !action.isEmpty else { return false }
        return content.drop(while: { $0.isWhitespace }).hasPrefix(action)
    }

    func arguments(in content: String) -> String {
        let leadingTrimmed = content.drop(while: { $0.isWhitespace })
        let action = trimmedAction
        let rest = !action.isEmpty && leadingTrimmed.hasPrefix(action)
            ? leadingTrimmed.dropFirst(action.count)
            : leadingTrimmed
        return String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum BotCommandStatus: Equatable {
    case waiting
    case answered(replyMessageId: String)
    case noResponse
    case failed
}

struct BotCommandDisplay: Equatable {
    let menuName: String
    let arguments: String
    let botName: String
    let status: BotCommandStatus
    let resendable: Bool
}

enum BotCommandUserAction {
    case viewReply(messageId: String)
    case resend
    case dismiss
}

struct BotCommandDispatch {
    let botId: Int64
    let botName: String
    let menuName: String
    let arguments: String
    let resendable: Bool
    let prepare: () async throws -> Mezon_Realtime_ChannelMessageSend
}

@MainActor
final class BotCommandTracker {

    struct Entry {
        let rowId: String
        let botId: Int64
        let botName: String
        let menuName: String
        let arguments: String
        let resendable: Bool
        let createdAt: Date
        var status: BotCommandStatus
        var commandMessageId: Int64
        var sentAt: Date
        var timedOut: Bool
        var message: Mezon_Realtime_ChannelMessageSend?

        var display: BotCommandDisplay {
            BotCommandDisplay(
                menuName: menuName,
                arguments: arguments,
                botName: botName,
                status: status,
                resendable: resendable && message != nil
            )
        }

        var awaitsReply: Bool {
            guard commandMessageId != 0 else { return false }
            switch status {
            case .waiting, .noResponse: return true
            case .answered, .failed: return false
            }
        }
    }

    private static let responseTimeoutNanoseconds: UInt64 = 30_000_000_000
    private static let unreferencedReplyClockSkew: TimeInterval = 2

    private let context: AccountContext
    private(set) var entries: [Entry] = []
    private var consumedReplyIds: Set<String> = []
    private var inFlightByBot: [Int64: Int] = [:]
    private var rowSequence = 0

    var onChange: (() -> Void)?

    init(context: AccountContext) {
        self.context = context
    }

    func dispatch(_ request: BotCommandDispatch) {
        beginFlight(request.botId)
        let context = self.context
        Task { @MainActor [weak self] in
            var prepared: Mezon_Realtime_ChannelMessageSend?
            var commandMessageId: Int64?
            do {
                let message = try await request.prepare()
                prepared = message
                commandMessageId = try await Self.send(message, context: context)
            } catch {
                commandMessageId = nil
            }
            guard let self else { return }
            self.endFlight(request.botId)
            let now = Date()
            let entry = Entry(
                rowId: self.nextRowId(),
                botId: request.botId,
                botName: request.botName,
                menuName: request.menuName,
                arguments: request.arguments,
                resendable: request.resendable,
                createdAt: now,
                status: commandMessageId == nil ? .failed : .waiting,
                commandMessageId: commandMessageId ?? 0,
                sentAt: now,
                timedOut: false,
                message: request.resendable ? prepared : nil
            )
            self.entries.append(entry)
            if let commandMessageId {
                self.scheduleTimeout(rowId: entry.rowId, commandMessageId: commandMessageId)
            }
            self.onChange?()
        }
    }

    func resend(rowId: String) {
        guard let index = entries.firstIndex(where: { $0.rowId == rowId }),
              let message = entries[index].message else { return }
        switch entries[index].status {
        case .noResponse, .failed: break
        case .waiting, .answered: return
        }
        entries[index].status = .waiting
        onChange?()

        let old = entries[index]
        beginFlight(old.botId)
        let context = self.context
        Task { @MainActor [weak self] in
            let commandMessageId = try? await Self.send(message, context: context)
            guard let self else { return }
            self.endFlight(old.botId)
            guard let currentIndex = self.entries.firstIndex(where: { $0.rowId == rowId }) else { return }
            guard let commandMessageId else {
                self.entries[currentIndex].status = .failed
                self.onChange?()
                return
            }
            let now = Date()
            let replacement = Entry(
                rowId: self.nextRowId(),
                botId: old.botId,
                botName: old.botName,
                menuName: old.menuName,
                arguments: old.arguments,
                resendable: old.resendable,
                createdAt: now,
                status: .waiting,
                commandMessageId: commandMessageId,
                sentAt: now,
                timedOut: false,
                message: message
            )
            self.entries.remove(at: currentIndex)
            self.entries.append(replacement)
            self.scheduleTimeout(rowId: replacement.rowId, commandMessageId: commandMessageId)
            self.onChange?()
        }
    }

    func dismiss(rowId: String) {
        guard let index = entries.firstIndex(where: { $0.rowId == rowId }) else { return }
        entries.remove(at: index)
        onChange?()
    }

    func resolveReplies(in messages: [ChatMessageDisplay]) {
        let pending = entries.indices.filter { entries[$0].awaitsReply }
        guard !pending.isEmpty else { return }
        let candidates = messages.filter { $0.botCommand == nil && !consumedReplyIds.contains($0.id) }
        guard !candidates.isEmpty else { return }

        var changed = false
        for index in pending {
            let commandId = entries[index].commandMessageId
            if let reply = candidates.first(where: {
                !consumedReplyIds.contains($0.id) && $0.replyRef?.messageRefID == commandId
            }) {
                answer(index, replyId: reply.id)
                changed = true
            }
        }

        let ordered = pending.sorted { !entries[$0].timedOut && entries[$1].timedOut }
        for index in ordered where entries[index].awaitsReply {
            let entry = entries[index]
            if entry.timedOut && (inFlightByBot[entry.botId] ?? 0) > 0 { continue }
            if let reply = candidates.first(where: { candidate in
                !consumedReplyIds.contains(candidate.id)
                    && candidate.replyRef == nil
                    && Int64(candidate.message.senderId) == entry.botId
                    && Self.isReply(candidate, after: entry)
            }) {
                answer(index, replyId: reply.id)
                changed = true
            }
        }

        if changed {
            onChange?()
        }
    }

    private func answer(_ index: Int, replyId: String) {
        entries[index].status = .answered(replyMessageId: replyId)
        consumedReplyIds.insert(replyId)
    }

    private static func isReply(_ candidate: ChatMessageDisplay, after entry: Entry) -> Bool {
        if let candidateId = Int64(candidate.id), candidateId > 0 {
            return candidateId > entry.commandMessageId
        }
        return candidate.message.createdAt >= entry.sentAt.addingTimeInterval(-unreferencedReplyClockSkew)
    }

    private func scheduleTimeout(rowId: String, commandMessageId: Int64) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.responseTimeoutNanoseconds)
            guard let self,
                  let index = self.entries.firstIndex(where: { $0.rowId == rowId }),
                  self.entries[index].commandMessageId == commandMessageId,
                  self.entries[index].status == .waiting else { return }
            self.entries[index].timedOut = true
            self.entries[index].status = .noResponse
            self.onChange?()
        }
    }

    private func beginFlight(_ botId: Int64) {
        inFlightByBot[botId, default: 0] += 1
    }

    private func endFlight(_ botId: Int64) {
        let remaining = (inFlightByBot[botId] ?? 0) - 1
        inFlightByBot[botId] = remaining > 0 ? remaining : nil
    }

    private func nextRowId() -> String {
        rowSequence += 1
        return "botcmd-\(rowSequence)"
    }

    private static func send(_ message: Mezon_Realtime_ChannelMessageSend, context: AccountContext) async throws -> Int64 {
        guard let token = await context.getToken() else {
            throw MezonError.invalidResponse
        }
        let ack = try await MezonHTTPClient.shared.sendEphemeralMessageToBot(message, token: token)
        return ack.messageID
    }
}
