import UIKit
import ImageIO
import MobileCoreServices
import AVFoundation
import os.log

private let logger = OSLog(subsystem: "mezon.mobile.MezonSharing", category: "ShareExtension")

private enum ShareUTI {
    static let image = kUTTypeImage as String
    static let movie = kUTTypeMovie as String
    static let fileURL = kUTTypeFileURL as String
    static let url = kUTTypeURL as String
    static let plainText = kUTTypePlainText as String
}

class ShareViewController: UIViewController {

    private let hostAppBundleIdentifier = "mezon.mobile"
    private let shareProtocol = "mezon.mobile.sharing"
    private let sharedKey = "mezon.mobile.sharing"
    private let appGroupIdentifier = "group.mezon.mobile"

    private var sharedMedia: [SharedMediaFile] = []
    private var sharedText: [String] = []
    private var pendingItems = 0
    private var processedItems = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        os_log("[MezonSharing] viewDidLoad called", log: logger, type: .info)
        NSLog("[MezonSharing] viewDidLoad called")
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        os_log("[MezonSharing] viewDidAppear called", log: logger, type: .info)
        NSLog("[MezonSharing] viewDidAppear - starting processInputItems")
        processInputItems()
    }

    private func processInputItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            NSLog("[MezonSharing] ERROR: No extensionContext or inputItems")
            dismissWithError(message: "No content to share")
            return
        }

        NSLog("[MezonSharing] Found %d extension items", extensionItems.count)

        guard let extensionItem = extensionItems.first,
              let attachments = extensionItem.attachments, !attachments.isEmpty else {
            NSLog("[MezonSharing] ERROR: No attachments found")
            dismissWithError(message: "No content to share")
            return
        }

        pendingItems = attachments.count
        processedItems = 0
        NSLog("[MezonSharing] Processing %d attachments", pendingItems)

        for (index, attachment) in attachments.enumerated() {
            let identifiers = attachment.registeredTypeIdentifiers
            NSLog("[MezonSharing] Attachment %d types: %@", index, identifiers.joined(separator: ", "))

            if attachment.hasItemConformingToTypeIdentifier(ShareUTI.image) {
                NSLog("[MezonSharing] Handling as IMAGE")
                handleImages(attachment: attachment, index: index)
            } else if attachment.hasItemConformingToTypeIdentifier(ShareUTI.movie) {
                NSLog("[MezonSharing] Handling as VIDEO")
                handleVideos(attachment: attachment, index: index)
            } else if attachment.hasItemConformingToTypeIdentifier(ShareUTI.fileURL) {
                NSLog("[MezonSharing] Handling as FILE")
                handleFiles(attachment: attachment, index: index)
            } else if attachment.hasItemConformingToTypeIdentifier(ShareUTI.url) {
                NSLog("[MezonSharing] Handling as URL")
                handleUrl(attachment: attachment, index: index)
            } else if attachment.hasItemConformingToTypeIdentifier(ShareUTI.plainText) {
                NSLog("[MezonSharing] Handling as TEXT")
                handleText(attachment: attachment, index: index)
            } else {
                NSLog("[MezonSharing] SKIP: Unsupported type")
                itemProcessed()
            }
        }
    }

    private func handleImages(attachment: NSItemProvider, index: Int) {
        attachment.loadItem(forTypeIdentifier: ShareUTI.image, options: nil) { [weak self] data, error in
            guard let self = self else { return }

            if let error = error {
                NSLog("[MezonSharing] Image load error: %@", error.localizedDescription)
                self.itemProcessed()
                return
            }

            var url: URL?
            if let dataURL = data as? URL {
                NSLog("[MezonSharing] Image loaded as URL: %@", dataURL.absoluteString)
                url = dataURL
            } else if let image = data as? UIImage {
                NSLog("[MezonSharing] Image loaded as UIImage, saving screenshot")
                url = self.saveScreenshot(image)
            } else if let imageData = data as? Data, let image = UIImage(data: imageData) {
                NSLog("[MezonSharing] Image loaded as Data (%d bytes), saving", imageData.count)
                url = self.saveScreenshot(image)
            } else {
                NSLog("[MezonSharing] Image loaded as unknown type: %@, trying Data fallback", String(describing: type(of: data)))
                if #available(iOSApplicationExtension 14.0, iOS 14.0, *) {
                    attachment.loadDataRepresentation(forTypeIdentifier: ShareUTI.image) { rawData, rawError in
                        if let rawData = rawData, let image = UIImage(data: rawData) {
                            NSLog("[MezonSharing] Fallback: loaded image from raw data (%d bytes)", rawData.count)
                            let savedURL = self.saveScreenshot(image)
                            if let savedURL = savedURL {
                                self.sharedMedia.append(SharedMediaFile(
                                    path: savedURL.absoluteString,
                                    thumbnail: nil,
                                    duration: nil,
                                    type: .image
                                ))
                            }
                        } else {
                            NSLog("[MezonSharing] Fallback failed: %@", rawError?.localizedDescription ?? "unknown")
                        }
                        self.itemProcessed()
                    }
                } else {
                    self.itemProcessed()
                }
                return
            }

            guard let sourceURL = url else {
                NSLog("[MezonSharing] ERROR: No source URL for image")
                self.itemProcessed()
                return
            }

            let fileExtension = self.getExtension(from: sourceURL, type: .image)
            let newName = UUID().uuidString
            guard let newPath = self.sharedContainerURL()?.appendingPathComponent("\(newName).\(fileExtension)") else {
                NSLog("[MezonSharing] ERROR: Cannot create shared container path")
                self.itemProcessed()
                return
            }

            if self.copyFile(at: sourceURL, to: newPath) {
                NSLog("[MezonSharing] Image copied to: %@", newPath.absoluteString)
                self.sharedMedia.append(SharedMediaFile(
                    path: newPath.absoluteString,
                    thumbnail: nil,
                    duration: nil,
                    type: .image
                ))
            }

            self.itemProcessed()
        }
    }

    private func handleVideos(attachment: NSItemProvider, index: Int) {
        attachment.loadItem(forTypeIdentifier: ShareUTI.movie, options: nil) { [weak self] data, error in
            guard let self = self, error == nil, let url = data as? URL else {
                NSLog("[MezonSharing] Video load error: %@", error?.localizedDescription ?? "unknown")
                self?.itemProcessed()
                return
            }

            let fileExtension = self.getExtension(from: url, type: .video)
            let newName = UUID().uuidString
            guard let newPath = self.sharedContainerURL()?.appendingPathComponent("\(newName).\(fileExtension)") else {
                self.itemProcessed()
                return
            }

            if self.copyFile(at: url, to: newPath) {
                if let sharedFile = self.getSharedMediaFile(forVideo: newPath) {
                    self.sharedMedia.append(sharedFile)
                }
            }

            self.itemProcessed()
        }
    }

    private func handleFiles(attachment: NSItemProvider, index: Int) {
        attachment.loadItem(forTypeIdentifier: ShareUTI.fileURL, options: nil) { [weak self] data, error in
            guard let self = self, error == nil, let url = data as? URL else {
                NSLog("[MezonSharing] File load error: %@", error?.localizedDescription ?? "unknown")
                self?.itemProcessed()
                return
            }

            let newName = self.getFileName(from: url)
            guard let newPath = self.sharedContainerURL()?.appendingPathComponent(newName) else {
                self.itemProcessed()
                return
            }

            if self.copyFile(at: url, to: newPath) {
                self.sharedMedia.append(SharedMediaFile(
                    path: newPath.absoluteString,
                    thumbnail: nil,
                    duration: nil,
                    type: .file
                ))
            }

            self.itemProcessed()
        }
    }

    private func handleText(attachment: NSItemProvider, index: Int) {
        attachment.loadItem(forTypeIdentifier: ShareUTI.plainText, options: nil) { [weak self] data, error in
            guard let self = self, error == nil, let text = data as? String else {
                self?.itemProcessed()
                return
            }

            self.sharedText.append(text)
            self.itemProcessed()
        }
    }

    private func handleUrl(attachment: NSItemProvider, index: Int) {
        attachment.loadItem(forTypeIdentifier: ShareUTI.url, options: nil) { [weak self] data, error in
            guard let self = self, error == nil, let url = data as? URL else {
                self?.itemProcessed()
                return
            }

            self.sharedText.append(url.absoluteString)
            self.itemProcessed()
        }
    }

    private func itemProcessed() {
        processedItems += 1
        NSLog("[MezonSharing] Item processed: %d/%d", processedItems, pendingItems)
        if processedItems >= pendingItems {
            DispatchQueue.main.async { [weak self] in
                self?.saveAndRedirect()
            }
        }
    }

    private func saveAndRedirect() {
        NSLog("[MezonSharing] saveAndRedirect - media: %d, text: %d", sharedMedia.count, sharedText.count)

        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("[MezonSharing] ERROR: Cannot access UserDefaults for group: %@", appGroupIdentifier)
            dismissWithError(message: "Cannot access shared storage")
            return
        }

        if !sharedMedia.isEmpty {
            let encodedData = try? JSONEncoder().encode(sharedMedia)
            userDefaults.set(encodedData, forKey: sharedKey)
            userDefaults.synchronize()
            NSLog("[MezonSharing] Saved %d media items to UserDefaults", sharedMedia.count)
            redirectToHostApp(type: .media)
        } else if !sharedText.isEmpty {
            userDefaults.set(sharedText, forKey: sharedKey)
            userDefaults.synchronize()
            NSLog("[MezonSharing] Saved %d text items to UserDefaults", sharedText.count)
            redirectToHostApp(type: .text)
        } else {
            NSLog("[MezonSharing] ERROR: No content to save")
            dismissWithError(message: "No supported content found")
        }
    }

    private func redirectToHostApp(type: RedirectType) {
        guard let url = URL(string: "\(shareProtocol)://dataUrl=\(sharedKey)#\(type)") else {
            NSLog("[MezonSharing] ERROR: Cannot create URL")
            dismissWithError(message: "Failed to create redirect URL")
            return
        }

        NSLog("[MezonSharing] Redirecting to host app with URL: %@", url.absoluteString)

        openURLViaApplication(url)
    }

    private func openURLViaApplication(_ url: URL) {
        NSLog("[MezonSharing] Calling OpenURLHelper.openURL via ObjC")
        OpenURLHelper.open(url) { [weak self] success in
            NSLog("[MezonSharing] OpenURLHelper result: %d", success)
            DispatchQueue.main.async {
                self?.completeExtension()
            }
        }
    }

    private func completeExtension() {
        NSLog("[MezonSharing] completeExtension called")
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func sharedContainerURL() -> URL? {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        if url == nil {
            NSLog("[MezonSharing] ERROR: sharedContainerURL is nil for group: %@", appGroupIdentifier)
        }
        return url
    }

    private func pngData(from image: UIImage) -> Data? {
        if #available(iOSApplicationExtension 13.0, iOS 13.0, *) {
            return image.pngData()
        }
        guard let cgImage = image.cgImage else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, kUTTypePNG, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private func saveScreenshot(_ image: UIImage) -> URL? {
        guard let png = pngData(from: image), let containerURL = sharedContainerURL() else { return nil }
        let path = containerURL.appendingPathComponent("Screenshot_\(UUID().uuidString).png")
        try? png.write(to: path)
        return path
    }

    private func getExtension(from url: URL, type: SharedMediaType) -> String {
        let parts = url.lastPathComponent.components(separatedBy: ".")
        if parts.count > 1, let ext = parts.last, !ext.isEmpty {
            return ext
        }
        switch type {
        case .image: return "png"
        case .video: return "mp4"
        case .file: return "txt"
        }
    }

    private func getFileName(from url: URL) -> String {
        let name = url.lastPathComponent
        if name.isEmpty {
            return UUID().uuidString + "." + getExtension(from: url, type: .file)
        }
        return name
    }

    private func copyFile(at srcURL: URL, to dstURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) {
                try FileManager.default.removeItem(at: dstURL)
            }
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
            return true
        } catch {
            NSLog("[MezonSharing] Cannot copy item at %@ to %@: %@", srcURL.absoluteString, dstURL.absoluteString, error.localizedDescription)
            return false
        }
    }

    private func getSharedMediaFile(forVideo videoURL: URL) -> SharedMediaFile? {
        let asset = AVAsset(url: videoURL)
        let duration = CMTimeGetSeconds(asset.duration) * 1000

        let thumbnailPath = getThumbnailPath(for: videoURL)
        if FileManager.default.fileExists(atPath: thumbnailPath.path) {
            return SharedMediaFile(path: videoURL.absoluteString, thumbnail: thumbnailPath.absoluteString, duration: duration, type: .video)
        }

        let assetImgGenerate = AVAssetImageGenerator(asset: asset)
        assetImgGenerate.appliesPreferredTrackTransform = true
        assetImgGenerate.maximumSize = CGSize(width: 360, height: 360)

        do {
            let img = try assetImgGenerate.copyCGImage(at: CMTimeMakeWithSeconds(0, preferredTimescale: 1), actualTime: nil)
            let thumbData = pngData(from: UIImage(cgImage: img))
            try thumbData?.write(to: thumbnailPath)
            return SharedMediaFile(path: videoURL.absoluteString, thumbnail: thumbnailPath.absoluteString, duration: duration, type: .video)
        } catch {
            NSLog("[MezonSharing] Failed to generate video thumbnail: %@", error.localizedDescription)
            return SharedMediaFile(path: videoURL.absoluteString, thumbnail: nil, duration: duration, type: .video)
        }
    }

    private func getThumbnailPath(for url: URL) -> URL {
        let fileName = Data(url.lastPathComponent.utf8).base64EncodedString().replacingOccurrences(of: "==", with: "")
        return sharedContainerURL()!.appendingPathComponent("\(fileName).jpg")
    }

    private func dismissWithError(message: String) {
        NSLog("[MezonSharing] dismissWithError: %@", message)
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        })
        present(alert, animated: true)
    }

    enum RedirectType: CustomStringConvertible {
        case media, text, file

        var description: String {
            switch self {
            case .media: return "media"
            case .text: return "text"
            case .file: return "file"
            }
        }
    }
}

struct SharedMediaFile: Codable {
    var path: String
    var thumbnail: String?
    var duration: Double?
    var type: SharedMediaType
}

enum SharedMediaType: Int, Codable {
    case image = 0
    case video = 1
    case file = 2
}
