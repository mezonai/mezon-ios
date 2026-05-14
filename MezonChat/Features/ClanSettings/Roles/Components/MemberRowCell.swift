import UIKit

@MainActor
final class MemberRowCell: UITableViewCell {

    static let reuseId = "MemberRowCell"

    enum Accessory {
        case none
        case removeButton
        case checkbox(checked: Bool)
    }

    private let avatarView = UIImageView()
    private let avatarInitials = UILabel()
    private let nameLabel = UILabel()
    private let subLabel = UILabel()
    private let accessoryButton = UIButton(type: .system)
    private let checkboxView = UIImageView()
    private var imageTask: URLSessionDataTask?

    var onAccessoryTapped: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
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

        nameLabel.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        nameLabel.textColor = .mezonTextPrimary
        nameLabel.numberOfLines = 1

        subLabel.font = .systemFont(ofSize: 12.sf, weight: .regular)
        subLabel.textColor = UIColor.theme.textDisabled
        subLabel.numberOfLines = 1

        accessoryButton.tintColor = UIColor.theme.textDisabled
        accessoryButton.addTarget(self, action: #selector(accessoryTapped), for: .touchUpInside)
        accessoryButton.isHidden = true

        checkboxView.contentMode = .scaleAspectFit
        checkboxView.tintColor = UIColor.theme.bgViolet
        checkboxView.isHidden = true

        [avatarView, avatarInitials, nameLabel, subLabel, accessoryButton, checkboxView].forEach {
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

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12.sw),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10.sh),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: accessoryButton.leadingAnchor, constant: -8.sw),

            subLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            subLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2.sh),
            subLabel.trailingAnchor.constraint(lessThanOrEqualTo: accessoryButton.leadingAnchor, constant: -8.sw),
            subLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10.sh),

            accessoryButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12.sw),
            accessoryButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            accessoryButton.widthAnchor.constraint(equalToConstant: 28.swh),
            accessoryButton.heightAnchor.constraint(equalToConstant: 28.swh),

            checkboxView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16.sw),
            checkboxView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkboxView.widthAnchor.constraint(equalToConstant: 22.swh),
            checkboxView.heightAnchor.constraint(equalToConstant: 22.swh)
        ])
    }

    func configure(
        name: String,
        subtitle: String?,
        avatarURL: String?,
        accessory: Accessory
    ) {
        nameLabel.text = name
        subLabel.text = subtitle
        subLabel.isHidden = subtitle?.isEmpty ?? true
        avatarInitials.text = RoleMemberDisplay.initials(name)

        imageTask?.cancel()
        avatarView.image = nil
        avatarInitials.isHidden = false
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

        switch accessory {
        case .none:
            accessoryButton.isHidden = true
            checkboxView.isHidden = true
        case .removeButton:
            accessoryButton.isHidden = false
            accessoryButton.setImage(
                UIImage(systemName: "minus.circle.fill")?.withRenderingMode(.alwaysTemplate),
                for: .normal)
            accessoryButton.tintColor = UIColor.systemRed
            checkboxView.isHidden = true
        case .checkbox(let checked):
            accessoryButton.isHidden = true
            checkboxView.isHidden = false
            let symbol = checked ? "checkmark.circle.fill" : "circle"
            checkboxView.image = UIImage(systemName: symbol)?.withRenderingMode(.alwaysTemplate)
            checkboxView.tintColor = checked ? UIColor.theme.bgViolet : UIColor.theme.textDisabled
        }
    }

    @objc private func accessoryTapped() {
        onAccessoryTapped?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        avatarView.image = nil
        avatarInitials.isHidden = false
        onAccessoryTapped = nil
    }
}
