import Foundation

@MainActor
enum MmnSendTokenLogMessage {
    private static let giveCoffeeDisplayAmount = "10000"

    static func sendGiveCoffeeTransferLog(
        context: AccountContext,
        receiverUserId: Int64
    ) async throws {
        try await send(
            context: context,
            receiverUserId: receiverUserId,
            amountInput: giveCoffeeDisplayAmount,
            note: L(L10n.MessageAction.giveACoffee)
        )
    }

    static func sendAfterUserIdTransferIfNeeded(
        context: AccountContext,
        payload: TransferQRPayload,
        isByAddress: Bool,
        amountInput: String,
        note: String
    ) async {
        guard !isByAddress else { return }
        guard let rid = payload.receiverUserId, !rid.isEmpty, let receiverId = Int64(rid) else { return }
        do {
            try await send(context: context, receiverUserId: receiverId, amountInput: amountInput, note: note)
        } catch {
        }
    }

    private static func send(
        context: AccountContext,
        receiverUserId: Int64,
        amountInput: String,
        note: String
    ) async throws {
        guard let token = await context.getToken() else { return }
        let trimmedNote = note
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let amountPretty = MmnMoneyFormat.formatTokenAmount(amountInput).display
        let line = "\(L(L10n.Profile.sendTokenLogLinePrefix)) \(amountPretty)₫ | \(trimmedNote)"
        let contentObj: [String: Any] = ["t": line]
        let data = try JSONSerialization.data(withJSONObject: contentObj)
        guard let contentStr = String(data: data, encoding: .utf8) else { return }

        let channels = try await context.account.network.listDirectMessageChannels(token: token)
        let dm: Mezon_Api_ChannelDescription
        if let existing = channels.first(where: { ch in
            ch.type == MezonConstants.ChannelType.dm.rawValue && ch.userIds.contains(receiverUserId)
        }) {
            dm = existing
        } else {
            dm = try await context.account.network.createDirectMessage(userId: receiverUserId, token: token)
        }
        let isPublic = dm.channelPrivate == 0
        _ = try await context.account.network.sendChannelMessage(
            clanId: 0,
            channelId: dm.channelID,
            mode: MezonConstants.ChannelStreamMode.dm.rawValue,
            isPublic: isPublic,
            content: contentStr,
            code: MezonConstants.MessageCode.sendToken.rawValue,
            token: token
        )
    }
}
