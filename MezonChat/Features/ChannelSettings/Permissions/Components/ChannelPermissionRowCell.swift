import UIKit

@MainActor
final class ChannelPermissionRowCell: UITableViewCell {

    static let reuseId = "ChannelPermissionRowCell"

    enum Trailing {
        case none
        case chevron
        case removeButton(enabled: Bool)
        case checkbox(checked: Bool)
    }

    private let avatarView = UIImageView()
    private let avatarInitials = UILabel()
    private let roleIconView = UIImageView()
    private let nameLabel = UILabel()
    private let subLabel = UILabel()
    private let ownerIcon = UIImageView()
    private let trailingButton = UIButton(type: .system)
    private let checkboxView = UIImageView()
    private let chevron = UIImageView()
    private var imageTask: URLSessionDataTask?
    private var configuredAvatarURL: String?

    var onRemoveTapped: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        backgroundColor = UIColor.theme.tertiary
        let bg = UIView()
        bg.backgroundColor = UIColor.theme.tertiary.withAlphaComponent(0.6)
        selectedBackgroundView = bg
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        avatarView.layer.cornerRadius = 18.swh
        avatarView.clipsToBounds = true
        avatarView.contentMode = .scaleAspectFill
        avatarView.backgroundColor = UIColor.theme.tertiary

        avatarInitials.font = .systemFont(ofSize: 13.sf, weight: .bold)
        avatarInitials.textColor = .white
        avatarInitials.textAlignment = .center

        roleIconView.contentMode = .scaleAspectFit
        roleIconView.image = UIImage(systemName: "shield.lefthalf.filled")?.withRenderingMode(.alwaysTemplate)
        roleIconView.isHidden = true

        nameLabel.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        nameLabel.textColor = .mezonTextPrimary
        nameLabel.numberOfLines = 1

        subLabel.font = .systemFont(ofSize: 12.sf, weight: .regular)
        subLabel.textColor = UIColor.theme.textDisabled
        subLabel.numberOfLines = 1

        ownerIcon.image = UIImage(systemName: "crown.fill")?.withRenderingMode(.alwaysTemplate)
        ownerIcon.tintColor = UIColor.systemYellow
        ownerIcon.contentMode = .scaleAspectFit
        ownerIcon.isHidden = true

        trailingButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
        trailingButton.isHidden = true

        checkboxView.contentMode = .scaleAspectFit
        checkboxView.isHidden = true

        chevron.image = UIImage(systemName: "chevron.right")?.withRenderingMode(.alwaysTemplate)
        chevron.tintColor = UIColor.theme.textDisabled
        chevron.contentMode = .scaleAspectFit
        chevron.isHidden = true

        [avatarView, avatarInitials, roleIconView, nameLabel, subLabel, ownerIcon, trailingButton, checkboxView, chevron].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14.sw),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 36.swh),
            avatarView.heightAnchor.constraint(equalToConstant: 36.swh),

            avatarInitials.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarInitials.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            roleIconView.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            roleIconView.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            roleIconView.widthAnchor.constraint(equalToConstant: 24.swh),
            roleIconView.heightAnchor.constraint(equalToConstant: 24.swh),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12.sw),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10.sh),

            ownerIcon.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6.sw),
            ownerIcon.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            ownerIcon.widthAnchor.constraint(equalToConstant: 14.swh),
            ownerIcon.heightAnchor.constraint(equalToConstant: 14.swh),

            subLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            subLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2.sh),
            subLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10.sh),

            trailingButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14.sw),
            trailingButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            trailingButton.widthAnchor.constraint(equalToConstant: 28.swh),
            trailingButton.heightAnchor.constraint(equalToConstant: 28.swh),

            checkboxView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16.sw),
            checkboxView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkboxView.widthAnchor.constraint(equalToConstant: 22.swh),
            checkboxView.heightAnchor.constraint(equalToConstant: 22.swh),

            chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14.sw),
            chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12.swh),
            chevron.heightAnchor.constraint(equalToConstant: 18.swh),

            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingButton.leadingAnchor, constant: -8.sw),
            subLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingButton.leadingAnchor, constant: -8.sw),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60.sh)
        ])
    }

    func configureMember(
        name: String,
        subtitle: String?,
        avatarURL: String?,
        isOwner: Bool,
        trailing: Trailing
    ) {
        nameLabel.text = name
        subLabel.text = subtitle
        subLabel.isHidden = subtitle?.isEmpty ?? true
        avatarInitials.text = RoleMemberDisplay.initials(name)
        ownerIcon.isHidden = !isOwner

        roleIconView.isHidden = true
        avatarView.isHidden = false
        avatarInitials.isHidden = false

        imageTask?.cancel()
        imageTask = nil
        configuredAvatarURL = nil
        avatarView.image = nil
        avatarView.backgroundColor = UIColor.theme.tertiary
        if let urlString = avatarURL, !urlString.isEmpty {
            let resolved = ImgproxyURL.create(from: urlString, width: 100, height: 100)
            configuredAvatarURL = resolved
            imageTask = ImageCache.shared.loadImage(urlString: resolved) { [weak self] image in
                guard let self else { return }
                DispatchQueue.main.async {
                    guard self.configuredAvatarURL == resolved else { return }
                    if let image {
                        self.avatarView.image = image
                        self.avatarInitials.isHidden = true
                    }
                }
            }
        }

        applyTrailing(trailing)
    }

    func configureRole(
        title: String,
        color: UIColor,
        trailing: Trailing
    ) {
        nameLabel.text = title
        subLabel.text = L(L10n.ChannelPermission.role)
        subLabel.isHidden = false
        imageTask?.cancel()
        imageTask = nil
        configuredAvatarURL = nil
        avatarInitials.isHidden = true
        ownerIcon.isHidden = true

        avatarView.image = nil
        avatarView.backgroundColor = color.withAlphaComponent(0.18)
        roleIconView.isHidden = false
        roleIconView.tintColor = color

        applyTrailing(trailing)
    }

    func setTrailing(_ trailing: Trailing) {
        applyTrailing(trailing)
    }

    private func applyTrailing(_ trailing: Trailing) {
        trailingButton.isHidden = true
        checkboxView.isHidden = true
        chevron.isHidden = true
        switch trailing {
        case .none:
            break
        case .chevron:
            chevron.isHidden = false
        case .removeButton(let enabled):
            trailingButton.isHidden = false
            trailingButton.setImage(
                UIImage(systemName: "xmark.circle.fill")?.withRenderingMode(.alwaysTemplate),
                for: .normal
            )
            trailingButton.tintColor = enabled ? UIColor.theme.text : UIColor.theme.textDisabled
            trailingButton.isEnabled = enabled
        case .checkbox(let checked):
            checkboxView.isHidden = false
            let symbol = checked ? "checkmark.circle.fill" : "circle"
            checkboxView.image = UIImage(systemName: symbol)?.withRenderingMode(.alwaysTemplate)
            checkboxView.tintColor = checked ? UIColor.theme.bgViolet : UIColor.theme.textDisabled
        }
    }

    @objc private func removeTapped() {
        onRemoveTapped?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        configuredAvatarURL = nil
        avatarView.image = nil
        avatarView.isHidden = false
        avatarView.backgroundColor = UIColor.theme.tertiary
        avatarInitials.isHidden = false
        roleIconView.isHidden = true
        ownerIcon.isHidden = true
        trailingButton.isHidden = true
        trailingButton.isEnabled = true
        trailingButton.setImage(nil, for: .normal)
        checkboxView.isHidden = true
        checkboxView.image = nil
        chevron.isHidden = true
        onRemoveTapped = nil
    }
}
