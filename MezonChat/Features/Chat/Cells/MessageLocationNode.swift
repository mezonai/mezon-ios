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

final class MessageLocationNode: ASDisplayNode {

    private let containerNode = ASDisplayNode()
    private let mapImageNode = ASImageNode()
    private let avatarContainerNode = ASDisplayNode()
    private let avatarImageNode = TransformImageNode()
    private let avatarPlaceholderNode = ASTextNode2()
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

        avatarContainerNode.backgroundColor = .colorAvatarDefault
        avatarContainerNode.cornerRadius = Self.avatarSize / 2
        avatarContainerNode.clipsToBounds = true
        avatarContainerNode.borderWidth = 2
        avatarContainerNode.borderColor = UIColor.white.cgColor

        avatarPlaceholderNode.attributedText = NSAttributedString(
            string: String(locationData.senderName.prefix(1)).uppercased(),
            attributes: [
                .font: UIFont.systemFont(ofSize: 11.sf, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
        )

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
        avatarContainerNode.addSubnode(avatarPlaceholderNode)
        avatarContainerNode.addSubnode(avatarImageNode)
        containerNode.addSubnode(infoBarNode)
        infoBarNode.addSubnode(titleNode)

        loadAvatar(urlString: locationData.avatarURL, name: locationData.senderName)
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

    private func loadAvatar(urlString: String?, name: String) {
        if let urlString, !urlString.isEmpty {
            avatarPlaceholderNode.isHidden = true
            let size = Self.avatarSize
            let args = TransformImageArguments(
                corners: ImageCorners(radius: size / 2),
                imageSize: CGSize(width: size, height: size),
                boundingSize: CGSize(width: size, height: size),
                intrinsicInsets: .zero
            )
            let proxyURL = ImgproxyURL.create(from: urlString, width: 150, height: 150)
            let hasMem = ImageCache.shared.memoryImage(forKey: proxyURL) != nil
            avatarImageNode.setSignal(remoteAvatarSignal(url: proxyURL), attemptSynchronously: hasMem)
            let avatarLayout = avatarImageNode.asyncLayout()
            let apply = avatarLayout(args)
            apply()
        } else {
            avatarPlaceholderNode.isHidden = false
        }
    }

    private func loadMapSnapshot(latitude: Double, longitude: Double) {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 320 * UIScreen.main.scale, height: Self.mapHeight * UIScreen.main.scale)
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { [weak self] snapshot, error in
            guard let snapshot, error == nil else { return }
            DispatchQueue.main.async {
                self?.mapImageNode.image = snapshot.image
                self?.setNeedsLayout()
            }
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
        let phSize = avatarPlaceholderNode.measure(CGSize(width: avatarSz, height: avatarSz))
        avatarPlaceholderNode.frame = CGRect(
            x: (avatarSz - phSize.width) / 2,
            y: (avatarSz - phSize.height) / 2,
            width: phSize.width, height: phSize.height
        )

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
