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

struct MmnTransaction: Decodable, Sendable {
    let hash: String
    let from_address: String?
    let to_address: String?
    let value: Int64?
    let transaction_timestamp: Int64?
    let from_username: String?
    let to_username: String?
    let sender_name: String?
    let receiver_name: String?
    let note: String?
    let extra_info: String?

    enum CodingKeys: String, CodingKey {
        case hash = "hash"
        case tx_hash = "tx_hash"
        case transaction_hash = "transaction_hash"
        case from_address = "from_address"
        case to_address = "to_address"
        case value = "value"
        case transaction_timestamp = "transaction_timestamp"
        case from_username = "from_username"
        case to_username = "to_username"
        case sender_name = "sender_name"
        case receiver_name = "receiver_name"
        case from_user = "from_user"
        case to_user = "to_user"
        case note = "note"
        case data = "data"
        case text_data = "text_data"
        case extra_info = "extra_info"
    }

    struct MmnUser: Decodable {
        let username: String?
        let name: String?
    }
    
    struct ExtraInfoWrapper: Decodable {
        let UserSenderId: String?
        let UserReceiverId: String?
        
        enum CodingKeys: String, CodingKey {
            case UserSenderId, UserReceiverId
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let s = try? container.decode(String.self, forKey: .UserSenderId) { UserSenderId = s }
            else if let i = try? container.decode(Int64.self, forKey: .UserSenderId) { UserSenderId = String(i) }
            else { UserSenderId = nil }
            
            if let s = try? container.decode(String.self, forKey: .UserReceiverId) { UserReceiverId = s }
            else if let i = try? container.decode(Int64.self, forKey: .UserReceiverId) { UserReceiverId = String(i) }
            else { UserReceiverId = nil }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let h = try? container.decode(String.self, forKey: .hash) {
            hash = h
        } else if let th = try? container.decode(String.self, forKey: .tx_hash) {
            hash = th
        } else if let tbh = try? container.decode(String.self, forKey: .transaction_hash) {
            hash = tbh
        } else {
            hash = ""
        }
        
        from_address = try? container.decode(String.self, forKey: .from_address)
        to_address = try? container.decode(String.self, forKey: .to_address)
        
        if let vInt = try? container.decode(Int64.self, forKey: .value) {
            value = vInt
        } else if let vStr = try? container.decode(String.self, forKey: .value), let v = Int64(vStr) {
            value = v
        } else {
            value = nil
        }
        
        if let tInt = try? container.decode(Int64.self, forKey: .transaction_timestamp) {
            transaction_timestamp = tInt
        } else if let tStr = try? container.decode(String.self, forKey: .transaction_timestamp), let t = Int64(tStr) {
            transaction_timestamp = t
        } else {
            transaction_timestamp = nil
        }
        
        var fName = try? container.decode(String.self, forKey: .from_username)
        if fName == nil { fName = try? container.decode(String.self, forKey: .sender_name) }
        if fName == nil, let user = try? container.decode(MmnUser.self, forKey: .from_user) {
            fName = user.username ?? user.name
        }
        from_username = fName
        
        var tName = try? container.decode(String.self, forKey: .to_username)
        if tName == nil { tName = try? container.decode(String.self, forKey: .receiver_name) }
        if tName == nil, let user = try? container.decode(MmnUser.self, forKey: .to_user) {
            tName = user.username ?? user.name
        }
        to_username = tName
        
        sender_name = fName
        receiver_name = tName
        
        var noteStr = try? container.decode(String.self, forKey: .note)
        if noteStr == nil { noteStr = try? container.decode(String.self, forKey: .data) }
        if noteStr == nil { noteStr = try? container.decode(String.self, forKey: .text_data) }
        note = noteStr
        
        if let str = try? container.decode(String.self, forKey: .extra_info) {
            extra_info = str
        } else if let wrapper = try? container.decode(ExtraInfoWrapper.self, forKey: .extra_info) {
            var dict: [String: String] = [:]
            if let s = wrapper.UserSenderId { dict["UserSenderId"] = s }
            if let r = wrapper.UserReceiverId { dict["UserReceiverId"] = r }
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let str = String(data: data, encoding: .utf8) {
                extra_info = str
            } else {
                extra_info = nil
            }
        } else {
            extra_info = nil
        }
    }
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
    }

    @available(iOS 13.0, *)
    func getAccountByUserId(_ userId: String) async throws -> WalletDetail {
        let address = Self.addressFromUserId(userId)
        let w: WalletDetail = try await jsonRPC(method: "account.getaccount", params: ["address": address])
        return w
    }

    @available(iOS 13.0, *)
    func getCurrentNonce(address: String, tag: String = "pending") async throws -> MmnGetCurrentNonceResult {
        let r: MmnGetCurrentNonceResult = try await jsonRPC(method: "account.getcurrentnonce", params: ["address": address, "tag": tag])
        return r
    }

    @available(iOS 13.0, *)
    func addTx(signed: [String: Any]) async throws -> MmnAddTxResult {
        let r: MmnAddTxResult = try await jsonRPC(method: "tx.addtx", params: signed)
        return r
    }

    @available(iOS 13.0, *)
    func getTransactionDetail(hash: String) async throws -> MmnTransaction {
        var indexerURLString = baseURL.absoluteString.replacingOccurrences(of: "mmn-api", with: "indexer-api")
        if !indexerURLString.hasSuffix("/") { indexerURLString += "/" }
        indexerURLString += "1337/tx/\(hash)/detail"
        
        guard let url = URL(string: indexerURLString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        struct Resp: Decodable {
            let data: RespData
        }
        struct RespData: Decodable {
            let transaction: MmnTransaction
        }
        
        let r = try JSONDecoder().decode(Resp.self, from: data)
        return r.data.transaction
    }

    @available(iOS 13.0, *)
    func getTransactionHistory(address: String, filter: String, timeStamp: String? = nil, lastHash: String? = nil) async throws -> [MmnTransaction] {
        var indexerURLString = baseURL.absoluteString.replacingOccurrences(of: "mmn-api", with: "indexer-api")
        if !indexerURLString.hasSuffix("/") { indexerURLString += "/" }
        indexerURLString += "1337/transactions/infinite"
        
        guard var comps = URLComponents(string: indexerURLString) else { throw URLError(.badURL) }
        var queryItems = [URLQueryItem(name: "limit", value: "20")]
        
        if let ts = timeStamp { queryItems.append(URLQueryItem(name: "timestamp_lt", value: ts)) }
        if let lh = lastHash { queryItems.append(URLQueryItem(name: "last_hash", value: lh)) }
        
        if filter == "2" || filter == "SENT" || filter == "outgoing" {
            queryItems.append(URLQueryItem(name: "filter_from_address", value: address))
        } else if filter == "1" || filter == "RECEIVED" || filter == "incoming" {
            queryItems.append(URLQueryItem(name: "filter_to_address", value: address))
        } else {
            queryItems.append(URLQueryItem(name: "wallet_address", value: address))
        }
        
        comps.queryItems = queryItems
        guard let finalURL = comps.url else { throw URLError(.badURL) }
        
        var req = URLRequest(url: finalURL)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        struct IndexerResponse: Decodable {
            let data: [MmnTransaction]?
        }
        
        let (data, response) = try await session.data(for: req)
        
        if let httpRes = response as? HTTPURLResponse, !(200...299).contains(httpRes.statusCode) {
            let errorMsg = String(data: data, encoding: .utf8) ?? "none"
            if httpRes.statusCode >= 500 {
                throw NSError(domain: "MmnClient", code: httpRes.statusCode, userInfo: [NSLocalizedDescriptionKey: L(L10n.Error.somethingWentWrong)])
            }
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        let res = try decoder.decode(IndexerResponse.self, from: data)
        return res.data ?? []
    }

    @available(iOS 13.0, *)

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

    @available(iOS 13.0, *)
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

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let rpc = try JSONDecoder().decode(RPCResponse<T>.self, from: data)
        if let err = rpc.error {
            throw NSError(domain: "MmnClient", code: err.code ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: err.message ?? "Unknown RPC error"])
        }
        guard let result = rpc.result else {
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
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
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
