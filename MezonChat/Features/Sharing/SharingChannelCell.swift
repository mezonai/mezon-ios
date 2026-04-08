import UIKit
import SwiftProtobuf

final class SharingChannelCell: UITableViewCell {

    static let reuseId = "SharingChannelCell"

    private let avatarView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 18
        iv.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        return iv
    }()

    private let avatarPlaceholder: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 14, weight: .semibold)
        l.textColor = .white
        l.textAlignment = .center
        return l
    }()

    private let channelIconView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = UIColor.white.withAlphaComponent(0.6)
        iv.isHidden = true
        return iv
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.textColor = .white
        l.numberOfLines = 1
        return l
    }()

    private let checkmarkView: UIImageView = {
        let iv = UIImageView(image: SharingChannelCell.selectionCheckmarkImage())
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.tintColor = UIColor(red: 0.34, green: 0.54, blue: 0.95, alpha: 1.0)
        iv.contentMode = .scaleAspectFit
        iv.isHidden = true
        return iv
    }()

    private var imageTask: URLSessionDataTask?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupLayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        avatarView.image = nil
        avatarPlaceholder.text = nil
        avatarPlaceholder.isHidden = true
        channelIconView.isHidden = true
        checkmarkView.isHidden = true
    }

    private func setupLayout() {
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(avatarView)
        avatarView.addSubview(avatarPlaceholder)
        avatarView.addSubview(channelIconView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(checkmarkView)

        let avatarSize: CGFloat = 36

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarView.heightAnchor.constraint(equalToConstant: avatarSize),

            avatarPlaceholder.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarPlaceholder.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            channelIconView.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            channelIconView.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            channelIconView.widthAnchor.constraint(equalToConstant: 18),
            channelIconView.heightAnchor.constraint(equalToConstant: 18),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkmarkView.leadingAnchor, constant: -8),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            checkmarkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkmarkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 22),
            checkmarkView.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    func configure(channel: Mezon_Api_ChannelDescription, clanName: String?, isSelected: Bool) {
        let isDM = channel.type == MezonConstants.ChannelType.dm.rawValue
        let isGroup = channel.type == MezonConstants.ChannelType.group.rawValue

        let displayName = Self.displayName(for: channel)
        nameLabel.text = displayName

        if isDM {
            channelIconView.isHidden = true
            if let avatarURL = channel.avatars.first, !avatarURL.isEmpty, let url = URL(string: avatarURL) {
                avatarPlaceholder.isHidden = true
                avatarView.backgroundColor = .clear
                loadImage(url: url)
            } else {
                avatarView.backgroundColor = colorFor(name: displayName)
                avatarPlaceholder.isHidden = false
                avatarPlaceholder.text = String(displayName.prefix(1)).uppercased()
            }
        } else if isGroup {
            avatarPlaceholder.isHidden = true
            channelIconView.isHidden = false
            channelIconView.image = SharingChannelCell.groupChannelIconImage()
            if !channel.channelAvatar.isEmpty, !channel.channelAvatar.contains("avatar-group.png"),
               let url = URL(string: channel.channelAvatar) {
                channelIconView.isHidden = true
                avatarView.backgroundColor = .clear
                loadImage(url: url)
            } else {
                avatarView.backgroundColor = UIColor.white.withAlphaComponent(0.12)
            }
        } else {
            channelIconView.isHidden = true
            avatarPlaceholder.isHidden = false
            let cName = clanName ?? displayName
            avatarPlaceholder.text = String(cName.prefix(1)).uppercased()
            avatarView.backgroundColor = colorFor(name: cName)

            nameLabel.text = displayName
        }

        checkmarkView.isHidden = !isSelected
    }

    private func loadImage(url: URL) {
        let urlString = ImgproxyURL.create(from: url.absoluteString)
        if let cached = ImageCache.shared.cachedImage(forURL: urlString) {
            avatarView.image = cached
            return
        }
        imageTask = ImageCache.shared.loadImage(urlString: urlString) { [weak self] image in
            self?.avatarView.image = image
        }
    }

    static func displayName(for channel: Mezon_Api_ChannelDescription) -> String {
        if !channel.channelLabel.isEmpty { return channel.channelLabel }
        if let first = channel.displayNames.first, !first.isEmpty { return first }
        if let first = channel.usernames.first, !first.isEmpty { return first }
        if !channel.creatorName.isEmpty { return "\(channel.creatorName)'s Group" }
        return "Chat"
    }

    private static func selectionCheckmarkImage() -> UIImage {
        if #available(iOS 13.0, *) {
            return UIImage(systemName: "checkmark.circle.fill") ?? UIImage()
        }
        let size = CGSize(width: 22, height: 22)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let circle = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 20, height: 20))
            UIColor(red: 0.34, green: 0.54, blue: 0.95, alpha: 1).setFill()
            circle.fill()
            UIColor.white.setStroke()
            let check = UIBezierPath()
            check.move(to: CGPoint(x: 6, y: 11))
            check.addLine(to: CGPoint(x: 10, y: 15))
            check.addLine(to: CGPoint(x: 16, y: 8))
            check.lineWidth = 2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()
        }
    }

    private static func groupChannelIconImage() -> UIImage {
        if #available(iOS 13.0, *) {
            return UIImage(systemName: "person.2.fill") ?? UIImage()
        }
        if let img = UIImage(named: "Channel/channel", in: Bundle.main, compatibleWith: nil) {
            return img.withRenderingMode(.alwaysTemplate)
        }
        let s = CGSize(width: 20, height: 20)
        return UIGraphicsImageRenderer(size: s).image { _ in
            UIColor.white.withAlphaComponent(0.85).setFill()
            UIBezierPath(ovalIn: CGRect(x: 2, y: 5, width: 8, height: 8)).fill()
            UIBezierPath(ovalIn: CGRect(x: 10, y: 5, width: 8, height: 8)).fill()
        }.withRenderingMode(.alwaysTemplate)
    }

    private func colorFor(name: String) -> UIColor {
        let colors: [UIColor] = [
            UIColor(red: 0.90, green: 0.30, blue: 0.35, alpha: 1),
            UIColor(red: 0.95, green: 0.55, blue: 0.20, alpha: 1),
            UIColor(red: 0.30, green: 0.75, blue: 0.45, alpha: 1),
            UIColor(red: 0.35, green: 0.55, blue: 0.90, alpha: 1),
            UIColor(red: 0.65, green: 0.40, blue: 0.85, alpha: 1),
            UIColor(red: 0.85, green: 0.35, blue: 0.60, alpha: 1),
        ]
        var hash: UInt = 5381
        for char in name.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt(char.value)
        }
        return colors[Int(hash % UInt(colors.count))]
    }
}
