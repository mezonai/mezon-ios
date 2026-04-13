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
        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let image = UIImage.animatedImage(from: data) ?? UIImage.decodeImage(from: data)
            else {
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
