import UIKit
import MobileCoreServices
import AVFoundation

class ShareViewController: UIViewController {

    private let shareProtocol = "mezon.mobile.sharing"
    private let sharedKey = "mezon.mobile.sharing"
    private let appGroupIdentifier = "group.mezon.mobile"

    private var sharedMedia: [SharedMediaFile] = []
    private var sharedText: [String] = []
    private var pendingItems = 0
    private var processedItems = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        processInputItems()
    }

    private func processInputItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            dismissWithError(message: "No content to share")
            return
        }

        guard let extensionItem = extensionItems.first,
              let attachments = extensionItem.attachments, !attachments.isEmpty else {
            dismissWithError(message: "No content to share")
            return
        }

        pendingItems = attachments.count
        processedItems = 0

        for (index, attachment) in attachments.enumerated() {
            if attachment.hasItemConformingToTypeIdentifier(kUTTypeImage as String) {
                handleImages(attachment: attachment, index: index)
            } else if attachment.hasItemConformingToTypeIdentifier(kUTTypeMovie as String) {
                handleVideos(attachment: attachment, index: index)
            } else if attachment.hasItemConformingToTypeIdentifier(kUTTypeFileURL as String)
                || attachment.hasItemConformingToTypeIdentifier("public.file-url")
                || attachment.hasItemConformingToTypeIdentifier("public.pdf")
                || attachment.hasItemConformingToTypeIdentifier("com.adobe.pdf") {
                handleFiles(attachment: attachment, index: index)
            } else if attachment.hasItemConformingToTypeIdentifier(kUTTypeURL as String) {
                handleUrl(attachment: attachment, index: index)
            } else if attachment.hasItemConformingToTypeIdentifier(kUTTypeText as String) {
                handleText(attachment: attachment, index: index)
            } else {
                itemProcessed()
            }
        }
    }

    private func handleImages(attachment: NSItemProvider, index: Int) {
        attachment.loadItem(forTypeIdentifier: kUTTypeImage as String, options: nil) { [weak self] data, error in
            guard let self = self else { return }

            if error != nil {
                self.itemProcessed()
                return
            }

            var url: URL?
            if let dataURL = data as? URL {
                url = dataURL
            } else if let image = data as? UIImage {
                url = self.saveScreenshot(image)
            } else if let imageData = data as? Data, let image = UIImage(data: imageData) {
                url = self.saveScreenshot(image)
            } else {
                attachment.loadDataRepresentation(forTypeIdentifier: kUTTypeImage as String) { rawData, rawError in
                    if let rawData = rawData, let image = UIImage(data: rawData) {
                        let savedURL = self.saveScreenshot(image)
                        if let savedURL = savedURL {
                            self.sharedMedia.append(SharedMediaFile(
                                path: savedURL.absoluteString,
                                thumbnail: nil,
                                duration: nil,
                                type: .image
                            ))
                        }
                    }
                    self.itemProcessed()
                }
                return
            }

            guard let sourceURL = url else {
                self.itemProcessed()
                return
            }

            let fileExtension = self.getExtension(from: sourceURL, type: .image)
            let newName = UUID().uuidString
            guard let newPath = self.sharedContainerURL()?.appendingPathComponent("\(newName).\(fileExtension)") else {
                self.itemProcessed()
                return
            }

            if self.copyFile(at: sourceURL, to: newPath) {
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
        attachment.loadItem(forTypeIdentifier: kUTTypeMovie as String, options: nil) { [weak self] data, error in
            guard let self = self, error == nil, let url = data as? URL else {
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
        let typeId = fileTypeIdentifier(for: attachment)
        attachment.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] data, error in
            guard let self = self, error == nil else {
                self?.itemProcessed()
                return
            }

            if let url = data as? URL {
                self.ingestFileURL(url)
                self.itemProcessed()
                return
            }

            if let fileData = data as? Data {
                let ext = typeId.contains("pdf") ? "pdf" : "bin"
                let newName = UUID().uuidString + ".\(ext)"
                guard let newPath = self.sharedContainerURL()?.appendingPathComponent(newName) else {
                    self.itemProcessed()
                    return
                }
                do {
                    try fileData.write(to: newPath)
                    self.sharedMedia.append(SharedMediaFile(
                        path: newPath.absoluteString,
                        thumbnail: nil,
                        duration: nil,
                        type: .file
                    ))
                } catch {
                }
                self.itemProcessed()
                return
            }

            self.itemProcessed()
        }
    }

    private func fileTypeIdentifier(for attachment: NSItemProvider) -> String {
        if attachment.hasItemConformingToTypeIdentifier(kUTTypeFileURL as String) {
            return kUTTypeFileURL as String
        }
        if attachment.hasItemConformingToTypeIdentifier("public.file-url") {
            return "public.file-url"
        }
        if attachment.hasItemConformingToTypeIdentifier("public.pdf") {
            return "public.pdf"
        }
        if attachment.hasItemConformingToTypeIdentifier("com.adobe.pdf") {
            return "com.adobe.pdf"
        }
        return kUTTypeFileURL as String
    }

    private func ingestFileURL(_ url: URL) {
        let newName = getFileName(from: url)
        guard let newPath = sharedContainerURL()?.appendingPathComponent(newName) else { return }
        if copyFile(at: url, to: newPath) {
            sharedMedia.append(SharedMediaFile(
                path: newPath.absoluteString,
                thumbnail: nil,
                duration: nil,
                type: .file
            ))
        }
    }

    private func handleText(attachment: NSItemProvider, index: Int) {
        attachment.loadItem(forTypeIdentifier: kUTTypeText as String, options: nil) { [weak self] data, error in
            guard let self = self, error == nil, let text = data as? String else {
                self?.itemProcessed()
                return
            }

            self.sharedText.append(text)
            self.itemProcessed()
        }
    }

    private func handleUrl(attachment: NSItemProvider, index: Int) {
        attachment.loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil) { [weak self] data, error in
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
        if processedItems >= pendingItems {
            DispatchQueue.main.async { [weak self] in
                self?.saveAndRedirect()
            }
        }
    }

    private func saveAndRedirect() {

        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            dismissWithError(message: "Cannot access shared storage")
            return
        }

        if !sharedMedia.isEmpty {
            let encodedData = try? JSONEncoder().encode(sharedMedia)
            userDefaults.set(encodedData, forKey: sharedKey)
            userDefaults.synchronize()
            redirectToHostApp(type: .media)
        } else if !sharedText.isEmpty {
            userDefaults.set(sharedText, forKey: sharedKey)
            userDefaults.synchronize()
            redirectToHostApp(type: .text)
        } else {
            dismissWithError(message: "No supported content found")
        }
    }

    private func redirectToHostApp(type: RedirectType) {
        guard let url = URL(string: "\(shareProtocol)://dataUrl=\(sharedKey)#\(type)") else {
            dismissWithError(message: "Failed to create redirect URL")
            return
        }

        openURLViaApplication(url)
    }

    private func openURLViaApplication(_ url: URL) {
        OpenURLHelper.open(url) { [weak self] _ in
            DispatchQueue.main.async {
                self?.completeExtension()
            }
        }
    }

    private func completeExtension() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func sharedContainerURL() -> URL? {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        return url
    }

    private func saveScreenshot(_ image: UIImage) -> URL? {
        guard let data = image.pngData(),
              let containerURL = sharedContainerURL() else { return nil }
        let path = containerURL.appendingPathComponent("Screenshot_\(UUID().uuidString).png")
        try? data.write(to: path)
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
        let accessed = srcURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                srcURL.stopAccessingSecurityScopedResource()
            }
        }
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) {
                try FileManager.default.removeItem(at: dstURL)
            }
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
            return true
        } catch {
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
            try UIImage(cgImage: img).pngData()?.write(to: thumbnailPath)
            return SharedMediaFile(path: videoURL.absoluteString, thumbnail: thumbnailPath.absoluteString, duration: duration, type: .video)
        } catch {
            return SharedMediaFile(path: videoURL.absoluteString, thumbnail: nil, duration: duration, type: .video)
        }
    }

    private func getThumbnailPath(for url: URL) -> URL {
        let fileName = Data(url.lastPathComponent.utf8).base64EncodedString().replacingOccurrences(of: "==", with: "")
        return sharedContainerURL()!.appendingPathComponent("\(fileName).jpg")
    }

    private func dismissWithError(message: String) {
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
