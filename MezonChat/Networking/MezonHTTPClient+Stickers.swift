import Foundation
import SwiftProtobuf

extension MezonHTTPClient {
    func addClanSticker(request: Mezon_Api_ClanStickerAddRequest, token: String) async throws -> Mezon_Api_ClanSticker {
        return try await postProto(
            path: "/mezon.api.Mezon/AddClanSticker",
            message: request,
            auth: .bearer(token),
            preferHTTPFirst: false
        )
    }

    func updateClanSticker(request: Mezon_Api_ClanStickerUpdateByIdRequest, token: String) async throws -> Mezon_Api_ClanSticker {
        return try await postProto(
            path: "/mezon.api.Mezon/UpdateClanStickerById",
            message: request,
            auth: .bearer(token),
            preferHTTPFirst: false
        )
    }

    func deleteClanSticker(request: Mezon_Api_ClanStickerDeleteRequest, token: String) async throws {
        try await postProtoIgnoringBody(
            path: "/mezon.api.Mezon/DeleteClanStickerById",
            message: request,
            auth: .bearer(token)
        )
    }
}
