import Foundation
import UIKit

enum ReactionEmojiImageLoader {

    @discardableResult
    static func load(from url: URL, completion: @escaping (UIImage?) -> Void) -> URLSessionDataTask? {
        let key = url.absoluteString
        if let diskData = ImageCache.shared.cachedData(forKey: key) {
            let image = UIImage.animatedImage(from: diskData) ?? UIImage.decodeImage(from: diskData)
            if let image {
                ImageCache.shared.setImage(image, data: nil, forKey: key)
                DispatchQueue.main.async { completion(image) }
                return nil
            }
        }
        if let cached = ImageCache.shared.image(forKey: key) {
            DispatchQueue.main.async { completion(cached) }
            return nil
        }
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            #if DEBUG
            let status = (response as? HTTPURLResponse)?.statusCode
            if error != nil || status.map({ $0 != 200 }) == true || data == nil {
                print(
                    "[EmojiURL] fetch emojiId url=\(url.absoluteString) http=\(String(describing: status)) bytes=\(data?.count ?? 0) error=\(String(describing: error))"
                )
            }
            #endif
            guard let data,
                  let image = UIImage.animatedImage(from: data) ?? UIImage.decodeImage(from: data)
            else {
                #if DEBUG
                if let data, !data.isEmpty {
                    let snippet = String(data: data.prefix(120), encoding: .utf8) ?? "<binary>"
                    print("[EmojiURL] decode failed url=\(url.absoluteString) len=\(data.count) snippet=\(snippet)")
                }
                #endif
                DispatchQueue.main.async { completion(nil) }
                return
            }
            ImageCache.shared.setImage(image, data: data, forKey: key)
            DispatchQueue.main.async { completion(image) }
        }
        task.resume()
        return task
    }

    @discardableResult
    static func load(emojiId: String, imgproxyFitSide: Int, completion: @escaping (UIImage?) -> Void) -> URLSessionDataTask? {
        guard let url = MezonConfig.emojiResourceURL(emojiId: emojiId, imgproxyFitSide: imgproxyFitSide) else {
            DispatchQueue.main.async { completion(nil) }
            return nil
        }
        return load(from: url, completion: completion)
    }
}
