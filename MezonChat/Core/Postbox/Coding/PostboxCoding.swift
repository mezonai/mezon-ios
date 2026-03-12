import Foundation

protocol PostboxCoding: Codable {}

extension PostboxCoding {

    func postboxEncode() -> Data? {
        try? JSONEncoder().encode(self)
    }
}

extension PostboxCoding {

    static func postboxDecode(from data: Data) -> Self? {
        try? JSONDecoder().decode(Self.self, from: data)
    }
}

extension Array where Element: PostboxCoding {

    func postboxEncode() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func postboxDecode(from data: Data) -> [Element]? {
        try? JSONDecoder().decode([Element].self, from: data)
    }
}
