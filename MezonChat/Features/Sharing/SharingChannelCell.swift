import UIKit
import SwiftProtobuf

final class SharingChannelCell: UITableViewCell {

    static let reuseId = "SharingChannelCell"

    static let groupDefaultAvatarBackground = UIColor(red: 249 / 255, green: 115 / 255, blue: 22 / 255, alpha: 1)

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
        let iv = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
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
            channelIconView.image = UIImage(systemName: "person.2.fill")?.withRenderingMode(.alwaysTemplate)
            channelIconView.tintColor = .white
            if !channel.channelAvatar.isEmpty, !channel.channelAvatar.contains("avatar-group.png"),
               let url = URL(string: channel.channelAvatar) {
                channelIconView.isHidden = true
                avatarView.backgroundColor = .clear
                loadImage(url: url)
            } else {
                avatarView.image = nil
                avatarView.backgroundColor = Self.groupDefaultAvatarBackground
            }
        } else {
            imageTask?.cancel()
            avatarView.image = nil
            avatarPlaceholder.isHidden = true
            channelIconView.isHidden = false
            let iconName = channel.channelListIconAssetName()
            channelIconView.image = (UIImage(named: iconName) ?? UIImage(systemName: "number"))?.withRenderingMode(.alwaysTemplate)
            channelIconView.tintColor = UIColor.theme.channelNormal
            avatarView.backgroundColor = UIColor.white.withAlphaComponent(0.12)
            nameLabel.text = displayName
        }

        checkmarkView.isHidden = !isSelected
    }

    private func loadImage(url: URL) {
        let urlString = ImgproxyURL.create(from: url.absoluteString, width: 150, height: 150)
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
