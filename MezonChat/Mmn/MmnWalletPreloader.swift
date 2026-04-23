import Foundation

@MainActor
enum MmnWalletPreloader {
    static func fetchAndPersistAfterLogin(session: MezonSession) {
        let userId = session.userId ?? ""
        let idToken = session.idToken ?? ""
        guard !userId.isEmpty else {
            MmnDebugLog.line("walletPreloader skip: empty userId")
            return
        }
        guard !idToken.isEmpty else {
            MmnDebugLog.line("walletPreloader skip: empty id_token (userId=\(userId))")
            return
        }
        if MmnJWT.isExpired(idToken) {
            MmnDebugLog.line("walletPreloader skip: id_token already expired")
            return
        }
        MmnWalletStore.shared.bind(userId: userId)
        MmnDebugLog.line("walletPreloader start userId=\(userId) idTokenLen=\(idToken.count)")
        Task.detached {
            do {
                let ephemeral = try MmnEphemeralKeyPair.generate()
                let address = MmnClient.addressFromUserId(userId)
                let prover = ZkProverClient()
                let bundle = try await prover.fetchProofs(
                    userId: userId,
                    jwt: idToken,
                    ephemeralPublicKeyBase58: ephemeral.publicKeyBase58,
                    address: address
                )
                let zk = MmnPersistedZkProofs(proof: bundle.proof, publicInput: bundle.publicInput)
                let key = MmnPersistedEphemeralKey(
                    publicKeyBase58: ephemeral.publicKeyBase58,
                    seedBase64: ephemeral.seed.base64EncodedString()
                )
                await MainActor.run {
                    MmnWalletStore.shared.setZkProofs(zk, ephemeralKey: key, userId: userId)
                }
                MmnDebugLog.line("walletPreloader ok userId=\(userId)")
            } catch {
                MmnDebugLog.line("walletPreloader fail: \(error.localizedDescription)")
            }
        }
    }
}
