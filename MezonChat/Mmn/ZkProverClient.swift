import Foundation

struct ZkProofBundle: Sendable {
    let proof: String
    let publicInput: String
}

struct ZkProverDataDTO: Decodable, Sendable {
    let proof: String
    let public_input: String
}

struct ZkProverTopDTO: Decodable, Sendable {
    let data: ZkProverDataDTO
}

enum ZkProverError: Error {
    case authenticationFailed
}

struct ZkProverClient: Sendable {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = MezonConfig.zkAPIURL) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: .default)
    }

    @available(iOS 13.0, *)
    func fetchProofs(userId: String, jwt: String, ephemeralPublicKeyBase58: String, address: String) async throws -> ZkProofBundle {
        let u = baseURL.appendingPathComponent("prove")
        var request = URLRequest(url: u)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "user_id": userId,
            "ephemeral_pk": ephemeralPublicKeyBase58,
            "jwt": jwt,
            "address": address,
            "client_type": "mezon"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 400, body.localizedCaseInsensitiveContains("authentication") {
                throw ZkProverError.authenticationFailed
            }
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ZkProverTopDTO.self, from: data)
        return ZkProofBundle(proof: decoded.data.proof, publicInput: decoded.data.public_input)
    }
}
