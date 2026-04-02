


import Foundation

func safeJsonDecode<T: Decodable>(
    _ jsonString: String,
    to type: T.Type,
    fallback: T? = nil
) -> T? {
    guard !jsonString.isEmpty,
          jsonString != "null",
          let data = jsonString.data(using: .utf8) else {
        return fallback
    }

    do {
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        return fallback
    }
}

