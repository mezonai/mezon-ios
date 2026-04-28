import Foundation
import CryptoKit

enum MmnEd25519PKCS8 {
    private static let ed25519OID: [UInt8] = [0x06, 0x03, 0x2b, 0x65, 0x70]
    private static let ed25519SeedLength = 32

    static func pkcs8Hex(fromSeed32 seed: Data) -> String {
        precondition(seed.count == ed25519SeedLength)
        let version: [UInt8] = [0x02, 0x01, 0x00]
        let algorithmId: [UInt8] = [0x30, 0x0b] + ed25519OID
        let privateKeyOctet: [UInt8] = [0x04, 0x22, 0x04, 0x20] + [UInt8](seed)
        let pkcs8Body: [UInt8] = version + algorithmId + privateKeyOctet
        var pkcs8: [UInt8] = [0x30, UInt8(2 + pkcs8Body.count)]
        pkcs8.append(contentsOf: pkcs8Body)
        return Data(pkcs8).map { String(format: "%02x", $0) }.joined()
    }
}

struct MmnEphemeralKeyPair: Sendable {
    let publicKeyBase58: String
    let privateKeyPkcs8Hex: String
    let signingKey: Curve25519.Signing.PrivateKey
    let seed: Data

    static func generate() throws -> MmnEphemeralKeyPair {
        var seed = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, 32, &seed)
        guard status == errSecSuccess else {
            throw NSError(domain: "MmnKey", code: -1, userInfo: [NSLocalizedDescriptionKey: "SecRandom failed"])
        }
        let data = Data(seed)
        return try fromSeed(data)
    }

    static func fromSeed(_ seed: Data) throws -> MmnEphemeralKeyPair {
        guard seed.count == 32 else {
            throw NSError(domain: "MmnKey", code: -2, userInfo: [NSLocalizedDescriptionKey: "Seed must be 32 bytes"])
        }
        let sk = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        let publicKeyBase58 = MmnBase58.encode(sk.publicKey.rawRepresentation)
        let pkcs8 = MmnEd25519PKCS8.pkcs8Hex(fromSeed32: seed)
        return MmnEphemeralKeyPair(publicKeyBase58: publicKeyBase58, privateKeyPkcs8Hex: pkcs8, signingKey: sk, seed: seed)
    }
}

enum MmnTxType {
    static let transferByZK: Int = 0
    static let transferByKey: Int = 1
}

struct MmnTxMsgForSign: Sendable {
    var type: Int
    var sender: String
    var recipient: String
    var amount: String
    var timestamp: Int64
    var textData: String
    var nonce: Int
    var extraInfoJSON: String
    var zkProof: String
    var zkPub: String

    var serializationLine: String {
        "\(type)|\(sender)|\(recipient)|\(amount)|\(textData)|\(nonce)|\(extraInfoJSON)"
    }

    var asAddTxMessage: [String: Any] {
        [
            "type": type,
            "sender": sender,
            "recipient": recipient,
            "amount": amount,
            "timestamp": timestamp,
            "text_data": textData,
            "nonce": nonce,
            "extra_info": extraInfoJSON,
            "zk_proof": zkProof,
            "zk_pub": zkPub
        ]
    }
}

enum MmnTransactionSigner {
    static func buildSignatureString(serialized: Data, signingKey: Curve25519.Signing.PrivateKey) throws -> String {
        let sig = try signingKey.signature(for: serialized)
        let pubB64 = signingKey.publicKey.rawRepresentation.base64EncodedString()
        let sigB64 = sig.base64EncodedString()
        let json = "{\"PubKey\":\"\(pubB64)\",\"Sig\":\"\(sigB64)\"}"
        return MmnBase58.encode(Data(json.utf8))
    }

    static func buildSignedAddTxBody(tx: MmnTxMsgForSign, signingKey: Curve25519.Signing.PrivateKey) throws -> [String: Any] {
        let line = Data(tx.serializationLine.utf8)
        let signature = try buildSignatureString(serialized: line, signingKey: signingKey)
        return ["tx_msg": tx.asAddTxMessage, "signature": signature]
    }
}
