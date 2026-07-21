import UIKit
import AsyncDisplayKit

private let sidebarAvatarLoadRetryDelays: [TimeInterval] = [1.5, 4, 10, 20]

struct ClanListInteraction {
    let onSelectClan: (Mezon_Api_ClanDesc) -> Void
    let onSelectDM: (Mezon_Api_ChannelDescription) -> Void
    let onLogoTapped: () -> Void
    let onJoinClanTapped: () -> Void
    let onCreateClanTapped: () -> Void
}

final class ClanListContainerNode: ASDisplayNode {

    private static let trailingClanActionCount = 2

    static let iconSize: CGFloat = 42.swh
    static let logoImageWidth: CGFloat = 42.swh
    static let logoImageHeight: CGFloat = 42.swh

    private let collectionView: UICollectionView
    private let logoHeaderView = UIView()
    private let logoImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .clear
        iv.layer.cornerRadius = 12.swh
        iv.translatesAutoresizingMaskIntoConstraints = true
        iv.autoresizingMask = []
        iv.isUserInteractionEnabled = true
        return iv
    }()
    private let logoSeparatorLine: UIView = {
        let line = UIView()
        line.translatesAutoresizingMaskIntoConstraints = true
        line.autoresizingMask = []
        return line
    }()
    private lazy var gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.startPoint = CGPoint(x: 0.5, y: 0)
        gl.endPoint   = CGPoint(x: 0.5, y: 1)
        return gl
    }()

    private var state: ClanListState = .empty
    private let interaction: ClanListInteraction
    private let disposables = DisposableSet()
    private var sidebarLogoLoadTask: URLSessionDataTask?
    private var sidebarLogoDisplaySource: String?

    init(signal: Signal<ClanListState, NoError>, interaction: ClanListInteraction) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 16.sh
        layout.itemSize = CGSize(width: Self.iconSize, height: Self.iconSize)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.interaction = interaction
        super.init()

        applySidebarAccountLogo(urlString: nil)

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                let prevState = self.state
                let prevDMs = prevState.unreadDMs
                let prevDmFingerprint = Self.unreadDmStripFingerprint(prevDMs)
                let prevClanId = prevState.selectedClanId
                let prevClanBadges = prevState.clans.map { $0.badgeCount }
                let prevClanFingerprints = prevState.clans.map { "\($0.clanID)-\($0.clanName)-\($0.logo)" }
                let prevAccountLogo = prevState.accountLogoURL

                if prevAccountLogo != newState.accountLogoURL {
                    self.applySidebarAccountLogo(urlString: newState.accountLogoURL)
                }

                let hasClanSection = self.collectionView.numberOfSections > 1
                let oldCount = hasClanSection ? self.collectionView.numberOfItems(inSection: 1) : 0
                let newClanSectionCount = newState.clans.count + Self.trailingClanActionCount

                let newClanBadges = newState.clans.map { $0.badgeCount }
                let newClanFingerprints = newState.clans.map { "\($0.clanID)-\($0.clanName)-\($0.logo)" }
                let clansChanged = prevClanFingerprints != newClanFingerprints
                let newDmFingerprint = Self.unreadDmStripFingerprint(newState.unreadDMs)

                let clanStructureChanged = newClanSectionCount != oldCount || clansChanged || prevClanBadges != newClanBadges
                let dmIdentityChanged = prevDMs.map(\.channelID) != newState.unreadDMs.map(\.channelID)
                let dmContentChanged = prevDmFingerprint != newDmFingerprint

                if clanStructureChanged {
                    self.state = newState
                    self.collectionView.reloadData()
                } else if dmIdentityChanged {
                    self.applyDmStripIdentityChange(prevDMs: prevDMs, newState: newState)
                } else if dmContentChanged {
                    self.state = newState
                    if self.collectionView.numberOfSections > 0 {
                        UIView.performWithoutAnimation {
                            self.collectionView.reloadSections(IndexSet(integer: 0))
                        }
                    } else {
                        self.collectionView.reloadData()
                    }
                } else if prevClanId != newState.selectedClanId {
                    self.state = newState
                    var paths: [IndexPath] = []
                    if let prev = prevClanId, let idx = newState.clans.firstIndex(where: { $0.clanID == prev }) {
                        paths.append(IndexPath(item: idx, section: 1))
                    }
                    if let curr = newState.selectedClanId, let idx = newState.clans.firstIndex(where: { $0.clanID == curr }) {
                        paths.append(IndexPath(item: idx, section: 1))
                    }
                    if !paths.isEmpty {
                        UIView.performWithoutAnimation { self.collectionView.reloadItems(at: paths) }
                    }
                } else {
                    self.state = newState
                }
            })
        )
    }

    deinit {
        sidebarLogoLoadTask?.cancel()
        disposables.dispose()
    }

    override func didLoad() {
        super.didLoad()

        layer.addSublayer(gradientLayer)

        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(ClanCell.self, forCellWithReuseIdentifier: ClanCell.reuseID)
        collectionView.register(ClanJoinActionCell.self, forCellWithReuseIdentifier: ClanJoinActionCell.reuseID)
        collectionView.register(ClanCreateActionCell.self, forCellWithReuseIdentifier: ClanCreateActionCell.reuseID)
        collectionView.register(UnreadDMBadgeCell.self, forCellWithReuseIdentifier: UnreadDMBadgeCell.reuseID)
        collectionView.register(UICollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "separator")
        collectionView.dataSource = self
        collectionView.delegate = self

        logoHeaderView.translatesAutoresizingMaskIntoConstraints = false
        logoHeaderView.backgroundColor = .clear
        logoHeaderView.clipsToBounds = false
        logoHeaderView.addSubview(logoImageView)
        logoHeaderView.addSubview(logoSeparatorLine)
        let logoTap = UITapGestureRecognizer(target: self, action: #selector(logoTapped))
        logoImageView.addGestureRecognizer(logoTap)

        view.addSubview(collectionView)
        view.addSubview(logoHeaderView)
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        view.layoutIfNeeded()
        let topY: CGFloat = 0
        let contentWidth = effectiveContentDimension(layoutSize: layout.size.width, viewDimension: view.bounds.width)
        let containerHeight = effectiveContentDimension(layoutSize: layout.size.height, viewDimension: view.bounds.height)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = CGRect(origin: .zero, size: CGSize(width: contentWidth, height: containerHeight))
        CATransaction.commit()

        let logoTopPad: CGFloat = 0
        let logoHeaderHeight = logoTopPad + Self.logoImageHeight + 16.sh
        transition.updateFrame(view: logoHeaderView, frame: CGRect(
            x: 0, y: topY, width: contentWidth, height: logoHeaderHeight
        ))

        let logoX = (contentWidth - Self.logoImageWidth) / 2
        logoImageView.frame = CGRect(
            x: logoX, y: logoTopPad, width: Self.logoImageWidth, height: Self.logoImageHeight
        )
        let sepScale = 1.0 / UIScreen.main.scale
        let sepW = contentWidth * 0.5
        let sepY = logoHeaderHeight - 8.sh - sepScale / 2
        logoSeparatorLine.frame = CGRect(
            x: (contentWidth - sepW) / 2, y: sepY, width: sepW, height: sepScale
        )

        transition.updateFrame(view: collectionView, frame: CGRect(
            x: 0, y: topY + logoHeaderHeight, width: contentWidth,
            height: containerHeight - topY - logoHeaderHeight - layout.intrinsicInsets.bottom
        ))
        collectionView.collectionViewLayout.invalidateLayout()
    }

    private func effectiveContentDimension(layoutSize: CGFloat, viewDimension: CGFloat) -> CGFloat {
        if viewDimension > 0.5 {
            return viewDimension
        }
        return max(1, layoutSize)
    }

    private func applySidebarAccountLogo(urlString: String?) {
        sidebarLogoLoadTask?.cancel()
        sidebarLogoLoadTask = nil
        let trimmed = urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedURL = trimmed.isEmpty ? MezonConstants.defaultDMLogoURL : trimmed
        guard URL(string: resolvedURL) != nil else {
            sidebarLogoDisplaySource = nil
            logoImageView.image = nil
            return
        }
        sidebarLogoDisplaySource = resolvedURL
        let proxied = resolvedURL == MezonConstants.defaultDMLogoURL
            ? resolvedURL
            : ImgproxyURL.create(from: resolvedURL, width: 150, height: 150)
        if let cached = ImageCache.shared.cachedImage(forURL: proxied) {
            logoImageView.image = cached
            return
        }
        logoImageView.image = nil
        loadSidebarAccountLogo(trimmed: resolvedURL, proxied: proxied, attempt: 0)
    }

    private func loadSidebarAccountLogo(trimmed: String, proxied: String, attempt: Int) {
        sidebarLogoLoadTask = ImageCache.shared.loadImage(urlString: proxied) { [weak self] image in
            guard let self else { return }
            guard self.sidebarLogoDisplaySource == trimmed else { return }
            if let image {
                self.logoImageView.image = image
            } else if attempt < sidebarAvatarLoadRetryDelays.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + sidebarAvatarLoadRetryDelays[attempt]) { [weak self] in
                    guard let self else { return }
                    guard self.sidebarLogoDisplaySource == trimmed else { return }
                    self.loadSidebarAccountLogo(trimmed: trimmed, proxied: proxied, attempt: attempt + 1)
                }
            }
        }
    }

    func focusDiscoverIfNoClans() {
        guard state.clans.isEmpty else { return }
        let section = 1
        guard collectionView.numberOfSections > section else { return }
        let item = state.clans.count
        let path = IndexPath(item: item, section: section)
        guard item < collectionView.numberOfItems(inSection: section) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.collectionView.scrollToItem(at: path, at: .centeredVertically, animated: true)
            self.collectionView.selectItem(at: path, animated: true, scrollPosition: .centeredVertically)
        }
    }

    func applyTheme() {
        let t = UIColor.theme
        gradientLayer.colors = [t.primary.cgColor, t.primaryGradient.cgColor]
        backgroundColor = .clear
        logoSeparatorLine.backgroundColor = t.border.withAlphaComponent(0.3)
        collectionView.reloadData()
    }

    private static func dmItemFingerprint(_ dm: Mezon_Api_ChannelDescription) -> String {
        let avatarSig: String
        if dm.type == MezonConstants.ChannelType.dm.rawValue {
            avatarSig = dm.avatars.filter { !$0.isEmpty }.joined(separator: "|")
        } else {
            avatarSig = dm.channelAvatar
        }
        return "\(dm.channelID)|\(dm.type)|\(dm.countMessUnread)|\(avatarSig)|\(dm.channelLabel)"
    }

    private static func unreadDmStripFingerprint(_ dms: [Mezon_Api_ChannelDescription]) -> String {
        dms.map { dmItemFingerprint($0) }.joined(separator: "\u{1e}")
    }

    private func applyDmStripIdentityChange(
        prevDMs: [Mezon_Api_ChannelDescription],
        newState: ClanListState
    ) {
        let newDMs = newState.unreadDMs
        guard collectionView.numberOfSections > 0,
              collectionView.numberOfItems(inSection: 0) == prevDMs.count else {
            state = newState
            collectionView.reloadData()
            return
        }
        collectionView.layoutIfNeeded()
        guard collectionView.numberOfItems(inSection: 0) == prevDMs.count else {
            state = newState
            collectionView.reloadData()
            return
        }
        state = newState
        let prevIds = prevDMs.map(\.channelID)
        let newIds = newDMs.map(\.channelID)
        let prevIdSet = Set(prevIds)
        let newIdSet = Set(newIds)
        let survivorsPrevOrder = prevIds.filter { newIdSet.contains($0) }
        let survivorsNewOrder = newIds.filter { prevIdSet.contains($0) }
        guard survivorsPrevOrder == survivorsNewOrder else {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.collectionView.performBatchUpdates {
                    self.collectionView.reloadSections(IndexSet(integer: 0))
                }
            }
            return
        }
        let deletes = prevIds.enumerated()
            .filter { !newIdSet.contains($0.element) }
            .map { IndexPath(item: $0.offset, section: 0) }
        let inserts = newIds.enumerated()
            .filter { !prevIdSet.contains($0.element) }
            .map { IndexPath(item: $0.offset, section: 0) }
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.collectionView.performBatchUpdates {
                if !deletes.isEmpty { self.collectionView.deleteItems(at: deletes) }
                if !inserts.isEmpty { self.collectionView.insertItems(at: inserts) }
            }
        }
        let prevItemById = Dictionary(prevDMs.map { ($0.channelID, $0) }, uniquingKeysWith: { _, new in new })
        var staleSurvivorPaths: [IndexPath] = []
        for (item, dm) in newDMs.enumerated() {
            guard let old = prevItemById[dm.channelID] else { continue }
            if Self.dmItemFingerprint(old) != Self.dmItemFingerprint(dm) {
                staleSurvivorPaths.append(IndexPath(item: item, section: 0))
            }
        }
        if !staleSurvivorPaths.isEmpty {
            UIView.performWithoutAnimation {
                collectionView.reloadItems(at: staleSurvivorPaths)
            }
        }
    }

    @objc private func logoTapped() { interaction.onLogoTapped() }
}

extension ClanListContainerNode: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    func numberOfSections(in collectionView: UICollectionView) -> Int { 2 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch section {
        case 0: return state.unreadDMs.count
        case 1: return state.clans.count + Self.trailingClanActionCount
        default: return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.section == 0 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: UnreadDMBadgeCell.reuseID, for: indexPath) as! UnreadDMBadgeCell
            guard indexPath.item < state.unreadDMs.count else { return cell }
            let dm = state.unreadDMs[indexPath.item]
            cell.configure(with: dm)
            return cell
        }
        let clanIndex = indexPath.item
        guard clanIndex < state.clans.count else {
            if clanIndex == state.clans.count {
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ClanJoinActionCell.reuseID, for: indexPath) as! ClanJoinActionCell
                cell.applyDiscoveryFocus(state.clans.isEmpty)
                return cell
            }
            return collectionView.dequeueReusableCell(withReuseIdentifier: ClanCreateActionCell.reuseID, for: indexPath) as! ClanCreateActionCell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ClanCell.reuseID, for: indexPath) as! ClanCell
        let clan = state.clans[clanIndex]
        cell.configure(with: clan, isSelected: clan.clanID == state.selectedClanId)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            guard indexPath.item < state.unreadDMs.count else { return }
            interaction.onSelectDM(state.unreadDMs[indexPath.item])
        } else {
            let i = indexPath.item
            guard i < state.clans.count else {
                collectionView.deselectItem(at: indexPath, animated: true)
                if i == state.clans.count { interaction.onJoinClanTapped() }
                else { interaction.onCreateClanTapped() }
                return
            }
            interaction.onSelectClan(state.clans[i])
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: Self.iconSize, height: Self.iconSize)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let sideInset = (collectionView.bounds.width - Self.iconSize) / 2
        if section == 0 {
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
        if section == 0 && !state.unreadDMs.isEmpty {
            return CGSize(width: collectionView.bounds.width, height: 16.sh)
        }
        return .zero
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        if kind == UICollectionView.elementKindSectionFooter && indexPath.section == 0 && !state.unreadDMs.isEmpty {
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

private final class ClanCell: UICollectionViewCell {

    static let reuseID = "ClanCell"

    private let indicatorBar: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 2.swh
        v.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let textAvatarView: TextAvatarView = {
        let v = TextAvatarView(username: "", size: ClanListContainerNode.iconSize, fontSize: 14.sf)
        v.layer.cornerRadius = 8.swh
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 8.swh
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
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
    private var boundClanId: Int64?
    private var avatarGeneration = 0
    private static let sz: CGFloat = ClanListContainerNode.iconSize

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        let sz = Self.sz
        contentView.addSubview(indicatorBar)
        contentView.addSubview(textAvatarView)
        contentView.addSubview(avatarImageView)
        contentView.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            indicatorBar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            indicatorBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: -12.sw),
            indicatorBar.widthAnchor.constraint(equalToConstant: 4.sw),
            indicatorBar.heightAnchor.constraint(equalToConstant: 32.sh),

            textAvatarView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            textAvatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textAvatarView.widthAnchor.constraint(equalToConstant: sz),
            textAvatarView.heightAnchor.constraint(equalToConstant: sz),

            avatarImageView.topAnchor.constraint(equalTo: textAvatarView.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: textAvatarView.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: textAvatarView.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: textAvatarView.bottomAnchor),

            badgeLabel.bottomAnchor.constraint(equalTo: textAvatarView.bottomAnchor, constant: 5.swh),
            badgeLabel.trailingAnchor.constraint(equalTo: textAvatarView.trailingAnchor, constant: 5.swh),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 20.swh),
            badgeLabel.heightAnchor.constraint(equalToConstant: 20.swh),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        boundClanId = nil
        avatarImageView.image = nil
        textAvatarView.configure(username: "")
        badgeLabel.isHidden = true
        badgeLabel.layer.borderWidth = 0
        badgeLabel.layer.borderColor = nil
    }

    func configure(with clan: Mezon_Api_ClanDesc, isSelected: Bool) {
        avatarGeneration += 1
        let generation = avatarGeneration
        boundClanId = clan.clanID
        let expectClanId = clan.clanID
        let clanName = clan.clanName

        let accentColor = UIColor(red: 0.44, green: 0.42, blue: 0.95, alpha: 1)
        indicatorBar.backgroundColor = accentColor
        indicatorBar.isHidden = !isSelected

        let resolvedLogoURL = ImgproxyURL.absoluteResourceURL(from: clan.logo)
        if !resolvedLogoURL.isEmpty {
            avatarImageView.isHidden = false
            loadExpectingClan(
                clanId: expectClanId, generation: generation, clanName: clanName, sourceURL: resolvedLogoURL)
        } else {
            textAvatarView.configure(username: clanName, fontSize: 14.sf)
            avatarImageView.isHidden = true
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

    private func loadExpectingClan(clanId: Int64, generation: Int, clanName: String, sourceURL: String, attempt: Int = 0) {
        imageTask?.cancel()
        imageTask = nil
        let urlString = ImgproxyURL.create(from: sourceURL, width: 150, height: 150)
        if let cached = ImageCache.shared.cachedImage(forURL: urlString) {
            guard boundClanId == clanId, avatarGeneration == generation else { return }
            avatarImageView.image = cached
            avatarImageView.isHidden = false
            textAvatarView.showImageMode()
            contentView.layoutIfNeeded()
            return
        }
        avatarImageView.image = nil
        textAvatarView.configure(username: clanName, fontSize: 14.sf)
        imageTask = ImageCache.shared.loadImage(urlString: urlString) { [weak self] image in
            guard let self else { return }
            guard self.boundClanId == clanId, self.avatarGeneration == generation else { return }
            if let image {
                self.avatarImageView.image = image
                self.avatarImageView.isHidden = false
                self.textAvatarView.showImageMode()
                self.contentView.setNeedsLayout()
                self.contentView.layoutIfNeeded()
            } else if attempt < sidebarAvatarLoadRetryDelays.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + sidebarAvatarLoadRetryDelays[attempt]) { [weak self] in
                    guard let self else { return }
                    guard self.boundClanId == clanId, self.avatarGeneration == generation else { return }
                    self.loadExpectingClan(
                        clanId: clanId, generation: generation, clanName: clanName,
                        sourceURL: sourceURL, attempt: attempt + 1)
                }
            } else {
                self.avatarImageView.isHidden = true
                self.textAvatarView.configure(username: clanName, fontSize: 14.sf)
                self.contentView.setNeedsLayout()
                self.contentView.layoutIfNeeded()
            }
        }
    }
}

private final class ClanJoinActionCell: UICollectionViewCell {

    static let reuseID = "ClanJoinActionCell"

    private let outer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 8.swh
        v.layer.borderWidth = 0
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.image = UIImage(named: "ClanSetting/JoinClanIcon")?.withRenderingMode(.alwaysOriginal)
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private var discoveryFocused = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        let sz = ClanListContainerNode.iconSize
        contentView.addSubview(outer)
        outer.addSubview(iconView)
        NSLayoutConstraint.activate([
            outer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            outer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            outer.widthAnchor.constraint(equalToConstant: sz),
            outer.heightAnchor.constraint(equalToConstant: sz),
            iconView.topAnchor.constraint(equalTo: outer.topAnchor),
            iconView.leadingAnchor.constraint(equalTo: outer.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: outer.trailingAnchor),
            iconView.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyDiscoveryFocus(_ focused: Bool) {
        discoveryFocused = focused
        refreshOuterAppearance()
    }

    private func refreshOuterAppearance() {
        let t = UIColor.theme
        outer.layer.borderWidth = 0
        outer.layer.borderColor = nil
        if discoveryFocused {
            outer.backgroundColor = t.iconPrimary.withAlphaComponent(0.22)
        } else {
            outer.backgroundColor = t.primary.withAlphaComponent(0.2)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshOuterAppearance()
    }
}

private final class ClanCreateActionCell: UICollectionViewCell {

    static let reuseID = "ClanCreateActionCell"

    private let outer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 8.swh
        v.layer.borderWidth = 0
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let iconView: UIImageView = {
        let iv = UIImageView()
        let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        iv.image = UIImage(systemName: "plus", withConfiguration: cfg)?.withRenderingMode(.alwaysTemplate)
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        let sz = ClanListContainerNode.iconSize
        contentView.addSubview(outer)
        outer.addSubview(iconView)
        NSLayoutConstraint.activate([
            outer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            outer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            outer.widthAnchor.constraint(equalToConstant: sz),
            outer.heightAnchor.constraint(equalToConstant: sz),
            iconView.centerXAnchor.constraint(equalTo: outer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: outer.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let t = UIColor.theme
        iconView.tintColor = t.iconPrimary
        outer.backgroundColor = t.iconPrimary.withAlphaComponent(0.28)
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

    private let groupIconView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "person.2.fill"))
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .white
        iv.isHidden = true
        return iv
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
    private var boundChannelId: Int64?
    private var dmAvatarGeneration = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        let sz = ClanListContainerNode.iconSize
        let radius = sz / 2

        contentView.addSubview(avatarContainer)
        avatarContainer.addSubview(avatarImageView)
        avatarContainer.addSubview(initialsLabel)
        avatarContainer.addSubview(groupIconView)
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

            groupIconView.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            groupIconView.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor),
            groupIconView.widthAnchor.constraint(equalToConstant: 20.swh),
            groupIconView.heightAnchor.constraint(equalToConstant: 20.swh),

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
        imageTask = nil
        boundChannelId = nil
        avatarImageView.image = nil
        initialsLabel.text = nil
        groupIconView.isHidden = true
        avatarContainer.backgroundColor = .clear
        badgeLabel.isHidden = true
        badgeLabel.layer.borderWidth = 0
        badgeLabel.layer.borderColor = nil
    }

    func configure(with dm: Mezon_Api_ChannelDescription) {
        dmAvatarGeneration += 1
        let generation = dmAvatarGeneration
        let expectChannelId = dm.channelID
        boundChannelId = expectChannelId

        let isDM = dm.type == MezonConstants.ChannelType.dm.rawValue
        let username = dm.usernames.first ?? ""
        let avatarSeed = username
        let name = avatarSeed
        let placeholderBg = UIColor.avatarColor(for: avatarSeed)

        let avatarURL: String
        if isDM {
            avatarURL = dm.avatars.first(where: { !$0.isEmpty }) ?? ""
        } else {
            let groupAvatar = dm.channelAvatar
            avatarURL = (!groupAvatar.isEmpty && !groupAvatar.contains("avatar-group.png")) ? groupAvatar : ""
        }
        let resolvedAvatarURL = ImgproxyURL.absoluteResourceURL(from: avatarURL)

        if !resolvedAvatarURL.isEmpty {
            groupIconView.isHidden = true
            avatarContainer.backgroundColor = .clear
            let proxyURL = ImgproxyURL.create(from: resolvedAvatarURL, width: 150, height: 150)
            avatarImageView.isHidden = false
            initialsLabel.isHidden = true
            imageTask?.cancel()
            imageTask = nil
            if let cached = ImageCache.shared.cachedImage(forURL: proxyURL) {
                guard boundChannelId == expectChannelId, dmAvatarGeneration == generation else { return }
                avatarImageView.image = cached
                contentView.layoutIfNeeded()
            } else {
                avatarImageView.image = nil
                loadDmAvatar(
                    proxyURL: proxyURL, expectChannelId: expectChannelId, generation: generation,
                    isDM: isDM, placeholderBg: placeholderBg, name: name, attempt: 0)
            }
        } else {
            avatarImageView.isHidden = true
            applyDmAvatarFallback(isDM: isDM, placeholderBg: placeholderBg, name: name)
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

    private func loadDmAvatar(
        proxyURL: String, expectChannelId: Int64, generation: Int,
        isDM: Bool, placeholderBg: UIColor, name: String, attempt: Int
    ) {
        imageTask = ImageCache.shared.loadImage(urlString: proxyURL) { [weak self] image in
            guard let self else { return }
            guard self.boundChannelId == expectChannelId, self.dmAvatarGeneration == generation else { return }
            if let image {
                self.avatarImageView.image = image
                self.avatarImageView.isHidden = false
                self.initialsLabel.isHidden = true
                self.contentView.setNeedsLayout()
                self.contentView.layoutIfNeeded()
            } else if attempt < sidebarAvatarLoadRetryDelays.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + sidebarAvatarLoadRetryDelays[attempt]) { [weak self] in
                    guard let self else { return }
                    guard self.boundChannelId == expectChannelId, self.dmAvatarGeneration == generation else { return }
                    self.loadDmAvatar(
                        proxyURL: proxyURL, expectChannelId: expectChannelId, generation: generation,
                        isDM: isDM, placeholderBg: placeholderBg, name: name, attempt: attempt + 1)
                }
            } else {
                self.applyDmAvatarFallback(isDM: isDM, placeholderBg: placeholderBg, name: name)
                self.contentView.setNeedsLayout()
                self.contentView.layoutIfNeeded()
            }
        }
    }

    private func applyDmAvatarFallback(isDM: Bool, placeholderBg: UIColor, name: String) {
        avatarImageView.isHidden = true
        if isDM {
            groupIconView.isHidden = true
            avatarContainer.backgroundColor = placeholderBg
            initialsLabel.isHidden = false
            initialsLabel.text = String(name.prefix(1)).uppercased()
        } else {
            avatarContainer.backgroundColor = .groupDMDefaultAvatar
            initialsLabel.isHidden = true
            groupIconView.tintColor = .white
            groupIconView.isHidden = false
        }
    }
}
