import UIKit

final class StickerItemCell: UITableViewCell {

    static let reuseId = "StickerItemCell"

    private static let horizontalInset: CGFloat = 16
    private static let nameMaxWidthRatio: CGFloat = 0.5
    private static let iconSize: CGFloat = 40
    private static let forSaleBadgeIconSize: CGFloat = 14
    private static var forSaleBadgeOutsideOffset: CGFloat { forSaleBadgeIconSize * 0.25 }
    private static let creatorAvatarSize: CGFloat = 30
    private static let deleteActionWidthRatio: CGFloat = 0.22
    private static let swipeSpringDamping: CGFloat = 0.82

    var onShortnameCommit: ((String, @escaping (Bool) -> Void) -> Void)?
    var onDelete: (() -> Void)?
    var onSwipeOpened: (() -> Void)?
    var onSwipeClosed: (() -> Void)?
    var onSwipeInteractionChanged: ((Bool) -> Void)?

    private let mainContentView = UIView()
    private let deleteActionView = UIView()
    private let deleteButton = UIButton(type: .system)
    private let iconContainerView = UIView()
    private let iconView = UIImageView()
    private let forSaleBadgeHost = UIView()
    private let forSaleBadgeView = UIImageView()
    private let nameTextField = UITextField()
    private let creatorTextAvatar = TextAvatarView(username: "", size: creatorAvatarSize, fontSize: 12.sf)
    private let creatorAvatarImageView = UIImageView()
    private let creatorNameLabel = UILabel()
    private let emptyStateLabel = UILabel()
    private let separatorView = UIView()

    private var iconTask: URLSessionDataTask?
    private var loadingIconURL: String?
    private var creatorAvatarLoadGeneration: UInt = 0
    private var originalShortname = ""
    private var isSwipeDeletable = false
    private var swipeStartOffset: CGFloat = 0
    private var currentSwipeOffset: CGFloat = 0
    private var separatorHeightConstraint: NSLayoutConstraint!
    private lazy var swipePanDelegate = SwipePanGestureDelegate(owner: self)
    private lazy var panGesture: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = swipePanDelegate
        return pan
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        let selected = UIView()
        selected.backgroundColor = UIColor.theme.secondary.withAlphaComponent(0.6)
        selectedBackgroundView = selected
        if #available(iOS 14.0, *) {
            backgroundConfiguration = .clear()
        }
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        contentView.clipsToBounds = false
        mainContentView.clipsToBounds = false
        mainContentView.backgroundColor = UIColor.theme.secondary
        deleteActionView.backgroundColor = .systemRed
        deleteActionView.isHidden = true
        deleteActionView.clipsToBounds = true

        separatorView.backgroundColor = UIColor.theme.border
        separatorView.translatesAutoresizingMaskIntoConstraints = false

        deleteButton.setTitle(L(L10n.Common.delete), for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 13.sf, weight: .semibold)
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.titleLabel?.numberOfLines = 2
        deleteButton.titleLabel?.textAlignment = .center
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)

        iconContainerView.clipsToBounds = false

        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 6.swh

        forSaleBadgeHost.backgroundColor = UIColor.theme.secondary
        forSaleBadgeHost.layer.cornerRadius = 3.swh
        forSaleBadgeHost.clipsToBounds = true
        forSaleBadgeHost.isOpaque = true
        forSaleBadgeHost.isHidden = true
        forSaleBadgeHost.isUserInteractionEnabled = false

        forSaleBadgeView.image = UIImage(named: "ClanSetting/ForSaleIcon")?
            .withRenderingMode(.alwaysOriginal)
        forSaleBadgeView.contentMode = .scaleAspectFit
        forSaleBadgeView.backgroundColor = .clear
        forSaleBadgeView.isOpaque = false
        forSaleBadgeView.isUserInteractionEnabled = false

        nameTextField.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        nameTextField.textColor = .mezonTextPrimary
        nameTextField.borderStyle = .none
        nameTextField.backgroundColor = .clear
        nameTextField.returnKeyType = .done
        nameTextField.autocapitalizationType = .none
        nameTextField.autocorrectionType = .no
        nameTextField.spellCheckingType = .no
        nameTextField.clearButtonMode = .never
        nameTextField.delegate = self

        creatorAvatarImageView.contentMode = .scaleAspectFill
        creatorAvatarImageView.clipsToBounds = true
        creatorAvatarImageView.backgroundColor = .clear

        creatorNameLabel.font = .systemFont(ofSize: 13.sf, weight: .regular)
        creatorNameLabel.textColor = UIColor.theme.textStrong
        creatorNameLabel.lineBreakMode = .byTruncatingTail

        emptyStateLabel.font = .systemFont(ofSize: 15.sf, weight: .medium)
        emptyStateLabel.textColor = UIColor.theme.textDisabled
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.isHidden = true

        [deleteActionView, mainContentView, separatorView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        [deleteButton, iconContainerView, iconView, forSaleBadgeHost, forSaleBadgeView, nameTextField, emptyStateLabel, creatorTextAvatar, creatorNameLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        deleteActionView.addSubview(deleteButton)
        iconContainerView.addSubview(iconView)
        forSaleBadgeHost.addSubview(forSaleBadgeView)
        creatorTextAvatar.addSubview(creatorAvatarImageView)
        creatorAvatarImageView.translatesAutoresizingMaskIntoConstraints = false
        [iconContainerView, forSaleBadgeHost, nameTextField, emptyStateLabel, creatorTextAvatar, creatorNameLabel].forEach {
            mainContentView.addSubview($0)
        }
        contentView.addGestureRecognizer(panGesture)

        separatorHeightConstraint = separatorView.heightAnchor.constraint(
            equalToConstant: 1.0 / UIScreen.main.scale
        )

        NSLayoutConstraint.activate([
            deleteActionView.topAnchor.constraint(equalTo: contentView.topAnchor),
            deleteActionView.bottomAnchor.constraint(equalTo: separatorView.topAnchor),
            deleteActionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            deleteActionView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: Self.deleteActionWidthRatio),

            deleteButton.topAnchor.constraint(equalTo: deleteActionView.topAnchor),
            deleteButton.bottomAnchor.constraint(equalTo: deleteActionView.bottomAnchor),
            deleteButton.leadingAnchor.constraint(equalTo: deleteActionView.leadingAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: deleteActionView.trailingAnchor),

            mainContentView.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainContentView.bottomAnchor.constraint(equalTo: separatorView.topAnchor),

            separatorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorHeightConstraint,

            iconContainerView.leadingAnchor.constraint(equalTo: mainContentView.leadingAnchor, constant: Self.horizontalInset),
            iconContainerView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconContainerView.heightAnchor.constraint(equalToConstant: Self.iconSize),
            iconContainerView.topAnchor.constraint(equalTo: mainContentView.topAnchor, constant: 10.sh),
            iconContainerView.bottomAnchor.constraint(equalTo: mainContentView.bottomAnchor, constant: -10.sh),

            iconView.topAnchor.constraint(equalTo: iconContainerView.topAnchor),
            iconView.leadingAnchor.constraint(equalTo: iconContainerView.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: iconContainerView.trailingAnchor),
            iconView.bottomAnchor.constraint(equalTo: iconContainerView.bottomAnchor),

            forSaleBadgeHost.topAnchor.constraint(
                equalTo: iconContainerView.topAnchor,
                constant: -Self.forSaleBadgeOutsideOffset
            ),
            forSaleBadgeHost.trailingAnchor.constraint(
                equalTo: iconContainerView.trailingAnchor,
                constant: Self.forSaleBadgeOutsideOffset
            ),
            forSaleBadgeHost.widthAnchor.constraint(equalToConstant: Self.forSaleBadgeIconSize),
            forSaleBadgeHost.heightAnchor.constraint(equalTo: forSaleBadgeHost.widthAnchor),

            forSaleBadgeView.topAnchor.constraint(equalTo: forSaleBadgeHost.topAnchor),
            forSaleBadgeView.leadingAnchor.constraint(equalTo: forSaleBadgeHost.leadingAnchor),
            forSaleBadgeView.trailingAnchor.constraint(equalTo: forSaleBadgeHost.trailingAnchor),
            forSaleBadgeView.bottomAnchor.constraint(equalTo: forSaleBadgeHost.bottomAnchor),

            nameTextField.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: 10.sw),
            nameTextField.centerYAnchor.constraint(equalTo: mainContentView.centerYAnchor),
            nameTextField.widthAnchor.constraint(
                lessThanOrEqualTo: mainContentView.widthAnchor,
                multiplier: Self.nameMaxWidthRatio
            ),
            nameTextField.trailingAnchor.constraint(lessThanOrEqualTo: creatorNameLabel.leadingAnchor, constant: -10.sw),

            emptyStateLabel.centerXAnchor.constraint(equalTo: mainContentView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: mainContentView.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: mainContentView.leadingAnchor, constant: Self.horizontalInset),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: mainContentView.trailingAnchor, constant: -Self.horizontalInset),

            creatorTextAvatar.trailingAnchor.constraint(equalTo: mainContentView.trailingAnchor, constant: -Self.horizontalInset),
            creatorTextAvatar.centerYAnchor.constraint(equalTo: mainContentView.centerYAnchor),
            creatorTextAvatar.widthAnchor.constraint(equalToConstant: Self.creatorAvatarSize),
            creatorTextAvatar.heightAnchor.constraint(equalToConstant: Self.creatorAvatarSize),

            creatorAvatarImageView.topAnchor.constraint(equalTo: creatorTextAvatar.topAnchor),
            creatorAvatarImageView.leadingAnchor.constraint(equalTo: creatorTextAvatar.leadingAnchor),
            creatorAvatarImageView.trailingAnchor.constraint(equalTo: creatorTextAvatar.trailingAnchor),
            creatorAvatarImageView.bottomAnchor.constraint(equalTo: creatorTextAvatar.bottomAnchor),

            creatorNameLabel.trailingAnchor.constraint(equalTo: creatorTextAvatar.leadingAnchor, constant: -8.sw),
            creatorNameLabel.centerYAnchor.constraint(equalTo: mainContentView.centerYAnchor),
            creatorNameLabel.widthAnchor.constraint(
                lessThanOrEqualTo: mainContentView.widthAnchor,
                multiplier: Self.nameMaxWidthRatio
            ),
        ])

        creatorTextAvatar.setContentCompressionResistancePriority(.required, for: .horizontal)
        nameTextField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        creatorNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameTextField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        creatorNameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        [iconContainerView, iconView, forSaleBadgeHost, forSaleBadgeView].forEach {
            $0.setContentCompressionResistancePriority(.required, for: .horizontal)
            $0.setContentCompressionResistancePriority(.required, for: .vertical)
            $0.setContentHuggingPriority(.required, for: .horizontal)
            $0.setContentHuggingPriority(.required, for: .vertical)
        }
        applySwipeOffset(0, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        mainContentView.bringSubviewToFront(forSaleBadgeHost)
        guard currentSwipeOffset != 0 else { return }
        mainContentView.transform = CGAffineTransform(translationX: currentSwipeOffset, y: 0)
    }

    private func updateAppearance(isEmpty: Bool = false) {
        let contentBackground = isEmpty ? UIColor.theme.primary : UIColor.theme.secondary
        mainContentView.backgroundColor = contentBackground
        forSaleBadgeHost.backgroundColor = UIColor.theme.secondary
        separatorView.backgroundColor = UIColor.theme.border
        nameTextField.textColor = .mezonTextPrimary
        emptyStateLabel.textColor = UIColor.theme.textDisabled
        creatorNameLabel.textColor = UIColor.theme.textStrong
        selectedBackgroundView?.backgroundColor = contentBackground.withAlphaComponent(isEmpty ? 0 : 0.6)
        applySwipeOffset(currentSwipeOffset, animated: false)
    }

    private func syncDeleteActionVisibility() {
        deleteActionView.isHidden = !isSwipeDeletable || currentSwipeOffset == 0
    }

    private func applyRowSeparator(isLast: Bool) {
        let hairline = 1.0 / UIScreen.main.scale
        separatorHeightConstraint.constant = isLast ? 0 : hairline
        separatorView.isHidden = isLast
    }

    private func applySwipeOffset(_ offset: CGFloat, animated: Bool) {
        currentSwipeOffset = offset
        let updates = {
            self.mainContentView.transform = CGAffineTransform(translationX: offset, y: 0)
            self.syncDeleteActionVisibility()
        }
        if animated {
            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                usingSpringWithDamping: Self.swipeSpringDamping,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: updates
            )
        } else {
            updates()
        }
    }

    private func setSwipeInteractionActive(_ active: Bool) {
        onSwipeInteractionChanged?(active)
    }

    func configure(
        sticker: CachedClanStickerRecord,
        creatorAvatar: String?,
        creatorName: String,
        isEditable: Bool,
        isLast: Bool
    ) {
        closeSwipe(animated: false)
        isSwipeDeletable = isEditable
        syncDeleteActionVisibility()
        updateAppearance(isEmpty: false)
        iconContainerView.isHidden = false
        nameTextField.isHidden = false
        emptyStateLabel.isHidden = true
        originalShortname = sticker.shortname
        nameTextField.text = sticker.shortname
        nameTextField.textColor = .mezonTextPrimary
        nameTextField.textAlignment = .natural
        nameTextField.isUserInteractionEnabled = isEditable
        creatorNameLabel.text = creatorName
        creatorNameLabel.isHidden = false
        creatorNameLabel.alpha = 1
        creatorTextAvatar.isHidden = false
        creatorTextAvatar.alpha = 1
        iconView.isHidden = false
        forSaleBadgeHost.isHidden = !sticker.isForSale
        isUserInteractionEnabled = true
        applyRowSeparator(isLast: isLast)

        loadCreatorAvatar(creatorAvatar, displayName: creatorName)
        loadStickerIcon(sticker)
    }

    func configureEmpty(text: String, isLast: Bool = true) {
        closeSwipe(animated: false)
        isSwipeDeletable = false
        updateAppearance(isEmpty: true)
        iconTask?.cancel()
        iconView.image = nil
        creatorAvatarImageView.image = nil
        iconContainerView.isHidden = true
        iconView.isHidden = true
        forSaleBadgeHost.isHidden = true
        creatorTextAvatar.isHidden = true
        creatorNameLabel.isHidden = true
        deleteActionView.isHidden = true
        nameTextField.isHidden = true
        emptyStateLabel.isHidden = false
        emptyStateLabel.text = text
        nameTextField.text = nil
        nameTextField.isUserInteractionEnabled = false
        isUserInteractionEnabled = false
        applyRowSeparator(isLast: isLast)
    }

    func beginEditingName() {
        closeSwipe(animated: true)
        guard nameTextField.isUserInteractionEnabled else { return }
        nameTextField.becomeFirstResponder()
    }

    func closeSwipe(animated: Bool) {
        let wasOpen = currentSwipeOffset < 0
        applySwipeOffset(0, animated: animated)
        setSwipeInteractionActive(false)
        if wasOpen {
            onSwipeClosed?()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        nameTextField.resignFirstResponder()
        closeSwipe(animated: false)
        creatorTextAvatar.alpha = 1
        creatorNameLabel.alpha = 1
        creatorAvatarLoadGeneration += 1
        iconTask?.cancel()
        iconTask = nil
        loadingIconURL = nil
        iconView.image = nil
        forSaleBadgeHost.isHidden = true
        iconContainerView.isHidden = false
        nameTextField.isHidden = false
        emptyStateLabel.isHidden = true
        emptyStateLabel.text = nil
        creatorAvatarImageView.image = nil
        creatorTextAvatar.showImageMode()
        onShortnameCommit = nil
        onDelete = nil
        onSwipeOpened = nil
        onSwipeClosed = nil
        onSwipeInteractionChanged = nil
        isSwipeDeletable = false
        originalShortname = ""
    }

    private var maxSwipeOffset: CGFloat {
        contentView.bounds.width * Self.deleteActionWidthRatio
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isSwipeDeletable else { return }
        let maxOffset = maxSwipeOffset
        guard maxOffset > 0 else { return }

        switch gesture.state {
        case .began:
            swipeStartOffset = currentSwipeOffset
            setSwipeInteractionActive(true)
        case .changed:
            let translation = gesture.translation(in: contentView)
            let offset = min(0, max(-maxOffset, swipeStartOffset + translation.x))
            applySwipeOffset(offset, animated: false)
        case .ended, .cancelled:
            let translation = gesture.translation(in: contentView)
            let offset = min(0, max(-maxOffset, swipeStartOffset + translation.x))
            let velocity = gesture.velocity(in: contentView).x
            let shouldClose = swipeStartOffset < 0 && (velocity > 500 || offset > -maxOffset * 0.5)
            let shouldOpen = !shouldClose && (offset < -maxOffset * 0.5 || velocity < -500)
            let target: CGFloat = shouldOpen ? -maxOffset : 0
            if shouldOpen {
                onSwipeOpened?()
            } else if target == 0, currentSwipeOffset < 0 {
                onSwipeClosed?()
            }
            setSwipeInteractionActive(false)
            applySwipeOffset(target, animated: true)
        default:
            break
        }
    }

    @objc private func deleteTapped() {
        closeSwipe(animated: true)
        onDelete?()
    }

    private func commitEditing() {
        let trimmed = (nameTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameTextField.text = originalShortname
            return
        }
        nameTextField.text = trimmed
        guard trimmed != originalShortname else { return }
        onShortnameCommit?(trimmed) { [weak self] success in
            guard let self else { return }
            if success {
                self.originalShortname = trimmed
            } else {
                self.nameTextField.text = self.originalShortname
            }
        }
    }

    private func loadCreatorAvatar(_ avatar: String?, displayName: String) {
        creatorAvatarLoadGeneration += 1
        let generation = creatorAvatarLoadGeneration
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDisplayName = !trimmedName.isEmpty

        creatorAvatarImageView.image = nil
        creatorAvatarImageView.tintColor = nil
        if hasDisplayName {
            creatorTextAvatar.configure(username: trimmedName, fontSize: 12.sf)
        } else {
            setLegacyPlaceholderAvatar()
        }

        guard let avatar, !avatar.isEmpty else { return }

        let avatarUrl = avatar.hasPrefix("http") ? avatar : "\(MezonConfig.baseImgURL)/\(avatar)"
        let side = Int(Self.creatorAvatarSize * UIScreen.main.scale)
        let loadKey = ImgproxyURL.avatarProxyURL(from: avatarUrl, width: side, height: side)
        let resolvedKey = loadKey.isEmpty ? avatarUrl : loadKey

        if let cached = ImageCache.shared.memoryImage(forKey: resolvedKey) {
            creatorAvatarImageView.image = cached
            creatorAvatarImageView.tintColor = nil
            creatorTextAvatar.showImageMode()
            return
        }

        ImageCache.shared.loadAvatar(urlString: resolvedKey) { [weak self] image in
            guard let self, generation == self.creatorAvatarLoadGeneration else { return }
            if let image {
                self.creatorAvatarImageView.image = image
                self.creatorAvatarImageView.tintColor = nil
                self.creatorTextAvatar.showImageMode()
            } else if hasDisplayName {
                self.creatorAvatarImageView.image = nil
                self.creatorTextAvatar.configure(username: trimmedName, fontSize: 12.sf)
            } else {
                self.setLegacyPlaceholderAvatar()
            }
        }
    }

    private func setLegacyPlaceholderAvatar() {
        creatorTextAvatar.showImageMode()
        creatorAvatarImageView.image = UIImage(systemName: "person.circle.fill")?
            .withRenderingMode(.alwaysTemplate)
        creatorAvatarImageView.tintColor = UIColor.theme.textDisabled
    }

    private func loadStickerIcon(_ sticker: CachedClanStickerRecord) {
        iconTask?.cancel()
        iconTask = nil
        let side = Int(Self.iconSize * UIScreen.main.scale)
        let proxyURL = ImgproxyURL.create(
            from: sticker.displayImageURLString,
            width: side,
            height: side
        )
        loadingIconURL = proxyURL
        iconView.image = nil
        iconTask = ImageCache.shared.loadImage(urlString: proxyURL) { [weak self] image in
            guard let self, self.loadingIconURL == proxyURL else { return }
            self.iconView.image = image
        }
    }

    fileprivate func shouldBeginSwipePan(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture, isSwipeDeletable else { return false }
        let velocity = panGesture.velocity(in: contentView)
        guard abs(velocity.x) > abs(velocity.y) else { return false }
        if currentSwipeOffset < 0 { return true }
        return velocity.x < 0
    }
}

private final class SwipePanGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    private weak var owner: StickerItemCell?

    init(owner: StickerItemCell) {
        self.owner = owner
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        owner?.shouldBeginSwipePan(gestureRecognizer) ?? false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

extension StickerItemCell: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        closeSwipe(animated: true)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        commitEditing()
    }
}
