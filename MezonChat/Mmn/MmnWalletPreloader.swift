import Foundation

enum MmnWalletPreloader {
    @available(iOS 13.0, *)
    static func fetchAndPersistAfterLogin(session: MezonSession) {
        let userId = session.userId ?? ""
        let idToken = session.idToken ?? ""
        guard !userId.isEmpty else {
            return
        }
        guard !idToken.isEmpty else {
            return
        }
        if MmnJWT.isExpired(idToken) {
            return
        }
        MmnWalletStore.shared.bind(userId: userId)
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
            } catch {
            }
        }
    }
}
