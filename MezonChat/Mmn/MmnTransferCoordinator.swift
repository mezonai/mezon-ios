import Foundation

struct TransferQRPayload: Sendable {
    var receiverUserId: String?
    var walletAddress: String?
    var suggestedAmount: String?
    var note: String?
    var extraAttribute: String?
    var receiverDisplayName: String?
}

enum MmnTransferParse {
    static func fromQRString(_ s: String) -> TransferQRPayload? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("{"), let d = t.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        if o["receiver_id"] == nil, o["wallet_address"] == nil { return nil }
        let rid: String? = (o["receiver_id"] as? String)
            ?? (o["receiver_id"] as? Int).map { String($0) }
            ?? (o["receiver_id"] as? Int64).map { String($0) }
        let wa = o["wallet_address"] as? String
        let amount = o["amount"] as? String ?? (o["amount"] as? Int).map { String($0) }
        let note = o["note"] as? String
        let extra = o["extra_attribute"] as? String
        let rname = (o["receiver_name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let p = TransferQRPayload(
            receiverUserId: rid,
            walletAddress: wa,
            suggestedAmount: amount,
            note: note,
            extraAttribute: extra,
            receiverDisplayName: (rname?.isEmpty == false) ? rname : nil
        )
        return p
    }
}

enum MmnTransferError: Error, LocalizedError {
    case walletNotReady
    case giveCoffeeInProgress

    var errorDescription: String? {
        switch self {
        case .walletNotReady:
            return "Wallet credentials are not ready. Please sign in again to use MMN transfer."
        case .giveCoffeeInProgress:
            return "Give coffee is already in progress."
        }
    }
}

@MainActor
enum MmnTransferCoordinator {
    private static let giveCoffeeLock = NSLock()
    private static var isGiveCoffeeInFlight = false
    private static let giveCoffeeTextData = "givecoffee"
    private static let giveCoffeeAmountInput = "10000"

    private static func loadCachedWalletCredentials(userId: String) throws -> (zk: MmnPersistedZkProofs, ephemeral: MmnEphemeralKeyPair) {
        MmnWalletStore.shared.bind(userId: userId)
        guard let zk = MmnWalletStore.shared.zkProofs,
              let ephemeral = MmnWalletStore.shared.ephemeralKeyPair() else {
            throw MmnTransferError.walletNotReady
        }
        return (zk, ephemeral)
    }

    static func send(
        context: AccountContext,
        payload: TransferQRPayload,
        amountInput: String,
        note: String
    ) async throws -> MmnAddTxResult {
        guard let u = context.currentUser else {
            throw NSError(domain: "MmnTransfer", code: 1, userInfo: [NSLocalizedDescriptionKey: "No user"])
        }
        let senderUserId = u.id
        let (zk, ephemeral) = try loadCachedWalletCredentials(userId: senderUserId)
        let wallet = try await MmnClient.shared.getAccountByUserId(senderUserId)
        let isByAddress = payload.walletAddress != nil
        let recipientUserOrAddress: String = {
            if let w = payload.walletAddress, !w.isEmpty { return w }
            if let r = payload.receiverUserId, !r.isEmpty { return r }
            return ""
        }()
        guard !recipientUserOrAddress.isEmpty else {
            throw NSError(domain: "MmnTransfer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing recipient"])
        }
        guard let scaled = MmnAmountScale.scaleToChainAmount(amountInput) else {
            throw NSError(domain: "MmnTransfer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid amount"])
        }
        if !MmnAmountScale.hasEnoughBalance(walletBalance: wallet.balance, sendScaled: scaled) {
            throw NSError(domain: "MmnTransfer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Insufficient balance"])
        }
        let senderAddr: String
        let recipientAddr: String
        if isByAddress {
            senderAddr = wallet.address
            recipientAddr = recipientUserOrAddress
        } else {
            senderAddr = MmnClient.addressFromUserId(senderUserId)
            recipientAddr = MmnClient.addressFromUserId(recipientUserOrAddress)
        }
        let nonceRes = try await MmnClient.shared.getCurrentNonce(address: senderAddr, tag: "pending")
        if let err = nonceRes.error, !err.isEmpty {
            throw NSError(domain: "MmnTransfer", code: 5, userInfo: [NSLocalizedDescriptionKey: err])
        }
        let n = nonceRes.nonce ?? 0
        let extra: [String: String] = [
            "type": "transfer_token",
            "UserReceiverId": isByAddress ? recipientUserOrAddress : (payload.receiverUserId ?? recipientUserOrAddress),
            "UserSenderId": senderUserId,
            "UserSenderUsername": u.username,
            "ExtraAttribute": payload.extraAttribute ?? ""
        ]
        let extraData = try JSONSerialization.data(withJSONObject: extra)
        guard let extraStr = String(data: extraData, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        let tx = MmnTxMsgForSign(
            type: MmnTxType.transferByZK,
            sender: senderAddr,
            recipient: recipientAddr,
            amount: scaled,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            textData: note,
            nonce: n + 1,
            extraInfoJSON: extraStr,
            zkProof: zk.proof,
            zkPub: zk.publicInput
        )
        let body = try MmnTransactionSigner.buildSignedAddTxBody(tx: tx, signingKey: ephemeral.signingKey)
        let addResult = try await MmnClient.shared.addTx(signed: body)
        if addResult.ok == true {
            await MmnSendTokenLogMessage.sendAfterUserIdTransferIfNeeded(
                context: context,
                payload: payload,
                isByAddress: isByAddress,
                amountInput: amountInput,
                note: note
            )
        }
        return addResult
    }

    static func sendGiveCoffee(
        context: AccountContext,
        receiverUserId: String,
        messageChannelId: String,
        messageClanId: String,
        messageRefId: String
    ) async throws -> MmnAddTxResult {
        giveCoffeeLock.lock()
        if isGiveCoffeeInFlight {
            giveCoffeeLock.unlock()
            throw MmnTransferError.giveCoffeeInProgress
        }
        isGiveCoffeeInFlight = true
        giveCoffeeLock.unlock()
        defer {
            giveCoffeeLock.lock()
            isGiveCoffeeInFlight = false
            giveCoffeeLock.unlock()
        }

        guard let u = context.currentUser else {
            throw NSError(domain: "MmnTransfer", code: 1, userInfo: [NSLocalizedDescriptionKey: "No user"])
        }
        let senderUserId = u.id
        guard !receiverUserId.isEmpty, receiverUserId != senderUserId else {
            throw NSError(domain: "MmnTransfer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid recipient"])
        }
        let (zk, ephemeral) = try loadCachedWalletCredentials(userId: senderUserId)
        let wallet = try await MmnClient.shared.getAccountByUserId(senderUserId)
        guard let scaled = MmnAmountScale.scaleToChainAmount(giveCoffeeAmountInput) else {
            throw NSError(domain: "MmnTransfer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid amount"])
        }
        if !MmnAmountScale.hasEnoughBalance(walletBalance: wallet.balance, sendScaled: scaled) {
            throw NSError(domain: "MmnTransfer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Insufficient balance"])
        }
        let senderAddr = MmnClient.addressFromUserId(senderUserId)
        let recipientAddr = MmnClient.addressFromUserId(receiverUserId)
        let nonceRes = try await MmnClient.shared.getCurrentNonce(address: senderAddr, tag: "pending")
        if let err = nonceRes.error, !err.isEmpty {
            throw NSError(domain: "MmnTransfer", code: 5, userInfo: [NSLocalizedDescriptionKey: err])
        }
        let n = nonceRes.nonce ?? 0
        let extra: [String: String] = [
            "type": "give_coffee",
            "ChannelId": messageChannelId.isEmpty ? "0" : messageChannelId,
            "ClanId": messageClanId.isEmpty ? "0" : messageClanId,
            "MessageRefId": messageRefId,
            "UserReceiverId": receiverUserId,
            "UserSenderId": senderUserId,
            "UserSenderUsername": u.username
        ]
        let extraData = try JSONSerialization.data(withJSONObject: extra)
        guard let extraStr = String(data: extraData, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        let tx = MmnTxMsgForSign(
            type: MmnTxType.transferByZK,
            sender: senderAddr,
            recipient: recipientAddr,
            amount: scaled,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            textData: giveCoffeeTextData,
            nonce: n + 1,
            extraInfoJSON: extraStr,
            zkProof: zk.proof,
            zkPub: zk.publicInput
        )
        let body = try MmnTransactionSigner.buildSignedAddTxBody(tx: tx, signingKey: ephemeral.signingKey)
        let addResult = try await MmnClient.shared.addTx(signed: body)
        if addResult.ok == true, let rec = Int64(receiverUserId) {
            do {
                try await MmnSendTokenLogMessage.sendGiveCoffeeTransferLog(
                    context: context,
                    receiverUserId: rec
                )
            } catch {
            }
        }
        return addResult
    }
}
