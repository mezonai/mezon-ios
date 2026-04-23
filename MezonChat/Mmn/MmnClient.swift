import Foundation
import CryptoKit

struct WalletDetail: Decodable, Sendable {
    let address: String
    let balance: String
    let nonce: Int
    let decimals: Int
}

struct MmnGetCurrentNonceResult: Decodable, Sendable {
    let address: String?
    let nonce: Int?
    let tag: String?
    let error: String?
}

struct MmnAddTxResult: Decodable, Sendable {
    let ok: Bool?
    let tx_hash: String?
    let error: String?
}

final class MmnClient: Sendable {
    static let shared = MmnClient()

    private let session: URLSession
    private let baseURL: URL

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        baseURL = MezonConfig.mmnAPIURL
        MmnDebugLog.line("client baseURL=\(baseURL.absoluteString)")
    }

    func getAccountByUserId(_ userId: String) async throws -> WalletDetail {
        let address = Self.addressFromUserId(userId)
        MmnDebugLog.line("getAccountByUserId userId=\(userId) address=\(address)")
        let w: WalletDetail = try await jsonRPC(method: "account.getaccount", params: ["address": address])
        MmnDebugLog.line("getAccount result balance=\(w.balance) decimals=\(w.decimals) nonce=\(w.nonce)")
        return w
    }

    func getCurrentNonce(address: String, tag: String = "pending") async throws -> MmnGetCurrentNonceResult {
        MmnDebugLog.line("getCurrentNonce address=\(address) tag=\(tag)")
        let r: MmnGetCurrentNonceResult = try await jsonRPC(method: "account.getcurrentnonce", params: ["address": address, "tag": tag])
        MmnDebugLog.line("getCurrentNonce result nonce=\(String(describing: r.nonce)) error=\(r.error ?? "nil")")
        return r
    }

    func addTx(signed: [String: Any]) async throws -> MmnAddTxResult {
        MmnDebugLog.line("addTx submit…")
        let r: MmnAddTxResult = try await jsonRPC(method: "tx.addtx", params: signed)
        MmnDebugLog.line("addTx result ok=\(String(describing: r.ok)) tx_hash=\(r.tx_hash ?? "nil") error=\(r.error ?? "nil")")
        return r
    }

    static func addressFromUserId(_ userId: String) -> String {
        let hash = SHA256.hash(data: Data(userId.utf8))
        return MmnBase58.encode(Data(hash))
    }

    private struct RPCResponse<T: Decodable>: Decodable {
        let result: T?
        let error: RPCError?
    }

    private struct RPCError: Decodable {
        let code: Int?
        let message: String?
    }

    private func jsonRPC<T: Decodable>(method: String, params: [String: Any]) async throws -> T {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1,
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        if method == "tx.addtx" {
            MmnDebugLog.line("JSON-RPC method=\(method) bodySize=\(bodyData.count) bytes")
        } else if let s = String(data: bodyData, encoding: .utf8) {
            MmnDebugLog.line("JSON-RPC method=\(method) body=\(s)")
        }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            MmnDebugLog.line("JSON-RPC HTTP \(http.statusCode) data=\(String(data: data, encoding: .utf8) ?? "")")
            throw URLError(.badServerResponse)
        }
        if let raw = String(data: data, encoding: .utf8) {
            if raw.count > 2000 {
                MmnDebugLog.line("JSON-RPC response prefix=\(raw.prefix(2000))… (total \(raw.count) chars)")
            } else {
                MmnDebugLog.line("JSON-RPC response=\(raw)")
            }
        }
        let rpc = try JSONDecoder().decode(RPCResponse<T>.self, from: data)
        if let err = rpc.error {
            MmnDebugLog.line("JSON-RPC error code=\(String(describing: err.code)) message=\(err.message ?? "")")
            throw NSError(domain: "MmnClient", code: err.code ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: err.message ?? "Unknown RPC error"])
        }
        guard let result = rpc.result else {
            MmnDebugLog.line("JSON-RPC empty result")
            throw NSError(domain: "MmnClient", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Empty RPC result"])
        }
        return result
    }
}

enum MmnBase58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    static func encode(_ data: Data) -> String {
        var bytes = [UInt8](data)
        var result: [Character] = []
        let leadingZeros = bytes.prefix(while: { $0 == 0 }).count
        while !bytes.isEmpty {
            var remainder = 0
            var quotient: [UInt8] = []
            for byte in bytes {
                let acc = remainder * 256 + Int(byte)
                let div = acc / 58
                remainder = acc % 58
                if !quotient.isEmpty || div > 0 { quotient.append(UInt8(div)) }
            }
            result.append(alphabet[remainder])
            bytes = quotient
        }
        let prefix = Array(repeating: alphabet[0], count: leadingZeros)
        return String(prefix + result.reversed())
    }
}

enum MmnAmountScale {
    private static let decimals = 6

    static func scaleToChainAmount(_ displayAmount: String) -> String? {
        let cleaned = displayAmount.replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        var whole = "0"
        var frac = ""
        if let dot = cleaned.firstIndex(of: ".") {
            whole = String(cleaned[..<dot]) == "" ? "0" : String(cleaned[..<dot])
            frac = String(cleaned[cleaned.index(after: dot)...])
        } else {
            whole = cleaned
        }
        while frac.count < Self.decimals { frac.append("0") }
        if frac.count > Self.decimals {
            let idx = frac.index(frac.startIndex, offsetBy: Self.decimals)
            frac = String(frac[..<idx])
        }
        var combined = whole + frac
        while combined.first == "0" && combined.count > 1, combined.count > 1 { combined.removeFirst() }
        return combined.isEmpty ? "0" : combined
    }

    static func hasEnoughBalance(walletBalance: String, sendScaled: String) -> Bool {
        let w = trimLeadingZeros(walletBalance)
        let s = trimLeadingZeros(sendScaled)
        if w == s { return true }
        if w.count != s.count { return w.count > s.count }
        return w >= s
    }

    static func balanceAfterDeducting(wallet: String, send: String) -> String {
        let w = trimLeadingZeros(wallet)
        let s = trimLeadingZeros(send)
        if s == "0" { return w }
        guard let wDec = Decimal(string: w), let sDec = Decimal(string: s) else { return w }
        if wDec < sDec { return "0" }
        let d = wDec - sDec
        return trimLeadingZeros(NSDecimalNumber(decimal: d).stringValue)
    }

    private static func trimLeadingZeros(_ x: String) -> String {
        var v = x
        while v.count > 1, v.first == "0" { v.removeFirst() }
        return v
    }
}

enum MmnMoneyFormat {
    static let currencySymbol = "đ"
    static let noteMaxLength = 512
    private static let maxTokenDigits = 19

    static func onlyDigitCharacters(_ s: String) -> String {
        s.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
            .map { String($0) }
            .joined()
    }

    static func tokenAmountCaretCharacterIndex(display: String, digitIndex: Int) -> Int {
        let ns = display as NSString
        var digitsBefore = 0
        var i = 0
        while i < ns.length {
            if digitsBefore == digitIndex { return i }
            if CharacterSet.decimalDigits.contains(UnicodeScalar(ns.character(at: i))!) {
                digitsBefore += 1
            }
            i += 1
        }
        return ns.length
    }

    static func displayAfterTokenEdit(currentDisplay: String, range: NSRange, replacement: String) -> (display: String, plain: Int64, caretDigitIndex: Int)? {
        let ns = currentDisplay as NSString
        let n = ns.length
        guard range.location != NSNotFound, NSMaxRange(range) <= n else { return nil }
        let before = ns.substring(to: range.location)
        let dStart = onlyDigitCharacters(before).count
        let affected = ns.substring(with: range)
        let dLen = onlyDigitCharacters(affected).count
        let repDigits = onlyDigitCharacters(replacement)
        let oldDigits = onlyDigitCharacters(currentDisplay)
        if dStart > oldDigits.count { return nil }
        let p1 = String(oldDigits.prefix(dStart))
        let dropCount = dStart + dLen
        if dropCount > oldDigits.count { return nil }
        let p2 = String(oldDigits.dropFirst(dropCount))
        var newDigits = p1 + repDigits + p2
        if newDigits.count > maxTokenDigits { newDigits = String(newDigits.prefix(maxTokenDigits)) }
        var caretDigits = min(p1.count + repDigits.count, newDigits.count)
        if newDigits.isEmpty {
            return ("0", 0, 0)
        }
        while newDigits.count > 1, newDigits.hasPrefix("0") {
            newDigits.removeFirst()
            if caretDigits > 0 { caretDigits -= 1 }
        }
        let result = formatTokenAmount(newDigits)
        if result.plain == 0 {
            return (result.display, result.plain, 0)
        }
        let maxDigit = onlyDigitCharacters(result.display).count
        caretDigits = min(caretDigits, maxDigit)
        return (result.display, result.plain, caretDigits)
    }

    static func formatTokenAmount(_ raw: String) -> (display: String, plain: Int64) {
        let digitsOnly = raw.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        var s = String(String.UnicodeScalarView(digitsOnly))
        if s.isEmpty { return ("0", 0) }
        while s.count > 1, s.hasPrefix("0") { s.removeFirst() }
        let value = Int64(s) ?? 0
        if value == 0 { return ("0", 0) }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        let display = formatter.string(from: NSNumber(value: value)) ?? s
        return (display, value)
    }

    static func plainAmount(from displayed: String) -> Int64 {
        let digitsOnly = displayed.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        return Int64(String(String.UnicodeScalarView(digitsOnly))) ?? 0
    }

    static func formatBalanceToString(_ balance: String?, decimals: Int = 6) -> String {
        guard let balance, !balance.isEmpty else { return "0" }
        guard let big = Decimal(string: balance) else { return "0" }
        var divisor = Decimal(1)
        for _ in 0..<decimals { divisor *= 10 }
        let value = big / divisor

        let handler = NSDecimalNumberHandler(
            roundingMode: .down,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        let integerDecimal = (value as NSDecimalNumber).rounding(accordingToBehavior: handler) as Decimal

        if integerDecimal != 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = Locale(identifier: "vi_VN")
            formatter.maximumFractionDigits = 0
            return formatter.string(from: integerDecimal as NSDecimalNumber) ?? "0"
        }
        let fractional = value - integerDecimal
        if fractional == 0 { return "0" }
        let fractionalStr = NSDecimalNumber(decimal: fractional * divisor)
            .stringValue
            .padding(toLength: decimals, withPad: "0", startingAt: 0)
        var trimmed = fractionalStr
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.isEmpty { return "0" }
        return "0,\(trimmed)"
    }
}

enum BalanceFormatter {
    static func format(_ balance: String?, decimals: Int = 6) -> String {
        guard let balance, !balance.isEmpty else { return "0" }
        guard let big = Decimal(string: balance) else { return "0" }

        var divisor = Decimal(1)
        for _ in 0..<decimals {
            divisor *= 10
        }
        let value = big / divisor

        let handler = NSDecimalNumberHandler(
            roundingMode: .down,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        let integerDecimal = (value as NSDecimalNumber).rounding(accordingToBehavior: handler) as Decimal

        if integerDecimal != 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = Locale(identifier: "vi-VN")
            formatter.maximumFractionDigits = 0
            return formatter.string(from: integerDecimal as NSDecimalNumber) ?? "0"
        }

        let fractional = value - integerDecimal
        if fractional == 0 { return "0" }

        let fractionalStr = NSDecimalNumber(decimal: fractional * divisor)
            .stringValue
            .padding(toLength: decimals, withPad: "0", startingAt: 0)

        var trimmed = fractionalStr
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.isEmpty { return "0" }
        return "0,\(trimmed)"
    }
}

enum MmnJWT {
    static func expirationDate(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        let pad = (4 - payload.count % 4) % 4
        if pad > 0 { payload += String(repeating: "=", count: pad) }
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let exp = obj["exp"] as? Double {
            return Date(timeIntervalSince1970: exp)
        }
        if let exp = obj["exp"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(exp))
        }
        if let exp = obj["exp"] as? Int64 {
            return Date(timeIntervalSince1970: TimeInterval(exp))
        }
        return nil
    }

    static func isExpired(_ jwt: String, leeway: TimeInterval = 90) -> Bool {
        guard let exp = expirationDate(jwt) else { return false }
        return Date() >= exp.addingTimeInterval(-leeway)
    }
}
