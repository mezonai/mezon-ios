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
        iv.layer.cornerRadius = 16
        iv.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        return iv
    }()

    private let avatarPlaceholder: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 12, weight: .semibold)
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

    private let statusLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 12, weight: .regular)
        l.textColor = UIColor.white.withAlphaComponent(0.55)
        l.numberOfLines = 2
        l.isHidden = true
        return l
    }()

    private let clanAvatarView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 7
        iv.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        iv.isHidden = true
        return iv
    }()

    private let clanNameLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 12, weight: .regular)
        l.textColor = UIColor.white.withAlphaComponent(0.55)
        l.numberOfLines = 1
        l.isHidden = true
        return l
    }()

    private let clanRowStack: UIStackView = {
        let s = UIStackView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.axis = .horizontal
        s.alignment = .center
        s.spacing = 6
        s.isHidden = true
        return s
    }()

    private let textColumnStack: UIStackView = {
        let s = UIStackView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.axis = .vertical
        s.alignment = .leading
        s.spacing = 5
        return s
    }()

    private let checkmarkView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.tintColor = UIColor(red: 0.34, green: 0.54, blue: 0.95, alpha: 1.0)
        iv.contentMode = .scaleAspectFit
        iv.isHidden = true
        return iv
    }()

    private var mainImageTask: URLSessionDataTask?
    private var clanImageTask: URLSessionDataTask?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupLayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        mainImageTask?.cancel()
        clanImageTask?.cancel()
        mainImageTask = nil
        clanImageTask = nil
        avatarView.image = nil
        clanAvatarView.image = nil
        avatarPlaceholder.text = nil
        avatarPlaceholder.isHidden = true
        channelIconView.isHidden = true
        checkmarkView.isHidden = true
        clanRowStack.isHidden = true
        clanAvatarView.isHidden = true
        clanNameLabel.isHidden = true
        clanNameLabel.text = nil
        statusLabel.isHidden = true
        statusLabel.text = nil
        contentView.alpha = 1
    }

    private func setupLayout() {
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(avatarView)
        avatarView.addSubview(avatarPlaceholder)
        avatarView.addSubview(channelIconView)
        contentView.addSubview(textColumnStack)
        textColumnStack.addArrangedSubview(nameLabel)
        textColumnStack.addArrangedSubview(statusLabel)
        textColumnStack.addArrangedSubview(clanRowStack)
        clanRowStack.addArrangedSubview(clanAvatarView)
        clanRowStack.addArrangedSubview(clanNameLabel)
        contentView.addSubview(checkmarkView)

        let avatarSize: CGFloat = 32
        clanAvatarView.widthAnchor.constraint(equalToConstant: 14).isActive = true
        clanAvatarView.heightAnchor.constraint(equalToConstant: 14).isActive = true

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarView.heightAnchor.constraint(equalToConstant: avatarSize),

            avatarPlaceholder.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarPlaceholder.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            channelIconView.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            channelIconView.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            channelIconView.widthAnchor.constraint(equalToConstant: 15),
            channelIconView.heightAnchor.constraint(equalToConstant: 15),

            textColumnStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            textColumnStack.trailingAnchor.constraint(lessThanOrEqualTo: checkmarkView.leadingAnchor, constant: -8),
            textColumnStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            checkmarkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkmarkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 22),
            checkmarkView.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    func configure(
        item: SharingSuggestionItem,
        channel: Mezon_Api_ChannelDescription?,
        isSelected: Bool,
        statusNote: String? = nil,
        isForwardingBlocked: Bool = false
    ) {
        let theme = UIColor.theme
        nameLabel.textColor = theme.textStrong
        clanNameLabel.textColor = theme.textDisabled
        if let note = statusNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            statusLabel.isHidden = false
            statusLabel.text = note
            statusLabel.textColor = theme.textDisabled
        } else {
            statusLabel.isHidden = true
            statusLabel.text = nil
        }
        contentView.alpha = isForwardingBlocked ? 0.5 : 1

        let ch = channel
        let isDM = item.type == MezonConstants.ChannelType.dm.rawValue
        let isGroup = item.type == MezonConstants.ChannelType.group.rawValue
        let isClanChannel = !isDM && !isGroup

        let displayName: String
        if let ch {
            displayName = Self.displayName(for: ch)
        } else {
            displayName = item.displayName
        }
        nameLabel.text = displayName

        let itemClan = item.clanName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chClan = ch?.clanName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayClanName: String? = {
            if !itemClan.isEmpty { return itemClan }
            if !chClan.isEmpty { return chClan }
            return nil
        }()

        if isClanChannel, let cn = displayClanName, !cn.isEmpty {
            clanRowStack.isHidden = false
            clanNameLabel.isHidden = false
            clanNameLabel.text = cn
            let logoRaw = item.clanLogo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !logoRaw.isEmpty {
                clanAvatarView.isHidden = false
                loadClanLogo(raw: logoRaw)
            } else {
                clanAvatarView.isHidden = true
                clanAvatarView.image = nil
            }
        } else {
            clanRowStack.isHidden = true
            clanAvatarView.isHidden = true
            clanNameLabel.isHidden = true
            clanAvatarView.image = nil
        }

        if isDM {
            channelIconView.isHidden = true
            let urlStr = item.avatarURL ?? ch?.avatars.first
            let username = ch?.usernames.first ?? ""
            if let s = urlStr, !s.isEmpty {
                avatarPlaceholder.isHidden = true
                avatarView.backgroundColor = UIColor.avatarColor(for: username)
                loadMainAvatar(raw: s)
            } else {
                avatarView.image = nil
                avatarView.backgroundColor = UIColor.avatarColor(for: username)
                avatarPlaceholder.isHidden = false
                avatarPlaceholder.text = String(username.prefix(1)).uppercased()
            }
        } else if isGroup {
            avatarPlaceholder.isHidden = true
            channelIconView.isHidden = false
            channelIconView.image = UIImage(systemName: "person.2.fill")?.withRenderingMode(.alwaysTemplate)
            channelIconView.tintColor = theme.iconSecondary
            let groupAv = ch?.channelAvatar ?? item.channelAvatar
            if !groupAv.isEmpty, !groupAv.contains("avatar-group.png") {
                channelIconView.isHidden = true
                avatarView.backgroundColor = Self.groupDefaultAvatarBackground
                loadMainAvatar(raw: groupAv)
            } else {
                avatarView.image = nil
                avatarView.backgroundColor = Self.groupDefaultAvatarBackground
            }
        } else {
            avatarView.image = nil
            avatarPlaceholder.isHidden = true
            channelIconView.isHidden = false
            let iconName: String
            if let ch {
                iconName = ch.channelListIconAssetName()
            } else {
                iconName = Mezon_Api_ChannelDescription.channelListIconAssetName(
                    type: item.type,
                    channelPrivate: item.channelPrivate,
                    ageRestricted: item.ageRestricted
                )
            }
            channelIconView.image = (UIImage(named: iconName) ?? UIImage(systemName: "number"))?.withRenderingMode(.alwaysTemplate)
            channelIconView.tintColor = theme.channelNormal
            avatarView.backgroundColor = theme.tertiary
        }

        checkmarkView.isHidden = isForwardingBlocked || !isSelected
    }

    private func loadMainAvatar(raw: String) {
        let proxied = SharingImageProxy.proxiedAvatarURLString(raw)
        guard !proxied.isEmpty else { return }
        if let cached = ImageCache.shared.cachedImage(forURL: proxied) {
            avatarView.image = cached
            avatarView.backgroundColor = .clear
            return
        }
        mainImageTask = ImageCache.shared.loadImage(urlString: proxied) { [weak self] image in
            self?.avatarView.image = image
            if image != nil {
                self?.avatarView.backgroundColor = .clear
            }
        }
    }

    private func loadClanLogo(raw: String) {
        let proxied = SharingImageProxy.proxiedAvatarURLString(raw)
        guard !proxied.isEmpty else { return }
        if let cached = ImageCache.shared.cachedImage(forURL: proxied) {
            clanAvatarView.image = cached
            return
        }
        clanImageTask = ImageCache.shared.loadImage(urlString: proxied) { [weak self] image in
            self?.clanAvatarView.image = image
        }
    }

    static func displayName(for channel: Mezon_Api_ChannelDescription) -> String {
        if !channel.channelLabel.isEmpty { return channel.channelLabel }
        if let first = channel.displayNames.first, !first.isEmpty { return first }
        if let first = channel.usernames.first, !first.isEmpty { return first }
        if !channel.creatorName.isEmpty { return "\(channel.creatorName)'s Group" }
        return "Chat"
    }

}
