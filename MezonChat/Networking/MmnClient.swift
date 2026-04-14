import Foundation
import CryptoKit

struct WalletDetail: Decodable, Sendable {
    let address: String
    let balance: String
    let nonce: Int
    let decimals: Int
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

    func getAccountByUserId(_ userId: String) async throws -> WalletDetail {
        let address = Self.addressFromUserId(userId)
        return try await jsonRPC(method: "account.getaccount", params: ["address": address])
    }

    static func addressFromUserId(_ userId: String) -> String {
        let hash = SHA256.hash(data: Data(userId.utf8))
        return Base58.encode(Data(hash))
    }

    private struct RPCRequest: Encodable {
        let jsonrpc = "2.0"
        let method: String
        let params: [String: String]
        let id: Int
    }

    private struct RPCResponse<T: Decodable>: Decodable {
        let result: T?
        let error: RPCError?
    }

    private struct RPCError: Decodable {
        let code: Int?
        let message: String?
    }

    private func jsonRPC<T: Decodable>(method: String, params: [String: String]) async throws -> T {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(RPCRequest(method: method, params: params, id: 1))

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

private enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    static func encode(_ data: Data) -> String {
        var bytes = [UInt8](data)
        var result = [Character]()

        let leadingZeros = bytes.prefix(while: { $0 == 0 }).count

        while !bytes.isEmpty {
            var remainder = 0
            var quotient = [UInt8]()
            for byte in bytes {
                let acc = remainder * 256 + Int(byte)
                let digit = acc / 58
                remainder = acc % 58
                if !quotient.isEmpty || digit > 0 {
                    quotient.append(UInt8(digit))
                }
            }
            result.append(alphabet[remainder])
            bytes = quotient
        }

        let prefix = Array(repeating: alphabet[0], count: leadingZeros)
        return String(prefix + result.reversed())
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
        if fractional == 0 {
            return "0"
        }

        let fractionalStr = NSDecimalNumber(decimal: fractional * divisor)
            .stringValue
            .padding(toLength: decimals, withPad: "0", startingAt: 0)

        var trimmed = fractionalStr
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.isEmpty { return "0" }
        return "0,\(trimmed)"
    }
}
