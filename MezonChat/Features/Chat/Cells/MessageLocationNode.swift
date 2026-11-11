import AsyncDisplayKit
import MapKit
import UIKit

struct LocationData {
    let latitude: Double
    let longitude: Double
    let googleMapsURL: String
    let avatarURL: String?
    let senderName: String
    let isMe: Bool

    static let coordinateRegex = try! NSRegularExpression(pattern: #"q=(-?\d+\.?\d*),(-?\d+\.?\d*)"#)

    static func parse(from content: Data, code: Int32, avatarURL: String?, senderName: String, isMe: Bool) -> LocationData? {
        guard code == 17 else { return nil }
        guard !content.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: content) as? [String: Any],
              let text = json["t"] as? String, !text.isEmpty else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = coordinateRegex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 3,
              let latRange = Range(match.range(at: 1), in: text),
              let lonRange = Range(match.range(at: 2), in: text),
              let lat = Double(text[latRange]),
              let lon = Double(text[lonRange]) else { return nil }
        return LocationData(
            latitude: lat, longitude: lon,
            googleMapsURL: text, avatarURL: avatarURL,
            senderName: senderName, isMe: isMe
        )
    }
}

private final class LocationSnapshotStore {
    static let shared = LocationSnapshotStore()

    private let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    private var runningSnapshotters: [String: MKMapSnapshotter] = [:]
    private var waiters: [String: [(UIImage) -> Void]] = [:]

    func cachedImage(forKey key: String) -> UIImage? {
        images.object(forKey: key as NSString)
    }

    func snapshot(key: String, options: MKMapSnapshotter.Options, completion: @escaping (UIImage) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.snapshot(key: key, options: options, completion: completion) }
            return
        }
        if let image = cachedImage(forKey: key) {
            completion(image)
            return
        }
        waiters[key, default: []].append(completion)
        guard runningSnapshotters[key] == nil else { return }

        let snapshotter = MKMapSnapshotter(options: options)
        runningSnapshotters[key] = snapshotter
        snapshotter.start { snapshot, error in
            let finished = self.runningSnapshotters.removeValue(forKey: key)
            let callbacks = self.waiters.removeValue(forKey: key) ?? []
            if let image = snapshot?.image, error == nil {
                self.images.setObject(image, forKey: key as NSString, cost: Self.byteCost(of: image))
                callbacks.forEach { $0(image) }
            }
            DispatchQueue.main.async { withExtendedLifetime(finished) {} }
        }
    }

    private static func byteCost(of image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }
}

final class MessageLocationNode: ASDisplayNode {

    private let containerNode = ASDisplayNode()
    private let mapImageNode = ASImageNode()
    private let avatarContainerNode = ASDisplayNode()
    private let avatarImageNode = TransformImageNode()
    private let infoBarNode = ASDisplayNode()
    private let titleNode = ASTextNode2()

    private var cachedTotalSize: CGSize = .zero
    private var locationData: LocationData?

    private static let mapHeight: CGFloat = 150
    private static let avatarSize: CGFloat = 30
    private static let infoBarHeight: CGFloat = 40
    private static let cornerRadius: CGFloat = 10

    var onTapped: (() -> Void)?

    func configure(locationData: LocationData) {
        self.locationData = locationData
        let t = UIColor.theme

        containerNode.backgroundColor = t.secondaryLight
        containerNode.cornerRadius = Self.cornerRadius
        containerNode.clipsToBounds = true
        containerNode.borderWidth = 1
        containerNode.borderColor = t.border.cgColor

        mapImageNode.contentMode = .scaleAspectFill
        mapImageNode.backgroundColor = t.border

        avatarContainerNode.backgroundColor = t.secondaryWeight
        avatarContainerNode.cornerRadius = Self.avatarSize / 2
        avatarContainerNode.clipsToBounds = true
        avatarContainerNode.borderWidth = 2
        avatarContainerNode.borderColor = UIColor.white.cgColor

        infoBarNode.backgroundColor = t.secondaryLight

        let titleText = locationData.isMe
            ? L(L10n.ChannelMessages.yourLocation)
            : String(format: L(L10n.ChannelMessages.locationOf), locationData.senderName)
        titleNode.attributedText = NSAttributedString(
            string: titleText,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .bold),
                .foregroundColor: t.textStrong,
            ]
        )
        titleNode.maximumNumberOfLines = 1

        addSubnode(containerNode)
        containerNode.addSubnode(mapImageNode)
        containerNode.addSubnode(avatarContainerNode)
        avatarContainerNode.addSubnode(avatarImageNode)
        containerNode.addSubnode(infoBarNode)
        infoBarNode.addSubnode(titleNode)

        loadAvatar(urlString: locationData.avatarURL)
        loadMapSnapshot(latitude: locationData.latitude, longitude: locationData.longitude)
    }

    override func didLoad() {
        super.didLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        containerNode.view.addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        guard let urlString = locationData?.googleMapsURL,
              let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    private func loadAvatar(urlString: String?) {
        let size = Self.avatarSize
        let args = TransformImageArguments(
            corners: ImageCorners(radius: size / 2),
            imageSize: CGSize(width: size, height: size),
            boundingSize: CGSize(width: size, height: size),
            intrinsicInsets: .zero
        )
        let defaultAvatar = DefaultUserAvatar.image(side: size)
        if let urlString, !urlString.isEmpty {
            avatarContainerNode.backgroundColor = .clear
            let proxyURL = ImgproxyURL.iconURL(from: urlString, width: 100, height: 100)
            let hasMem = ImageCache.shared.memoryImage(forKey: proxyURL) != nil
                || ImageCache.shared.memoryImage(forKey: urlString) != nil
            avatarImageNode.setSignal(
                remoteAvatarSignal(proxiedURL: proxyURL, originalURL: urlString, fallbackImage: defaultAvatar),
                attemptSynchronously: hasMem
            )
        } else {
            avatarImageNode.setSignal(staticImageSignal(image: defaultAvatar), attemptSynchronously: true)
        }
        let avatarLayout = avatarImageNode.asyncLayout()
        let apply = avatarLayout(args)
        apply()
    }

    private func loadMapSnapshot(latitude: Double, longitude: Double) {
        let key = "\(latitude),\(longitude)"
        if let image = LocationSnapshotStore.shared.cachedImage(forKey: key) {
            mapImageNode.image = image
            return
        }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 320 * UIScreen.main.scale, height: Self.mapHeight * UIScreen.main.scale)
        options.traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: .dark),
            UITraitCollection(displayScale: 1),
        ])

        LocationSnapshotStore.shared.snapshot(key: key, options: options) { [weak self] image in
            self?.mapImageNode.image = image
            self?.setNeedsLayout()
        }
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let totalH = Self.mapHeight + Self.infoBarHeight
        let totalW = maxWidth
        let titleConstraint = CGSize(width: totalW - 20, height: Self.infoBarHeight)
        _ = titleNode.measure(titleConstraint)
        cachedTotalSize = CGSize(width: totalW, height: totalH)
        return cachedTotalSize
    }

    override func layout() {
        super.layout()
        let w = cachedTotalSize.width
        containerNode.frame = CGRect(origin: .zero, size: cachedTotalSize)

        mapImageNode.frame = CGRect(x: 0, y: 0, width: w, height: Self.mapHeight)

        let avatarSz = Self.avatarSize
        let avatarX = (w - avatarSz) / 2
        let avatarY = (Self.mapHeight - avatarSz) / 2
        avatarContainerNode.frame = CGRect(x: avatarX, y: avatarY, width: avatarSz, height: avatarSz)
        avatarImageNode.frame = CGRect(origin: .zero, size: CGSize(width: avatarSz, height: avatarSz))

        let infoY = Self.mapHeight
        infoBarNode.frame = CGRect(x: 0, y: infoY, width: w, height: Self.infoBarHeight)

        let titleSize = titleNode.calculatedSize
        titleNode.frame = CGRect(
            x: 10,
            y: (Self.infoBarHeight - titleSize.height) / 2,
            width: min(titleSize.width, w - 20),
            height: titleSize.height
        )
    }
}
