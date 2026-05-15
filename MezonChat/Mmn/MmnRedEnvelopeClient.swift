import Foundation

enum LuckyMoneyQRParse {
    static func luckyMoneyId(from s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("{"), let d = t.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        if let id = o["lucky_money_id"] as? String {
            let x = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return x.isEmpty ? nil : x
        }
        if let id = o["lucky_money_id"] as? Int64 { return String(id) }
        if let id = o["lucky_money_id"] as? Int { return String(id) }
        if let id = o["lucky_money_id"] as? Double { return String(Int64(id)) }
        return nil
    }
}

enum MmnRedEnvelopeError: Error, LocalizedError {
    case serviceNotConfigured
    case walletNotReady
    case httpStatus(Int, String?)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .serviceNotConfigured:
            return L(L10n.QRScanner.luckyMoneyServiceNotConfigured)
        case .walletNotReady:
            return L(L10n.QRScanner.luckyMoneyWalletNotReady)
        case .httpStatus(let code, let body):
            let fallback = code > 0 ? "HTTP \(code)" : L(L10n.QRScanner.luckyMoneyClaimFailed)
            return DongAPIErrorFormat.userMessage(from: body, fallback: fallback)
        case .invalidPayload:
            return L(L10n.QRScanner.luckyMoneyInvalidPayload)
        }
    }
}

struct MmnRedEnvelopeClaimAmountData: Decodable {
    let split_money_id: Int64
    let amount: Int64
    let description: String?

    enum CodingKeys: String, CodingKey {
        case split_money_id
        case amount
        case description
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        split_money_id = try Self.decodeInt64(c, key: .split_money_id)
        amount = try Self.decodeInt64(c, key: .amount)
        description = try c.decodeIfPresent(String.self, forKey: .description)
    }

    private static func decodeInt64(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Int64 {
        if let v = try? c.decode(Int64.self, forKey: key) { return v }
        if let v = try? c.decode(Int.self, forKey: key) { return Int64(v) }
        if let v = try? c.decode(Double.self, forKey: key) { return Int64(v) }
        if let s = try? c.decode(String.self, forKey: key), let v = Int64(s) { return v }
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Expected number")
    }
}

private struct DongEnvelope<T: Decodable>: Decodable {
    let data: T?
}

private enum DongAPIErrorFormat {
    static func userMessage(from raw: String?, fallback: String) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return fallback }
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return raw
        }
        if let m = obj["message"] as? String {
            let t = m.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        if let d = obj["data"] as? [String: Any], let m = d["message"] as? String {
            let t = m.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        if raw.hasPrefix("{") { return fallback }
        return raw
    }
}

enum MmnRedEnvelopeClient {
    private static func normalizedBase(_ base: URL) -> String {
        base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func requestURL(path: String, query: [String: String]) throws -> URL {
        let base = MezonConfig.dongServiceAPIURL
        let p = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let raw = "\(normalizedBase(base))/\(p)"
        var comp = URLComponents(string: raw)
        if !query.isEmpty {
            comp?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comp?.url else { throw MmnRedEnvelopeError.serviceNotConfigured }
        return url
    }

    private static func zkCredentials(userId: String) throws -> (proof: String, publicInput: String, publicKey: String) {
        MmnWalletStore.shared.bind(userId: userId)
        guard let zk = MmnWalletStore.shared.zkProofs,
              let ephemeral = MmnWalletStore.shared.ephemeralKeyPair() else {
            throw MmnRedEnvelopeError.walletNotReady
        }
        return (zk.proof, zk.publicInput, ephemeral.publicKeyBase58)
    }

    static func claimAmount(luckyMoneyId: String, userId: String) async throws -> MmnRedEnvelopeClaimAmountData {
        let cred = try zkCredentials(userId: userId)
        let url = try requestURL(path: "api/v1/red-envelopes/qr/claim-amount", query: ["id": luckyMoneyId])
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "user_id": userId,
            "proof_b64": cred.proof,
            "public_b64": cred.publicInput,
            "publickey": cred.publicKey,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw MmnRedEnvelopeError.httpStatus(-1, nil) }
        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8)
            throw MmnRedEnvelopeError.httpStatus(http.statusCode, msg)
        }
        if let env = try? JSONDecoder().decode(DongEnvelope<MmnRedEnvelopeClaimAmountData>.self, from: data),
           let inner = env.data {
            return inner
        }
        if let inner = try? JSONDecoder().decode(MmnRedEnvelopeClaimAmountData.self, from: data) {
            return inner
        }
        throw MmnRedEnvelopeError.invalidPayload
    }

    static func claimRedEnvelope(luckyMoneyId: String, splitMoneyId: Int64, userId: String) async throws {
        let cred = try zkCredentials(userId: userId)
        let url = try requestURL(
            path: "api/v1/red-envelopes/qr/\(luckyMoneyId)/claim",
            query: [:]
        )
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "split_money_id": splitMoneyId,
            "user_id": userId,
            "proof_b64": cred.proof,
            "public_b64": cred.publicInput,
            "publickey": cred.publicKey,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw MmnRedEnvelopeError.httpStatus(-1, nil) }
        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8)
            throw MmnRedEnvelopeError.httpStatus(http.statusCode, msg)
        }
        _ = data
    }
}
