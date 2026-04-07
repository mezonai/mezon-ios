import Foundation

enum ImgproxyURL {

    private static let proxyBase = "https://imgproxy.mezon.ai/K0YUZRIosDOcz5lY6qrgC6UIXmQgWzLjZv7VJ1RAA8c"
    private static let cdnHosts = ["cdn.mezon", "profile.mezon"]
    private static let skipExtensions: Set<String> = ["gif", "webp"]

    private static let attachmentOutputSuffix = "@jpeg"

    static func attachmentURL(
        from sourceURL: String,
        width: Int,
        height: Int,
        resizeType: String = "fit"
    ) -> String {
        guard !sourceURL.isEmpty else { return sourceURL }
        guard cdnHosts.contains(where: { sourceURL.contains($0) }) else {
            return sourceURL
        }
        let w = max(1, width)
        let h = max(1, height)
        let processingOptions = "rs:\(resizeType):\(w):\(h):1/mb:2097152"
        let encodedSource = sourceURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sourceURL
        return "\(proxyBase)/\(processingOptions)/plain/\(encodedSource)\(attachmentOutputSuffix)"
    }

    static func create(
        from sourceURL: String,
        width: Int = 100,
        height: Int = 100,
        resizeType: String = "fit"
    ) -> String {
        guard !sourceURL.isEmpty else { return sourceURL }

        let ext = (sourceURL as NSString).pathExtension.lowercased()
        if skipExtensions.contains(ext) {
            return sourceURL
        }

        guard cdnHosts.contains(where: { sourceURL.contains($0) }) else {
            return sourceURL
        }

        let processingOptions = "rs:\(resizeType):\(width):\(height):1/mb:2097152"
        let encodedSource = sourceURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sourceURL
        return "\(proxyBase)/\(processingOptions)/plain/\(encodedSource)@webp"
    }


    static func createEmoji(from sourceURL: String, width: Int, height: Int, resizeType: String = "fit") -> String {
        guard !sourceURL.isEmpty else { return sourceURL }
        guard cdnHosts.contains(where: { sourceURL.contains($0) }) else {
            return sourceURL
        }
        let processingOptions = "rs:\(resizeType):\(width):\(height):1/mb:2097152"
        let encodedSource = sourceURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sourceURL
        return "\(proxyBase)/\(processingOptions)/plain/\(encodedSource)@webp"
    }
}
