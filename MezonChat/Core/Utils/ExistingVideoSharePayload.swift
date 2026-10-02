import Foundation

struct ExistingVideoSharePayload: Codable {
    static let internalScheme = "mezon-video-share"
    static let appGroupIdentifier = "group.mezon.mobile"
    static let tokenKeyPrefix = "mezon.video-share.token."
    static let tokenLifetime: TimeInterval = 10 * 60

    let url: String
    let thumbnail: String
    let filename: String
    let filetype: String
    let size: Int64
    let width: Int
    let height: Int
    let durationSeconds: Int
}

struct ExistingVideoShareTokenRecord: Codable {
    let createdAt: TimeInterval
    let payload: ExistingVideoSharePayload
}
