import UIKit
import AsyncDisplayKit

struct ClanListInteraction {
    let onSelectClan: (Mezon_Api_ClanDesc) -> Void
    let onSelectDM: (Mezon_Api_ChannelDescription) -> Void
    let onLogoTapped: () -> Void
}

final class ClanListContainerNode: ASDisplayNode {

    static let iconSize: CGFloat = 42.swh

    private let collectionView: UICollectionView
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private lazy var gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.startPoint = CGPoint(x: 0.5, y: 0)
        gl.endPoint   = CGPoint(x: 0.5, y: 1)
        return gl
    }()

    private var state: ClanListState = .empty
    private let interaction: ClanListInteraction
    private let disposables = DisposableSet()

    init(signal: Signal<ClanListState, NoError>, interaction: ClanListInteraction) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 16.sh
        layout.itemSize = CGSize(width: Self.iconSize, height: Self.iconSize)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.interaction = interaction
        super.init()

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                let prevDmFingerprint = Self.unreadDmStripFingerprint(self.state.unreadDMs)
                let prevClanId = self.state.selectedClanId
                let wasLoading = self.state.isLoading
                let prevDMCount = self.state.unreadDMs.count
                let prevDMBadges = self.state.unreadDMs.map { $0.countMessUnread }
                let prevClanBadges = self.state.clans.map { $0.badgeCount }
                self.state = newState

                if newState.isLoading != wasLoading {
                    if newState.isLoading { self.loadingIndicator.startAnimating() }
                    else { self.loadingIndicator.stopAnimating() }
                }

                let hasClanSection = self.collectionView.numberOfSections > 2
                let oldCount = hasClanSection ? self.collectionView.numberOfItems(inSection: 2) : 0

                let newDMBadges = newState.unreadDMs.map { $0.countMessUnread }
                let newClanBadges = newState.clans.map { $0.badgeCount }
                let badgesChanged = prevDMBadges != newDMBadges || prevClanBadges != newClanBadges
                let newDmFingerprint = Self.unreadDmStripFingerprint(newState.unreadDMs)
                let dmStripIdentityChanged = prevDmFingerprint != newDmFingerprint

                if newState.clans.count != oldCount || newState.unreadDMs.count != prevDMCount || badgesChanged {
                    self.collectionView.reloadData()
                } else if dmStripIdentityChanged {
                    if self.collectionView.numberOfSections > 1 {
                        UIView.performWithoutAnimation {
                            self.collectionView.reloadSections(IndexSet(integer: 1))
                        }
                    } else {
                        self.collectionView.reloadData()
                    }
                } else if prevClanId != newState.selectedClanId {
                    var paths: [IndexPath] = []
                    if let prev = prevClanId, let idx = newState.clans.firstIndex(where: { $0.clanID == prev }) {
                        paths.append(IndexPath(item: idx, section: 2))
                    }
                    if let curr = newState.selectedClanId, let idx = newState.clans.firstIndex(where: { $0.clanID == curr }) {
                        paths.append(IndexPath(item: idx, section: 2))
                    }
                    if !paths.isEmpty {
                        UIView.performWithoutAnimation { self.collectionView.reloadItems(at: paths) }
                    }
                }
            })
        )
    }

    deinit { disposables.dispose() }

    override func didLoad() {
        super.didLoad()

        layer.addSublayer(gradientLayer)

        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(ClanCell.self, forCellWithReuseIdentifier: ClanCell.reuseID)
        collectionView.register(LogoCell.self, forCellWithReuseIdentifier: LogoCell.reuseID)
        collectionView.register(UnreadDMBadgeCell.self, forCellWithReuseIdentifier: UnreadDMBadgeCell.reuseID)
        collectionView.register(UICollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "separator")
        collectionView.dataSource = self
        collectionView.delegate = self

        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(collectionView)
        view.addSubview(loadingIndicator)
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        let topY = layout.safeInsets.top + 6.sh
        let centerX = layout.size.width / 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = CGRect(origin: .zero, size: layout.size)
        CATransaction.commit()

        transition.updateFrame(view: collectionView, frame: CGRect(
            x: 0, y: topY, width: layout.size.width, height: layout.size.height - topY - layout.intrinsicInsets.bottom
        ))

        let liSize: CGFloat = 24.swh
        transition.updateFrame(view: loadingIndicator, frame: CGRect(
            x: centerX - liSize / 2, y: (layout.size.height - liSize) / 2, width: liSize, height: liSize
        ))
    }

    func applyTheme() {
        let t = UIColor.theme
        gradientLayer.colors = [t.primary.cgColor, t.primaryGradient.cgColor]
        backgroundColor = .clear
        loadingIndicator.color = t.textDisabled
        collectionView.reloadData()
    }

    private static func unreadDmStripFingerprint(_ dms: [Mezon_Api_ChannelDescription]) -> String {
        dms.map { dm in
            let avatarSig: String
            if dm.type == MezonConstants.ChannelType.dm.rawValue {
                avatarSig = dm.avatars.filter { !$0.isEmpty }.joined(separator: "|")
            } else {
                avatarSig = dm.channelAvatar
            }
            return "\(dm.channelID)|\(dm.type)|\(dm.countMessUnread)|\(avatarSig)|\(dm.channelLabel)"
        }.joined(separator: "\u{1e}")
    }

    @objc private func logoTapped() { interaction.onLogoTapped() }
}

extension ClanListContainerNode: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    func numberOfSections(in collectionView: UICollectionView) -> Int { 3 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return state.unreadDMs.count
        case 2: return state.clans.count
        default: return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.section == 0 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: LogoCell.reuseID, for: indexPath) as! LogoCell
            cell.onTap = { [weak self] in self?.interaction.onLogoTapped() }
            return cell
        }
        if indexPath.section == 1 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: UnreadDMBadgeCell.reuseID, for: indexPath) as! UnreadDMBadgeCell
            let dm = state.unreadDMs[indexPath.item]
            cell.configure(with: dm)
            return cell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ClanCell.reuseID, for: indexPath) as! ClanCell
        let clan = state.clans[indexPath.item]
        cell.configure(with: clan, isSelected: clan.clanID == state.selectedClanId)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            interaction.onLogoTapped()
        } else if indexPath.section == 1 {
            interaction.onSelectDM(state.unreadDMs[indexPath.item])
        } else {
            interaction.onSelectClan(state.clans[indexPath.item])
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: Self.iconSize, height: Self.iconSize)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let sideInset = (collectionView.bounds.width - Self.iconSize) / 2
        if section == 0 {
            return UIEdgeInsets(top: 6.sh, left: sideInset, bottom: 0, right: sideInset)
        }
        if section == 1 {
            return state.unreadDMs.isEmpty
                ? .zero
                : UIEdgeInsets(top: 4.sh, left: sideInset, bottom: 0, right: sideInset)
        }
        return UIEdgeInsets(top: 0, left: sideInset, bottom: 80.sh, right: sideInset)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        16.sh
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize {
        if section == 0 || (section == 1 && !state.unreadDMs.isEmpty) {
            return CGSize(width: collectionView.bounds.width, height: 16.sh)
        }
        return .zero
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        if kind == UICollectionView.elementKindSectionFooter && (indexPath.section == 0 || (indexPath.section == 1 && !state.unreadDMs.isEmpty)) {
            let footer = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "separator", for: indexPath)
            if footer.subviews.count <= 1 {
                let line = UIView()
                line.backgroundColor = UIColor.theme.border.withAlphaComponent(0.3)
                line.translatesAutoresizingMaskIntoConstraints = false
                footer.addSubview(line)
                NSLayoutConstraint.activate([
                    line.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
                    line.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
                    line.widthAnchor.constraint(equalTo: footer.widthAnchor, multiplier: 0.5),
                    line.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
                ])
            }
            return footer
        }
        return UICollectionReusableView()
    }
}

private final class LogoCell: UICollectionViewCell {
    static let reuseID = "LogoCell"

    var onTap: (() -> Void)?

    private let logoImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .clear
        iv.layer.cornerRadius = 12.swh
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(logoImageView)
        let sz = ClanListContainerNode.iconSize
        NSLayoutConstraint.activate([
            logoImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            logoImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            logoImageView.widthAnchor.constraint(equalToConstant: sz),
            logoImageView.heightAnchor.constraint(equalToConstant: sz),
        ])
        logoImageView.image = UIImage(named: "MezonLogo")
    }

    required init?(coder: NSCoder) { fatalError() }
}

private final class ClanCell: UICollectionViewCell {

    static let reuseID = "ClanCell"

    private let indicatorBar: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 2.swh
        v.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let avatarContainer: UIView = {
        let v = UIView()
        v.clipsToBounds = true
        v.layer.cornerRadius = 8.swh
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let initialsLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        l.textColor = .white
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let badgeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 9.sf, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.backgroundColor = UIColor.mezonUnreadBadge
        l.layer.cornerRadius = 10.swh
        l.clipsToBounds = true
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isHidden = true
        return l
    }()

    private var imageTask: URLSessionDataTask?
    private static let sz: CGFloat = ClanListContainerNode.iconSize

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        let sz = Self.sz
        contentView.addSubview(indicatorBar)
        contentView.addSubview(avatarContainer)
        avatarContainer.addSubview(avatarImageView)
        avatarContainer.addSubview(initialsLabel)
        contentView.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            indicatorBar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            indicatorBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: -12.sw),
            indicatorBar.widthAnchor.constraint(equalToConstant: 4.sw),
            indicatorBar.heightAnchor.constraint(equalToConstant: 32.sh),

            avatarContainer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            avatarContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarContainer.widthAnchor.constraint(equalToConstant: sz),
            avatarContainer.heightAnchor.constraint(equalToConstant: sz),

            avatarImageView.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor),

            initialsLabel.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor),

            badgeLabel.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor, constant: 5.swh),
            badgeLabel.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor, constant: 5.swh),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 20.swh),
            badgeLabel.heightAnchor.constraint(equalToConstant: 20.swh),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        avatarImageView.image = nil
        initialsLabel.text = nil
        avatarContainer.backgroundColor = .clear
        badgeLabel.isHidden = true
        badgeLabel.layer.borderWidth = 0
        badgeLabel.layer.borderColor = nil
    }

    func configure(with clan: Mezon_Api_ClanDesc, isSelected: Bool) {
        avatarContainer.layer.cornerRadius = 8.swh

        let accentColor = UIColor(red: 0.44, green: 0.42, blue: 0.95, alpha: 1)
        indicatorBar.backgroundColor = accentColor
        indicatorBar.isHidden = !isSelected

        initialsLabel.text = initials(for: clan.clanName)

        if !clan.logo.isEmpty, let url = URL(string: clan.logo) {
            avatarContainer.backgroundColor = .clear
            avatarImageView.isHidden = false
            initialsLabel.isHidden = true
            loadImage(url: url)
        } else {
            avatarContainer.backgroundColor = colorFor(name: clan.clanName)
            avatarImageView.isHidden = true
            initialsLabel.isHidden = false
        }

        let count = clan.badgeCount
        if count > 0 {
            badgeLabel.text = count > 99 ? "99+" : "\(count)"
            badgeLabel.isHidden = false
            badgeLabel.backgroundColor = UIColor.mezonUnreadBadge
        } else {
            badgeLabel.isHidden = true
            badgeLabel.layer.borderWidth = 0
            badgeLabel.layer.borderColor = nil
        }
    }

    private func loadImage(url: URL) {
        let urlString = ImgproxyURL.create(from: url.absoluteString)
        if let cached = ImageCache.shared.cachedImage(forURL: urlString) {
            avatarImageView.image = cached
            return
        }
        imageTask = ImageCache.shared.loadImage(urlString: urlString) { [weak self] image in
            self?.avatarImageView.image = image
        }
    }

    private func initials(for name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first }.map { String($0).uppercased() }.joined()
    }

    private func colorFor(name: String) -> UIColor {
        let colors: [UIColor] = [
            UIColor(red: 0.36, green: 0.36, blue: 0.82, alpha: 1),
            UIColor(red: 0.23, green: 0.56, blue: 0.42, alpha: 1),
            UIColor(red: 0.72, green: 0.26, blue: 0.26, alpha: 1),
            UIColor(red: 0.75, green: 0.52, blue: 0.18, alpha: 1),
            UIColor(red: 0.32, green: 0.52, blue: 0.78, alpha: 1),
            UIColor(red: 0.55, green: 0.28, blue: 0.68, alpha: 1),
        ]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}

private final class UnreadDMBadgeCell: UICollectionViewCell {

    static let reuseID = "UnreadDMBadgeCell"

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let initialsLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        l.textColor = .white
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let avatarContainer: UIView = {
        let v = UIView()
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let badgeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 9.sf, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.backgroundColor = UIColor.mezonUnreadBadge
        l.clipsToBounds = true
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isHidden = true
        return l
    }()

    private var imageTask: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        let sz = ClanListContainerNode.iconSize
        let radius = sz / 2

        contentView.addSubview(avatarContainer)
        avatarContainer.addSubview(avatarImageView)
        avatarContainer.addSubview(initialsLabel)
        contentView.addSubview(badgeLabel)

        avatarContainer.layer.cornerRadius = radius
        badgeLabel.layer.cornerRadius = 10.swh

        NSLayoutConstraint.activate([
            avatarContainer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            avatarContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarContainer.widthAnchor.constraint(equalToConstant: sz),
            avatarContainer.heightAnchor.constraint(equalToConstant: sz),

            avatarImageView.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor),

            initialsLabel.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor),

            badgeLabel.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor, constant: 5.swh),
            badgeLabel.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor, constant: 5.swh),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 20.swh),
            badgeLabel.heightAnchor.constraint(equalToConstant: 20.swh),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        avatarImageView.image = nil
        initialsLabel.text = nil
        avatarContainer.backgroundColor = .clear
        badgeLabel.isHidden = true
        badgeLabel.layer.borderWidth = 0
        badgeLabel.layer.borderColor = nil
    }

    func configure(with dm: Mezon_Api_ChannelDescription) {
        let name = dm.channelLabel.isEmpty ? "DM" : dm.channelLabel
        let colors: [UIColor] = [
            UIColor(red: 0.36, green: 0.36, blue: 0.82, alpha: 1),
            UIColor(red: 0.23, green: 0.56, blue: 0.42, alpha: 1),
            UIColor(red: 0.72, green: 0.26, blue: 0.26, alpha: 1),
            UIColor(red: 0.32, green: 0.52, blue: 0.78, alpha: 1),
            UIColor(red: 0.55, green: 0.28, blue: 0.68, alpha: 1),
        ]
        let placeholderBg = colors[abs(name.hashValue) % colors.count]

        let isDM = dm.type == MezonConstants.ChannelType.dm.rawValue
        let avatarURL: String
        if isDM {
            avatarURL = dm.avatars.first(where: { !$0.isEmpty }) ?? ""
        } else {
            let groupAvatar = dm.channelAvatar
            avatarURL = (!groupAvatar.isEmpty && !groupAvatar.contains("avatar-group")) ? groupAvatar : ""
        }

        if !avatarURL.isEmpty {
            avatarContainer.backgroundColor = .clear
            let proxyURL = ImgproxyURL.create(from: avatarURL)
            avatarImageView.isHidden = false
            initialsLabel.isHidden = true
            if let cached = ImageCache.shared.cachedImage(forURL: proxyURL) {
                avatarImageView.image = cached
            } else {
                imageTask = ImageCache.shared.loadImage(urlString: proxyURL) { [weak self] image in
                    self?.avatarImageView.image = image
                }
            }
        } else {
            avatarContainer.backgroundColor = placeholderBg
            avatarImageView.isHidden = true
            initialsLabel.isHidden = false
            initialsLabel.text = String(name.prefix(1)).uppercased()
        }

        let count = dm.countMessUnread
        if count > 0 {
            badgeLabel.text = count > 99 ? "99+" : "\(count)"
            badgeLabel.isHidden = false
            badgeLabel.backgroundColor = UIColor.mezonUnreadBadge
        } else {
            badgeLabel.isHidden = true
            badgeLabel.layer.borderWidth = 0
            badgeLabel.layer.borderColor = nil
        }
    }
}
