import UIKit

private enum DiscoverClanHashtags {
    static func parse(_ raw: String) -> [String] {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        let tags: [String]
        if value.hasPrefix("["), let data = value.data(using: .utf8),
           let array = try? JSONDecoder().decode([String].self, from: data) {
            tags = array
        } else if value.contains(",") {
            tags = value.components(separatedBy: ",")
        } else if value.hasPrefix("#") {
            tags = value.components(separatedBy: .whitespacesAndNewlines)
        } else {
            tags = [value]
        }
        var seen = Set<String>()
        return tags.compactMap { rawTag in
            var tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            if tag.hasPrefix("#") { tag.removeFirst() }
            tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            return !tag.isEmpty && seen.insert(tag).inserted ? tag : nil
        }
    }

    static func label(_ tag: String) -> String {
        switch tag {
        case "Gaming": return L(L10n.DiscoverDetail.hashtagGaming)
        case "Technology": return L(L10n.DiscoverDetail.hashtagTechnology)
        case "Education": return L(L10n.DiscoverDetail.hashtagEducation)
        case "Entertainment": return L(L10n.DiscoverDetail.hashtagEntertainment)
        case "Music": return L(L10n.DiscoverDetail.hashtagMusic)
        case "Art": return L(L10n.DiscoverDetail.hashtagArt)
        case "Crypto": return L(L10n.DiscoverDetail.hashtagCrypto)
        case "Anime": return L(L10n.DiscoverDetail.hashtagAnime)
        case "Sports": return L(L10n.DiscoverDetail.hashtagSports)
        case "Community": return L(L10n.DiscoverDetail.hashtagCommunity)
        default: return tag
        }
    }
}

private final class DiscoverClanHashtagsView: UIView {
    private let tags: [String]
    private var labels: [UILabel] = []
    private var chips: [UIView] = []
    private var layoutWidth: CGFloat = 0

    init(tags: [String]) {
        self.tags = tags
        super.init(frame: .zero)
        for _ in tags {
            let label = UILabel()
            label.font = .systemFont(ofSize: 12.sf)
            label.numberOfLines = 0
            let chip = UIView()
            chip.layer.cornerRadius = 16.swh
            chip.layer.borderWidth = 1
            chip.addSubview(label)
            addSubview(chip)
            labels.append(label)
            chips.append(chip)
        }
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: layoutTags(width: bounds.width, updateFrames: false))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if layoutWidth != bounds.width {
            layoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
        _ = layoutTags(width: bounds.width, updateFrames: true)
    }

    private func layoutTags(width: CGFloat, updateFrames: Bool) -> CGFloat {
        guard width > 0 else { return 0 }
        let paddingX = 12.sw
        let paddingY = 6.sh
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for (label, chip) in zip(labels, chips) {
            let textSize = label.sizeThatFits(CGSize(width: max(1, width - 2 * paddingX), height: .greatestFiniteMagnitude))
            let chipWidth = min(width, ceil(textSize.width) + 2 * paddingX)
            let chipHeight = ceil(textSize.height) + 2 * paddingY
            if x > 0 && x + chipWidth > width {
                x = 0
                y += rowHeight + 8.sh
                rowHeight = 0
            }
            if updateFrames {
                chip.frame = CGRect(x: x, y: y, width: chipWidth, height: chipHeight)
                label.frame = chip.bounds.insetBy(dx: paddingX, dy: paddingY)
            }
            x += chipWidth + 8.sw
            rowHeight = max(rowHeight, chipHeight)
        }
        return y + rowHeight
    }

    func applyTheme() {
        for (index, label) in labels.enumerated() {
            let chip = chips[index]
            label.text = DiscoverClanHashtags.label(tags[index])
            label.textColor = UIColor.theme.textStrong
            chip.backgroundColor = UIColor.theme.secondaryWeight
            chip.layer.borderColor = UIColor.theme.borderDim.cgColor
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}

private enum DiscoverClanLayout {
    static let pageSize: Int32 = 6
    static let bannerDisplayHeightList: CGFloat = 120
    static let detailBannerHeightMultiplier: CGFloat = 0.38
    static let detailLogoSide: CGFloat = 88
    static let avatarSide: CGFloat = 24
    static let rowVerticalInset: CGFloat = 8
    static let rowHorizontalInset: CGFloat = 12
}

private func discoverDetailFormatCreated(seconds: UInt32) -> String {
    guard seconds > 0 else { return L(L10n.DiscoverDetail.dateUnavailable) }
    let date = Date(timeIntervalSince1970: TimeInterval(seconds))
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .none
    df.locale = LanguageManager.shared.current.locale
    return df.string(from: date)
}

private func discoverDetailChattySubtitle(online: Int32, total: Int32) -> String {
    let t = max(total, 1)
    let r = Double(online) / Double(t)
    if r >= 0.25 { return L(L10n.DiscoverDetail.chattyBusy) }
    if r >= 0.10 { return L(L10n.DiscoverDetail.chattyModerate) }
    return L(L10n.DiscoverDetail.chattyQuiet)
}

private enum DiscoverClanImageProxy {
    static func bannerURL(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        let scale = UIScreen.main.scale
        let contentWidthPt = UIScreen.main.bounds.width - DiscoverClanLayout.rowHorizontalInset * 2
        let wPx = max(480, Int(ceil(contentWidthPt * scale)))
        let hPx = max(240, Int(ceil(DiscoverClanLayout.bannerDisplayHeightList * scale)))
        return ImgproxyURL.create(from: raw, width: wPx, height: hPx, resizeType: "fill")
    }

    static func avatarURL(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        let px = Int(ceil(DiscoverClanLayout.avatarSide * UIScreen.main.scale))
        return ImgproxyURL.create(from: raw, width: px, height: px, resizeType: "fill")
    }

    static func detailBannerURL(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        let scale = UIScreen.main.scale
        let wPt = UIScreen.main.bounds.width
        let hPt = wPt * DiscoverClanLayout.detailBannerHeightMultiplier
        let wPx = max(640, Int(ceil(wPt * scale)))
        let hPx = max(360, Int(ceil(hPt * scale)))
        return ImgproxyURL.create(from: raw, width: wPx, height: hPx, resizeType: "fill")
    }

    static func detailLogoURL(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        let px = Int(80 * UIScreen.main.scale)
        return ImgproxyURL.create(from: raw, width: px, height: px, resizeType: "fill")
    }
}

private final class DiscoverClanVerifiedBadge: UILabel {
    private let contentInsets = UIEdgeInsets(top: 2.sh, left: 6.sw, bottom: 2.sh, right: 6.sw)

    init(fontSize: CGFloat) {
        super.init(frame: .zero)
        font = .systemFont(ofSize: fontSize, weight: .semibold)
        textColor = .white
        backgroundColor = UIColor(rgb: 0x3BA55C)
        layer.cornerRadius = 4.swh
        clipsToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
        refreshText()
    }

    required init?(coder: NSCoder) { fatalError() }

    func refreshText() {
        let title = L(L10n.Discover.verified)
        let badgeFont = font ?? UIFont.systemFont(ofSize: 10.sf, weight: .semibold)
        let iconSize = 12.swh
        let icon = NSTextAttachment()
        icon.image = UIImage(systemName: "checkmark.seal.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
        icon.bounds = CGRect(x: 0, y: (badgeFont.capHeight - iconSize) / 2, width: iconSize, height: iconSize)
        let text = NSMutableAttributedString(attachment: icon)
        text.append(NSAttributedString(string: " \(title)", attributes: [.font: badgeFont, .foregroundColor: UIColor.white]))
        attributedText = text
        accessibilityLabel = title
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + contentInsets.left + contentInsets.right,
                      height: size.height + contentInsets.top + contentInsets.bottom)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }
}

private final class DiscoverClanListCell: UITableViewCell {
    private let cardContainer = UIView()
    private let bannerView = UIImageView()
    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let descLabel = UILabel()
    private let membersLabel = UILabel()
    private let verifiedBadge = DiscoverClanVerifiedBadge(fontSize: 10.sf)
    private var bannerTask: URLSessionDataTask?
    private var avatarTask: URLSessionDataTask?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        cardContainer.backgroundColor = UIColor.theme.secondary
        cardContainer.layer.cornerRadius = 12.swh
        cardContainer.layer.borderWidth = 1
        cardContainer.layer.borderColor = UIColor.theme.borderDim.cgColor
        cardContainer.clipsToBounds = true
        cardContainer.translatesAutoresizingMaskIntoConstraints = false

        bannerView.contentMode = .scaleAspectFill
        bannerView.clipsToBounds = true
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = DiscoverClanLayout.avatarSide / 2
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 12.sf, weight: .semibold)
        nameLabel.numberOfLines = 1
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.font = .systemFont(ofSize: 10.sf, weight: .regular)
        descLabel.numberOfLines = 2
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        membersLabel.font = .systemFont(ofSize: 10.sf, weight: .medium)
        membersLabel.translatesAutoresizingMaskIntoConstraints = false
        membersLabel.setContentHuggingPriority(.required, for: .horizontal)

        let dot = UIView()
        dot.backgroundColor = UIColor(rgb: 0x3BA55C)
        dot.layer.cornerRadius = 4.swh
        dot.translatesAutoresizingMaskIntoConstraints = false
        let bottomRow = UIStackView(arrangedSubviews: [dot, membersLabel])
        bottomRow.spacing = 6.sw
        bottomRow.alignment = .center
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        let verifiedStack = UIStackView(arrangedSubviews: [bottomRow, UIView(), verifiedBadge])
        verifiedStack.spacing = 8.sw
        verifiedStack.alignment = .center
        verifiedStack.translatesAutoresizingMaskIntoConstraints = false

        let headerRow = UIStackView(arrangedSubviews: [avatarView, nameLabel])
        headerRow.spacing = 8.sw
        headerRow.alignment = .center
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        let textBlock = UIStackView(arrangedSubviews: [headerRow, descLabel, verifiedStack])
        textBlock.axis = .vertical
        textBlock.spacing = 8.sh
        textBlock.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(cardContainer)
        cardContainer.addSubview(bannerView)
        cardContainer.addSubview(textBlock)

        NSLayoutConstraint.activate([
            cardContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: DiscoverClanLayout.rowVerticalInset),
            cardContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DiscoverClanLayout.rowHorizontalInset),
            cardContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DiscoverClanLayout.rowHorizontalInset),
            cardContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -DiscoverClanLayout.rowVerticalInset),

            bannerView.topAnchor.constraint(equalTo: cardContainer.topAnchor),
            bannerView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
            bannerView.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor),
            bannerView.heightAnchor.constraint(equalToConstant: DiscoverClanLayout.bannerDisplayHeightList),

            avatarView.widthAnchor.constraint(equalToConstant: DiscoverClanLayout.avatarSide),
            avatarView.heightAnchor.constraint(equalToConstant: DiscoverClanLayout.avatarSide),

            dot.widthAnchor.constraint(equalToConstant: 8.swh),
            dot.heightAnchor.constraint(equalToConstant: 8.swh),

            textBlock.topAnchor.constraint(equalTo: bannerView.bottomAnchor, constant: 10.sh),
            textBlock.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 10.sw),
            textBlock.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -10.sw),
            textBlock.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor, constant: -10.sh),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(false, animated: false)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(false, animated: false)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        bannerTask?.cancel()
        avatarTask?.cancel()
        bannerView.image = nil
        avatarView.image = nil
    }

    func configure(_ item: Mezon_Api_ClanDiscover) {
        nameLabel.textColor = UIColor.theme.textStrong
        descLabel.textColor = UIColor.theme.textDisabled
        membersLabel.textColor = UIColor.theme.textDisabled
        nameLabel.text = item.clanName
        descLabel.text = item.description_p
        membersLabel.text = String(format: L(L10n.Discover.membersLabel), Int(item.totalMembers))
        verifiedBadge.refreshText()
        verifiedBadge.isHidden = !item.verified

        bannerTask?.cancel()
        avatarTask?.cancel()
        bannerView.image = nil
        avatarView.image = nil
        if !item.banner.isEmpty {
            let url = DiscoverClanImageProxy.bannerURL(item.banner)
            bannerTask = ImageCache.shared.loadImage(urlString: url) { [weak self] img in
                self?.bannerView.image = img
            }
        }
        if !item.clanLogo.isEmpty {
            let url = DiscoverClanImageProxy.avatarURL(item.clanLogo)
            avatarTask = ImageCache.shared.loadImage(urlString: url) { [weak self] img in
                self?.avatarView.image = img
            }
        }
    }

    func applyTheme() {
        cardContainer.backgroundColor = UIColor.theme.secondary
        cardContainer.layer.borderColor = UIColor.theme.borderDim.cgColor
        nameLabel.textColor = UIColor.theme.textStrong
        descLabel.textColor = UIColor.theme.textDisabled
        membersLabel.textColor = UIColor.theme.textDisabled
    }
}

final class DiscoverClanEmptyStateViewController: UIViewController {

    private let context: AccountContext
    private let gradientLayer = CAGradientLayer()
    private let headerContainer = UIView()
    private let titleLabel = UILabel()
    private let searchField = UITextField()
    private let qrHeaderButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: "Profile/ScanQR")?.withRenderingMode(.alwaysTemplate), for: .normal)
        btn.layer.cornerRadius = 16
        btn.layer.borderWidth = 1
        btn.clipsToBounds = true
        btn.imageEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let addFriendHeaderButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(
            UIImage(named: "Notifications/AddFriendIcon", in: Bundle.main, compatibleWith: nil)?
                .withRenderingMode(.alwaysOriginal),
            for: .normal
        )
        btn.layer.cornerRadius = 16
        btn.layer.borderWidth = 1
        btn.clipsToBounds = true
        btn.imageEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refresh = UIRefreshControl()
    private var searchDebounce: DispatchWorkItem?

    private var allItems: [Mezon_Api_ClanDiscover] = []
    private var filtered: [Mezon_Api_ClanDiscover] = []
    private var currentPage: Int32 = 1
    private var totalPages: Int32 = 1
    private var loading = false
    private var loadingMore = false
    private var fetchError: String?

    private let statusLabel: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        l.numberOfLines = 0
        l.font = .systemFont(ofSize: 14.sf)
        l.isHidden = true
        return l
    }()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private lazy var statusBackgroundHost: UIView = {
        let v = UIView()
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(loadingIndicator)
        v.addSubview(statusLabel)
        let statusLeading = statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: v.leadingAnchor, constant: 24.sw)
        statusLeading.priority = UILayoutPriority(999)
        let statusTrailing = statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -24.sw)
        statusTrailing.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            statusLeading,
            statusTrailing,
        ])
        v.isUserInteractionEnabled = false
        return v
    }()

    weak var hostNavigationController: UINavigationController?
    var onUserJoinedClan: (() -> Void)?

    private var enclosingNavigationController: NavigationController? {
        var current: UIViewController? = self
        while let node = current {
            if let nav = node as? NavigationController {
                return nav
            }
            if let nav = node.navigationController as? NavigationController {
                return nav
            }
            current = node.parent
        }
        return nil
    }

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        gradientLayer.startPoint = CGPoint(x: 1, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0, y: 0)
        view.layer.insertSublayer(gradientLayer, at: 0)
        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        titleLabel.text = L(L10n.Discover.communityOnMezon)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        searchField.borderStyle = .none
        searchField.backgroundColor = UIColor.theme.tertiary
        searchField.layer.cornerRadius = 16
        searchField.layer.borderWidth = 0
        searchField.clipsToBounds = true
        searchField.font = .systemFont(ofSize: 14.sf)
        searchField.textColor = UIColor.theme.textStrong
        searchField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.Discover.exploreCommunities),
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )
        searchField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10.sw, height: 1))
        searchField.leftViewMode = .always
        searchField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 10.sw, height: 1))
        searchField.rightViewMode = .always
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)

        qrHeaderButton.addTarget(self, action: #selector(openQR), for: .touchUpInside)
        addFriendHeaderButton.addTarget(self, action: #selector(openAddFriend), for: .touchUpInside)

        let navRow = UIStackView(arrangedSubviews: [searchField, qrHeaderButton, addFriendHeaderButton])
        navRow.spacing = 8.sw
        navRow.alignment = .center
        navRow.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, navRow])
        headerStack.axis = .vertical
        headerStack.spacing = 10.sh
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(headerStack)
        headerContainer.translatesAutoresizingMaskIntoConstraints = false

        let headerStackTrailing = headerStack.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -12.sw)
        headerStackTrailing.priority = UILayoutPriority(999)
        let headerStackBottom = headerStack.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -14.sh)
        headerStackBottom.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 14.sh),
            headerStack.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 12.sw),
            headerStackTrailing,
            headerStackBottom,
            searchField.heightAnchor.constraint(equalToConstant: 32),
            qrHeaderButton.widthAnchor.constraint(equalToConstant: 32),
            qrHeaderButton.heightAnchor.constraint(equalToConstant: 32),
            addFriendHeaderButton.widthAnchor.constraint(equalToConstant: 32),
            addFriendHeaderButton.heightAnchor.constraint(equalToConstant: 32),
        ])

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 340
        tableView.register(DiscoverClanListCell.self, forCellReuseIdentifier: "c")
        tableView.contentInset.bottom = 80
        tableView.verticalScrollIndicatorInsets.bottom = 80
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.refreshControl = refresh
        refresh.addTarget(self, action: #selector(pullRefresh), for: .valueChanged)

        view.addSubview(headerContainer)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            headerContainer.topAnchor.constraint(equalTo: view.topAnchor),
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        applyThemeFully()
        updateStatusBackgroundVisibility()
        Task { await reloadFirstPage() }

        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: LanguageManager.didChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appearanceChanged() {
        applyThemeFully()
        tableView.reloadData()
        updateStatusBackgroundVisibility()
    }

    private func applyThemeFully() {
        let t = UIColor.theme
        gradientLayer.colors = [t.primary.cgColor, t.primaryGradient.cgColor]
        titleLabel.text = L(L10n.Discover.communityOnMezon)
        titleLabel.textColor = t.textStrong
        searchField.backgroundColor = t.tertiary
        searchField.layer.borderWidth = 0
        searchField.textColor = t.textStrong
        searchField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.Discover.exploreCommunities),
            attributes: [.foregroundColor: t.textDisabled]
        )
        headerContainer.layer.borderWidth = 0
        qrHeaderButton.backgroundColor = t.tertiary
        qrHeaderButton.layer.borderColor = t.border.withAlphaComponent(0.4).cgColor
        
        let currentTheme = ThemeManager.shared.current
        let effectiveTheme = currentTheme == .system ? (UITraitCollection.current.userInterfaceStyle == .dark ? AppTheme.dark : AppTheme.light) : currentTheme
        qrHeaderButton.setImage(UIImage(named: "Profile/ScanQR")?.withRenderingMode(.alwaysTemplate), for: .normal)
        if effectiveTheme == .light || effectiveTheme == .sunrise {
            qrHeaderButton.tintColor = UIColor(hexString: "#ff6b6f76")
        } else {
            qrHeaderButton.tintColor = UIColor(hexString: "#fefefe")
        }
        
        addFriendHeaderButton.backgroundColor = t.tertiary
        addFriendHeaderButton.layer.borderColor = t.border.withAlphaComponent(0.4).cgColor
        statusLabel.textColor = t.textDisabled
        loadingIndicator.color = t.textStrong
    }

    private func updateStatusBackgroundVisibility() {
        if loading && allItems.isEmpty {
            fetchError = nil
            statusLabel.isHidden = true
            loadingIndicator.isHidden = false
            loadingIndicator.startAnimating()
            tableView.backgroundView = statusBackgroundHost
            return
        }
        loadingIndicator.stopAnimating()
        loadingIndicator.isHidden = true
        if fetchError != nil {
            statusLabel.text = L(L10n.Discover.loadFailed)
            statusLabel.isHidden = false
            tableView.backgroundView = statusBackgroundHost
            return
        }
        if allItems.isEmpty {
            statusLabel.text = L(L10n.Discover.noCommunities)
            statusLabel.isHidden = false
            tableView.backgroundView = statusBackgroundHost
            return
        }
        if filtered.isEmpty {
            statusLabel.text = L(L10n.Discover.noMatchingCommunities)
            statusLabel.isHidden = false
            tableView.backgroundView = statusBackgroundHost
            return
        }
        statusLabel.text = nil
        statusLabel.isHidden = true
        tableView.backgroundView = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }

    @objc private func searchChanged() {
        searchDebounce?.cancel()
        let term = searchField.text ?? ""
        let work = DispatchWorkItem { [weak self] in
            self?.applyFilter(term: term)
        }
        searchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func applyFilter(term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty {
            filtered = allItems
        } else {
            filtered = allItems.filter {
                $0.clanName.lowercased().contains(t) || $0.description_p.lowercased().contains(t)
            }
        }
        tableView.reloadData()
        updateStatusBackgroundVisibility()
    }

    @objc private func pullRefresh() {
        Task { await reloadFirstPage() }
    }

    func reloadDiscoverList() {
        Task { await reloadFirstPage() }
    }

    private func navigationForDiscoverPush() -> UINavigationController? {
        enclosingNavigationController
            ?? hostNavigationController
            ?? navigationController
            ?? parent?.navigationController
            ?? parent?.parent?.navigationController
    }

    @objc private func openQR() {
        let vc = QRScannerViewController(context: context)
        navigationForDiscoverPush()?.pushViewController(vc, animated: true)
    }

    @objc private func openAddFriend() {
        let vc = FriendRequestViewController(context: context)
        navigationForDiscoverPush()?.pushViewController(vc, animated: true)
    }

    private func reloadFirstPage() async {
        await fetchPage(1, append: false)
        await MainActor.run {
            self.refresh.endRefreshing()
        }
    }

    private func fetchPage(_ page: Int32, append: Bool) async {
        guard !loading else {
            await MainActor.run { if append { self.loadingMore = false } }
            return
        }
        loading = true
        await MainActor.run {
            if !append {
                self.fetchError = nil
            }
            self.updateStatusBackgroundVisibility()
            if !append { self.tableView.reloadData() }
        }
        do {
            let token = await context.getToken()
            let r = try await context.account.network.listClanDiscover(
                pageNumber: page,
                itemPerPage: DiscoverClanLayout.pageSize,
                bearerToken: token
            )
            await MainActor.run {
                if append {
                    let existing = Set(allItems.map { $0.clanID })
                    let newOnes = r.clanDiscover.filter { !existing.contains($0.clanID) }
                    allItems.append(contentsOf: newOnes)
                } else {
                    allItems = r.clanDiscover
                }
                currentPage = r.pageNumber != 0 ? r.pageNumber : page
                totalPages = max(1, r.pageCount)
                fetchError = nil
                applyFilter(term: searchField.text ?? "")
                loading = false
                loadingMore = false
                tableView.reloadData()
                updateStatusBackgroundVisibility()
            }
        } catch {
            await MainActor.run {
                loading = false
                loadingMore = false
                if allItems.isEmpty {
                    fetchError = error.localizedDescription
                }
                tableView.reloadData()
                updateStatusBackgroundVisibility()
            }
        }
    }

    private func loadMoreIfNeeded() {
        guard !loading, !loadingMore, currentPage < totalPages else { return }
        loadingMore = true
        let next = currentPage + 1
        Task { await fetchPage(next, append: true) }
    }
}

extension DiscoverClanEmptyStateViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filtered.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "c", for: indexPath) as! DiscoverClanListCell
        cell.configure(filtered[indexPath.row])
        cell.applyTheme()
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = filtered[indexPath.row]
        let detail = DiscoverClanDetailViewController(context: context, item: item)
        detail.onJoined = { [weak self] in
            self?.onUserJoinedClan?()
        }
        guard let nav = navigationForDiscoverPush() else { return }
        nav.pushViewController(detail, animated: true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offset = scrollView.contentOffset.y
        let h = scrollView.contentSize.height
        let fh = scrollView.frame.height
        if h > 0, offset > h - fh * 1.5 {
            loadMoreIfNeeded()
        }
    }
}

final class DiscoverClanDetailViewController: BaseViewController {

    private let context: AccountContext
    private let item: Mezon_Api_ClanDiscover
    private let backButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let bannerView = UIImageView()
    private let logoView = UIImageView()
    private let cardView = UIView()
    private let nameLabel = UILabel()
    private let descLabel = UILabel()
    private let memberDot = UIView()
    private let membersLabel = UILabel()
    private let joinButton = UIButton(type: .system)
    private let innerStack = UIStackView()
    private let infoStack = UIStackView()
    private let aboutTitleLabel = UILabel()
    private let aboutBodyLabel = UILabel()
    private var hashtagsView: DiscoverClanHashtagsView?
    private var infoRowIconBgs: [UIView] = []
    private var infoRowTitleLabels: [UILabel] = []
    private var infoRowSubtitleLabels: [UILabel] = []
    private var infoRowIconViews: [UIImageView] = []

    var onJoined: (() -> Void)?

    init(context: AccountContext, item: Mezon_Api_ClanDiscover) {
        self.context = context
        self.item = item
        super.init(navigationBarPresentationData: nil)
        displayNavigationBar = false
        hidesBottomBarWhenPushed = true
    }

    required init(coder: NSCoder) { fatalError() }

    override func setupUI() {
        view.backgroundColor = UIColor.theme.primary
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        bannerView.contentMode = .scaleAspectFill
        bannerView.clipsToBounds = true
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        logoView.contentMode = .scaleAspectFill
        logoView.clipsToBounds = true
        logoView.layer.borderWidth = 4
        logoView.translatesAutoresizingMaskIntoConstraints = false
        let ls = DiscoverClanLayout.detailLogoSide
        logoView.layer.cornerRadius = ls * 0.22
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 16.swh
        cardView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        cardView.clipsToBounds = true
        nameLabel.font = .systemFont(ofSize: 24.sf, weight: .bold)
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 0
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.font = .systemFont(ofSize: 14.sf)
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        memberDot.translatesAutoresizingMaskIntoConstraints = false
        memberDot.layer.cornerRadius = 4.swh
        membersLabel.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        membersLabel.textAlignment = .natural
        membersLabel.translatesAutoresizingMaskIntoConstraints = false
        joinButton.backgroundColor = UIColor(rgb: 0x5865F2)
        joinButton.setTitle(L(L10n.Discover.joinClan), for: .normal)
        joinButton.setTitleColor(.white, for: .normal)
        joinButton.titleLabel?.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        joinButton.layer.cornerRadius = 12.swh
        joinButton.translatesAutoresizingMaskIntoConstraints = false
        joinButton.addTarget(self, action: #selector(joinTapped), for: .touchUpInside)
        let membersRow = UIStackView(arrangedSubviews: [memberDot, membersLabel])
        membersRow.axis = .horizontal
        membersRow.spacing = 8.sw
        membersRow.alignment = .center
        let membersWrap = UIView()
        membersWrap.translatesAutoresizingMaskIntoConstraints = false
        membersRow.translatesAutoresizingMaskIntoConstraints = false
        membersWrap.addSubview(membersRow)
        NSLayoutConstraint.activate([
            membersRow.centerXAnchor.constraint(equalTo: membersWrap.centerXAnchor),
            membersRow.topAnchor.constraint(equalTo: membersWrap.topAnchor),
            membersRow.bottomAnchor.constraint(equalTo: membersWrap.bottomAnchor),
        ])
        innerStack.axis = .vertical
        innerStack.spacing = 16.sh
        innerStack.alignment = .fill
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        infoStack.axis = .vertical
        infoStack.spacing = 20.sh
        infoStack.alignment = .fill
        aboutTitleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        aboutTitleLabel.text = L(L10n.DiscoverDetail.about)
        aboutTitleLabel.textAlignment = .left
        aboutBodyLabel.font = .systemFont(ofSize: 14.sf)
        aboutBodyLabel.numberOfLines = 0
        aboutBodyLabel.textAlignment = .left
        let feat = item.shortURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let featureSubtitle = !feat.isEmpty ? feat : L(L10n.DiscoverDetail.featureFallback)
        let communitySubtitle = item.verified
            ? L(L10n.DiscoverDetail.communityVerified)
            : L(L10n.DiscoverDetail.communityFallback)
        infoStack.addArrangedSubview(
            discoverDetailInfoRow(iconName: "bubble.left.and.bubble.right", title: L(L10n.DiscoverDetail.howChatty), subtitle: discoverDetailChattySubtitle(online: item.onlineMembers, total: item.totalMembers)))
        infoStack.addArrangedSubview(
            discoverDetailInfoRow(iconName: "calendar", title: L(L10n.DiscoverDetail.clanCreated), subtitle: discoverDetailFormatCreated(seconds: item.createTimeSeconds)))
        infoStack.addArrangedSubview(
            discoverDetailInfoRow(iconName: "sparkles", title: L(L10n.DiscoverDetail.feature), subtitle: featureSubtitle))
        infoStack.addArrangedSubview(
            discoverDetailInfoRow(iconName: "person.3.fill", title: L(L10n.DiscoverDetail.communityRow), subtitle: communitySubtitle))
        innerStack.addArrangedSubview(nameLabel)
        innerStack.addArrangedSubview(descLabel)
        innerStack.addArrangedSubview(membersWrap)
        innerStack.addArrangedSubview(joinButton)
        innerStack.addArrangedSubview(infoStack)
        innerStack.addArrangedSubview(aboutTitleLabel)
        innerStack.addArrangedSubview(aboutBodyLabel)
        let hashtags = DiscoverClanHashtags.parse(item.hashtags)
        if !hashtags.isEmpty {
            let tagsView = DiscoverClanHashtagsView(tags: hashtags)
            hashtagsView = tagsView
            innerStack.addArrangedSubview(tagsView)
        }
        innerStack.setCustomSpacing(24.sh, after: joinButton)
        innerStack.setCustomSpacing(20.sh, after: infoStack)
        joinButton.heightAnchor.constraint(equalToConstant: 48.sh).isActive = true
        NSLayoutConstraint.activate([
            memberDot.widthAnchor.constraint(equalToConstant: 8.swh),
            memberDot.heightAnchor.constraint(equalToConstant: 8.swh),
        ])
        nameLabel.text = item.clanName
        descLabel.text = item.description_p
        membersLabel.text = L(L10n.ClanAction.memberCount, Int(item.totalMembers))
        let aboutRaw = item.about.trimmingCharacters(in: .whitespacesAndNewlines)
        aboutBodyLabel.text = aboutRaw
        let showAbout = !aboutRaw.isEmpty
        aboutTitleLabel.isHidden = !showAbout
        aboutBodyLabel.isHidden = !showAbout
        view.addSubview(scrollView)
        view.addSubview(backButton)
        scrollView.addSubview(contentView)
        contentView.addSubview(bannerView)
        contentView.addSubview(cardView)
        contentView.addSubview(logoView)
        cardView.addSubview(innerStack)
        contentView.bringSubviewToFront(logoView)
        view.bringSubviewToFront(backButton)
        let sym = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: sym), for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.backgroundColor = UIColor.theme.primary.withAlphaComponent(0.45)
        backButton.layer.cornerRadius = 20.swh
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            bannerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            bannerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bannerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bannerView.heightAnchor.constraint(equalTo: bannerView.widthAnchor, multiplier: DiscoverClanLayout.detailBannerHeightMultiplier),
            cardView.topAnchor.constraint(equalTo: bannerView.bottomAnchor, constant: -32.sh),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            logoView.widthAnchor.constraint(equalToConstant: DiscoverClanLayout.detailLogoSide),
            logoView.heightAnchor.constraint(equalToConstant: DiscoverClanLayout.detailLogoSide),
            logoView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            logoView.centerYAnchor.constraint(equalTo: bannerView.bottomAnchor),
            innerStack.topAnchor.constraint(equalTo: logoView.bottomAnchor, constant: 12.sh),
            innerStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16.sw),
            innerStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16.sw),
            innerStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -24.sh),
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8.sw),
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8.sh),
            backButton.widthAnchor.constraint(equalToConstant: 40.swh),
            backButton.heightAnchor.constraint(equalToConstant: 40.swh),
        ])
        if !item.banner.isEmpty {
            let u = DiscoverClanImageProxy.detailBannerURL(item.banner)
            _ = ImageCache.shared.loadImage(urlString: u) { [weak self] img in
                self?.bannerView.image = img
            }
        }
        if !item.clanLogo.isEmpty {
            let u = DiscoverClanImageProxy.detailLogoURL(item.clanLogo)
            _ = ImageCache.shared.loadImage(urlString: u) { [weak self] img in
                self?.logoView.image = img
            }
        }
    }

    private func discoverDetailInfoRow(iconName: String, title: String, subtitle: String) -> UIView {
        let iconBg = UIView()
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        iconBg.layer.cornerRadius = 18.swh
        iconBg.backgroundColor = UIColor.theme.borderDim
        let iconView = UIImageView()
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        iconView.image = UIImage(systemName: iconName, withConfiguration: cfg)?.withRenderingMode(.alwaysTemplate)
        iconView.tintColor = UIColor.theme.textDisabled
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBg.addSubview(iconView)
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.text = title
        titleLabel.numberOfLines = 0
        let subtitleLabel = UILabel()
        subtitleLabel.font = .systemFont(ofSize: 13.sf, weight: .regular)
        subtitleLabel.textColor = UIColor.theme.textDisabled
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = subtitle
        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2.sh
        textStack.alignment = .leading
        let row = UIStackView(arrangedSubviews: [iconBg, textStack])
        row.axis = .horizontal
        row.spacing = 12.sw
        row.alignment = .top
        NSLayoutConstraint.activate([
            iconBg.widthAnchor.constraint(equalToConstant: 36.swh),
            iconBg.heightAnchor.constraint(equalToConstant: 36.swh),
            iconView.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18.swh),
            iconView.heightAnchor.constraint(equalToConstant: 18.swh),
        ])
        infoRowIconBgs.append(iconBg)
        infoRowTitleLabels.append(titleLabel)
        infoRowSubtitleLabels.append(subtitleLabel)
        infoRowIconViews.append(iconView)
        return row
    }

    override func applyTheme() {
        view.backgroundColor = UIColor.theme.primary
        cardView.backgroundColor = UIColor.theme.secondary
        logoView.layer.borderColor = UIColor.theme.primary.cgColor
        nameLabel.textColor = UIColor.theme.textStrong
        descLabel.textColor = UIColor.theme.textDisabled
        membersLabel.textColor = UIColor.theme.textStrong
        memberDot.backgroundColor = UIColor(rgb: 0x3BA55C)
        aboutTitleLabel.textColor = UIColor.theme.textStrong
        aboutBodyLabel.textColor = UIColor.theme.textDisabled
        hashtagsView?.applyTheme()
        backButton.tintColor = UIColor.theme.textStrong
        backButton.backgroundColor = UIColor.theme.primary.withAlphaComponent(0.45)
        for bg in infoRowIconBgs {
            bg.backgroundColor = UIColor.theme.borderDim
        }
        for t in infoRowTitleLabels {
            t.textColor = UIColor.theme.textStrong
        }
        for s in infoRowSubtitleLabels {
            s.textColor = UIColor.theme.textDisabled
        }
        for iv in infoRowIconViews {
            iv.tintColor = UIColor.theme.textDisabled
        }
    }

    @objc private func backTapped() {
        if let nav = navigationController as? NavigationController {
            nav.filterController(self, animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc private func joinTapped() {
        joinButton.isEnabled = false
        Task { @MainActor in
            let code = "\(item.inviteID)"
            let clanId = await ClanInviteJoiner.join(context: context, code: code, clanId: item.clanID)
            guard let clanId, clanId != 0 else {
                joinButton.isEnabled = true
                return
            }
            await ClanChannelDescsGate.ensureFetchedBeforeJoin(context: context, clanId: clanId)
            context.account.socket.joinClanChat(clanId: clanId)
            onJoined?()
            NotificationCenter.default.post(
                name: .mezonQRSelectClan,
                object: nil,
                userInfo: ["clanId": "\(clanId)"]
            )
        }
    }
}
