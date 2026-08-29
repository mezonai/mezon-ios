import UIKit

final class ChannelPermissionsRowView: UIView {

    enum Kind {
        case role(title: String, color: UIColor)
        case member(name: String, username: String, avatarURL: String?, isOwner: Bool)
    }

    enum Trailing {
        case none
        case chevron
        case removeButton(enabled: Bool)
    }

    private let kind: Kind
    private let trailing: Trailing
    private let onTrailing: (() -> Void)?
    private let onTap: (() -> Void)?

    private let avatarView = UIImageView()
    private let avatarInitials = UILabel()
    private let roleIconView = UIImageView()
    private let nameLabel = UILabel()
    private let subLabel = UILabel()
    private let ownerIcon = UIImageView()
    private let trailingButton = UIButton(type: .system)
    private let chevron = UIImageView()
    private var imageTask: URLSessionDataTask?

    init(
        kind: Kind,
        trailing: Trailing,
        onTrailing: (() -> Void)?,
        onTap: (() -> Void)?
    ) {
        self.kind = kind
        self.trailing = trailing
        self.onTrailing = onTrailing
        self.onTap = onTap
        super.init(frame: .zero)
        backgroundColor = .clear
        setup()
        configure()
        if onTap != nil {
            let g = UITapGestureRecognizer(target: self, action: #selector(rowTapped))
            addGestureRecognizer(g)
            isUserInteractionEnabled = true
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        avatarView.layer.cornerRadius = 18.swh
        avatarView.clipsToBounds = true
        avatarView.contentMode = .scaleAspectFill

        avatarInitials.font = .systemFont(ofSize: 13.sf, weight: .bold)
        avatarInitials.textColor = .white
        avatarInitials.textAlignment = .center

        roleIconView.contentMode = .scaleAspectFit
        roleIconView.image = UIImage.mezonSystemImage("shield.lefthalf.filled")?.withRenderingMode(.alwaysTemplate)
        roleIconView.isHidden = true

        nameLabel.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        nameLabel.textColor = .mezonTextPrimary
        nameLabel.numberOfLines = 1

        subLabel.font = .systemFont(ofSize: 12.sf, weight: .regular)
        subLabel.textColor = UIColor.theme.textDisabled
        subLabel.numberOfLines = 1

        ownerIcon.image = UIImage.mezonSystemImage("crown.fill")?.withRenderingMode(.alwaysTemplate)
        ownerIcon.tintColor = UIColor.systemYellow
        ownerIcon.contentMode = .scaleAspectFit
        ownerIcon.isHidden = true

        trailingButton.addTarget(self, action: #selector(trailingTapped), for: .touchUpInside)
        trailingButton.isHidden = true

        chevron.image = UIImage.mezonSystemImage("chevron.right")?.withRenderingMode(.alwaysTemplate)
        chevron.tintColor = UIColor.theme.textDisabled
        chevron.contentMode = .scaleAspectFit
        chevron.isHidden = true

        [avatarView, avatarInitials, roleIconView, nameLabel, subLabel, ownerIcon, trailingButton, chevron].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 60.sh),

            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14.sw),
            avatarView.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 36.swh),
            avatarView.heightAnchor.constraint(equalToConstant: 36.swh),

            avatarInitials.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarInitials.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            roleIconView.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            roleIconView.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            roleIconView.widthAnchor.constraint(equalToConstant: 24.swh),
            roleIconView.heightAnchor.constraint(equalToConstant: 24.swh),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12.sw),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10.sh),

            ownerIcon.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6.sw),
            ownerIcon.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            ownerIcon.widthAnchor.constraint(equalToConstant: 14.swh),
            ownerIcon.heightAnchor.constraint(equalToConstant: 14.swh),

            subLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            subLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2.sh),
            subLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10.sh),

            trailingButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14.sw),
            trailingButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingButton.widthAnchor.constraint(equalToConstant: 28.swh),
            trailingButton.heightAnchor.constraint(equalToConstant: 28.swh),

            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14.sw),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12.swh),
            chevron.heightAnchor.constraint(equalToConstant: 18.swh),

            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingButton.leadingAnchor, constant: -8.sw),
            subLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingButton.leadingAnchor, constant: -8.sw)
        ])
    }

    private func configure() {
        switch kind {
        case .role(let title, let color):
            nameLabel.text = title
            subLabel.text = L(L10n.ChannelPermission.role)
            subLabel.isHidden = false
            avatarInitials.isHidden = true
            ownerIcon.isHidden = true
            avatarView.image = nil
            avatarView.backgroundColor = color.withAlphaComponent(0.18)
            roleIconView.isHidden = false
            roleIconView.tintColor = color

        case .member(let name, let username, let avatarURL, let isOwner):
            nameLabel.text = name
            subLabel.text = username
            subLabel.isHidden = username.isEmpty
            avatarInitials.text = RoleMemberDisplay.initials(name)
            avatarInitials.isHidden = false
            ownerIcon.isHidden = !isOwner
            roleIconView.isHidden = true
            avatarView.backgroundColor = UIColor.theme.secondary
            avatarView.image = nil
            if let urlString = avatarURL, !urlString.isEmpty {
                let resolved = ImgproxyURL.create(from: urlString, width: 100, height: 100)
                imageTask = ImageCache.shared.loadImage(urlString: resolved) { [weak self] image in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        if let image {
                            self.avatarView.image = image
                            self.avatarInitials.isHidden = true
                        }
                    }
                }
            }
        }

        switch trailing {
        case .none:
            trailingButton.isHidden = true
            chevron.isHidden = true
        case .chevron:
            trailingButton.isHidden = true
            chevron.isHidden = false
        case .removeButton(let enabled):
            trailingButton.isHidden = false
            trailingButton.setImage(
                UIImage.mezonSystemImage("xmark.circle.fill")?.withRenderingMode(.alwaysTemplate),
                for: .normal
            )
            trailingButton.tintColor = enabled ? UIColor.theme.text : UIColor.theme.textDisabled
            trailingButton.isEnabled = enabled
            chevron.isHidden = true
        }
    }

    @objc private func trailingTapped() { onTrailing?() }

    @objc private func rowTapped() { onTap?() }

    deinit { imageTask?.cancel() }
}
