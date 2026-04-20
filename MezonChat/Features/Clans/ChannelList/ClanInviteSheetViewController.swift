import AsyncDisplayKit
import CoreImage
import UIKit

private final class ClanInviteSearchWrapNode: ASDisplayNode {
    let textField = UITextField()
    let clearButton = UIButton(type: .system)
    private let iconView = UIImageView(image: UIImage(systemName: "magnifyingglass"))

    override init() {
        super.init()
        backgroundColor = UIColor.theme.secondary
        cornerRadius = 8.swh
        clipsToBounds = true
    }

    override func didLoad() {
        super.didLoad()
        iconView.tintColor = UIColor.theme.textDisabled
        view.addSubview(iconView)

        textField.placeholder = L(L10n.ClanInviteSheet.searchPlaceholder)
        textField.borderStyle = .none
        textField.font = .systemFont(ofSize: 15.sf, weight: .regular)
        textField.clearButtonMode = .never
        view.addSubview(textField)

        clearButton.setImage(
            UIImage(systemName: "xmark.circle.fill")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 16.sf, weight: .regular)
            ),
            for: .normal
        )
        clearButton.isHidden = true
        view.addSubview(clearButton)
    }

    override func layout() {
        super.layout()
        let b = bounds
        let iconSize: CGFloat = 18.swh
        let clearSize: CGFloat = 24.swh

        iconView.frame = CGRect(
            x: 8.sw,
            y: (b.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        clearButton.frame = CGRect(
            x: b.width - 8.sw - clearSize,
            y: (b.height - clearSize) / 2,
            width: clearSize,
            height: clearSize
        )
        textField.frame = CGRect(
            x: iconView.frame.maxX + 8.sw,
            y: 0,
            width: clearButton.frame.minX - 4.sw - iconView.frame.maxX - 8.sw,
            height: b.height
        )
    }

    func applyTheme() {
        backgroundColor = UIColor.theme.secondary
        iconView.tintColor = UIColor.theme.textDisabled
        textField.textColor = UIColor.theme.textStrong
        textField.tintColor = UIColor.theme.textDisabled
        clearButton.tintColor = UIColor.theme.textStrong
        textField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.ClanInviteSheet.searchPlaceholder),
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )
    }
}

private final class ClanInviteActionButtonNode: ASDisplayNode {
    private let iconWrapNode = ASDisplayNode()
    private let iconNode = ASImageNode()
    private let labelNode = ASTextNode()
    var onTap: (() -> Void)?

    init(iconAsset: String, fallbackSystemIcon: String, title: String) {
        super.init()
        automaticallyManagesSubnodes = false

        iconWrapNode.isLayerBacked = true
        iconNode.isLayerBacked = true
        labelNode.isLayerBacked = true

        iconWrapNode.backgroundColor = UIColor.theme.secondary
        iconWrapNode.cornerRadius = 20.swh
        iconWrapNode.clipsToBounds = true

        let img = UIImage(named: iconAsset)?.withRenderingMode(.alwaysTemplate)
            ?? UIImage(systemName: fallbackSystemIcon)?.withRenderingMode(.alwaysTemplate)
        iconNode.image = img
        iconNode.tintColor = UIColor.theme.textStrong
        iconNode.contentMode = .scaleAspectFit

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        labelNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.sf * 0.75, weight: .regular),
                .foregroundColor: UIColor.theme.text,
                .paragraphStyle: para,
            ]
        )
        
        addSubnode(iconWrapNode)
        addSubnode(iconNode)
        addSubnode(labelNode)
    }

    override func didLoad() {
        super.didLoad()
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    @objc private func handleTap() { onTap?() }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        let labelSz = labelNode.calculateSizeThatFits(CGSize(width: 200, height: 40))
        let maxW = max(40.swh, labelSz.width)
        return CGSize(width: maxW, height: 62.sh) 
    }

    override func layout() {
        super.layout()
        let b = bounds
        
        let iconSz: CGFloat = 40.swh
        let iconFrame = CGRect(x: (b.width - iconSz) / 2, y: 0, width: iconSz, height: iconSz)
        iconWrapNode.frame = iconFrame
        
        let innerIconSz: CGFloat = 24.swh
        iconNode.frame = CGRect(
            x: iconFrame.minX + (iconSz - innerIconSz) / 2,
            y: iconFrame.minY + (iconSz - innerIconSz) / 2,
            width: innerIconSz,
            height: innerIconSz
        )
        
        let labelSz = labelNode.calculateSizeThatFits(CGSize(width: b.width, height: 20))
        labelNode.frame = CGRect(
            x: (b.width - labelSz.width) / 2,
            y: iconFrame.maxY + 6.sh,
            width: labelSz.width,
            height: labelSz.height
        )
    }
}

private final class ClanInviteEmptyStateNode: ASDisplayNode {
    private let imageNode = ASImageNode()
    private let titleNode = ASTextNode()
    private let descriptionNode = ASTextNode()
    let actionButtonNode = ASButtonNode()

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        isHidden = true

        imageNode.isLayerBacked = true
        titleNode.isLayerBacked = true
        descriptionNode.isLayerBacked = true

        imageNode.image = UIImage(named: "Invite/EmptyFriendIcon", in: .main, compatibleWith: nil)?
            .withRenderingMode(.alwaysOriginal)
        imageNode.contentMode = .scaleAspectFit
        imageNode.style.preferredSize = CGSize(width: 96.swh, height: 96.swh)
        updateText()
    }

    private func updateText() {
        let center = NSMutableParagraphStyle()
        center.alignment = .center

        titleNode.attributedText = NSAttributedString(
            string: L(L10n.ClanInviteSheet.emptyTitle),
            attributes: [
                .font: UIFont.systemFont(ofSize: 30.sf * 0.6, weight: .bold),
                .foregroundColor: UIColor.theme.textStrong,
                .paragraphStyle: center,
            ]
        )
        titleNode.maximumNumberOfLines = 2

        descriptionNode.attributedText = NSAttributedString(
            string: L(L10n.ClanInviteSheet.emptyDescription),
            attributes: [
                .font: UIFont.systemFont(ofSize: 24.sf * 0.6, weight: .regular),
                .foregroundColor: UIColor.theme.textDisabled,
                .paragraphStyle: center,
            ]
        )
        descriptionNode.maximumNumberOfLines = 0

        actionButtonNode.setTitle(
            L(L10n.ClanInviteSheet.emptyAction),
            with: .systemFont(ofSize: 14.sf, weight: .semibold),
            with: UIColor.theme.textLink,
            for: .normal
        )
    }

    func applyTheme() { updateText() }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let topStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 10.sh,
            justifyContent: .center,
            alignItems: .center,
            children: [imageNode, titleNode, descriptionNode]
        )
        let outerStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 14.sh,
            justifyContent: .center,
            alignItems: .center,
            children: [topStack, actionButtonNode]
        )
        let inset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 24.sw, bottom: 0, right: 24.sw),
            child: outerStack
        )
        return ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: .minimumXY, child: inset)
    }
}

private final class ClanInviteFriendCellNode: ASCellNode {
    var onInvite: (() -> Void)?

    private let avatarBgNode = ASDisplayNode()
    private let avatarNode = ASNetworkImageNode()
    private let initialNode = ASTextNode()
    private let groupIconNode = ASImageNode()
    private let nameNode = ASTextNode()
    private let inviteButtonNode = ASButtonNode()
    private let spinnerWrapNode: ASDisplayNode

    private enum AvatarMode { case image, group, initial }
    private let avatarMode: AvatarMode
    private let needsSpinner: Bool

    init(name: String, avatarURL: String?, isGroupDM: Bool, isSent: Bool, isLoading: Bool) {
        self.needsSpinner = isLoading

        spinnerWrapNode = ASDisplayNode { () -> UIView in
            let sp = UIActivityIndicatorView(style: .medium)
            sp.hidesWhenStopped = true
            if isLoading {
                sp.startAnimating()
            }
            return sp
        }

        if let avatarURL, !avatarURL.isEmpty {
            avatarMode = .image
        } else if isGroupDM {
            avatarMode = .group
        } else {
            avatarMode = .initial
        }

        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .clear

        avatarBgNode.isLayerBacked = true
        avatarNode.isLayerBacked = true
        initialNode.isLayerBacked = true
        groupIconNode.isLayerBacked = true
        nameNode.isLayerBacked = true

        let avatarSize: CGFloat = 40.swh
        avatarBgNode.cornerRadius = avatarSize / 2
        avatarBgNode.clipsToBounds = true

        avatarNode.cornerRadius = avatarSize / 2
        avatarNode.clipsToBounds = true
        avatarNode.contentMode = .scaleAspectFill

        groupIconNode.image = UIImage(systemName: "person.2.fill")
        groupIconNode.tintColor = .white
        groupIconNode.contentMode = .scaleAspectFit

        let initial = name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"

        switch avatarMode {
        case .image:
            let px = Int(avatarSize * UIScreen.main.scale)
            let proxied = ImgproxyURL.create(from: avatarURL!, width: px, height: px)
            avatarNode.url = URL(string: proxied)
            avatarBgNode.backgroundColor = UIColor.theme.border
        case .group:
            avatarBgNode.backgroundColor = UIColor(red: 0.96, green: 0.55, blue: 0.16, alpha: 1)
        case .initial:
            avatarBgNode.backgroundColor = UIColor.theme.border
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            initialNode.attributedText = NSAttributedString(
                string: initial,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14.sf, weight: .bold),
                    .foregroundColor: UIColor.theme.textDisabled,
                    .paragraphStyle: para,
                ]
            )
        }

        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail
        nameNode.attributedText = NSAttributedString(
            string: name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .regular),
                .foregroundColor: UIColor.theme.textStrong,
            ]
        )

        let title = isSent ? L(L10n.ClanInviteSheet.invited) : L(L10n.ClanInviteSheet.invite)
        inviteButtonNode.backgroundColor = UIColor.theme.tertiary
        inviteButtonNode.cornerRadius = 16.swh
        inviteButtonNode.clipsToBounds = true
        inviteButtonNode.borderWidth = 1 / UIScreen.main.scale
        inviteButtonNode.borderColor = UIColor.theme.border.withAlphaComponent(0.8).cgColor
        inviteButtonNode.contentEdgeInsets = UIEdgeInsets(top: 6.sh, left: 12.sw, bottom: 6.sh, right: 12.sw)
        inviteButtonNode.isEnabled = !isSent && !isLoading

        if isLoading {
            inviteButtonNode.setTitle("", with: .systemFont(ofSize: 14.sf, weight: .medium), with: .clear, for: .normal)
        } else {
            inviteButtonNode.setTitle(
                title,
                with: .systemFont(ofSize: 14.sf, weight: .medium),
                with: UIColor.theme.textStrong,
                for: .normal
            )
        }

        inviteButtonNode.addTarget(self, action: #selector(inviteTapped), forControlEvents: .touchUpInside)
        alpha = isSent ? 0.6 : 1.0
    }

    func updateState(isSent: Bool, isLoading: Bool) {
        let title = isSent ? L(L10n.ClanInviteSheet.invited) : L(L10n.ClanInviteSheet.invite)
        inviteButtonNode.isEnabled = !isSent && !isLoading
        alpha = isSent ? 0.6 : 1.0

        if isLoading {
            inviteButtonNode.setTitle("", with: .systemFont(ofSize: 14.sf, weight: .medium), with: .clear, for: .normal)
            if spinnerWrapNode.isNodeLoaded {
                ASPerformBlockOnMainThread {
                    if let spinner = self.spinnerWrapNode.view.subviews.first as? UIActivityIndicatorView {
                        spinner.startAnimating()
                    }
                }
            }
        } else {
            inviteButtonNode.setTitle(
                title,
                with: .systemFont(ofSize: 14.sf, weight: .medium),
                with: UIColor.theme.textStrong,
                for: .normal
            )
            if spinnerWrapNode.isNodeLoaded {
                ASPerformBlockOnMainThread {
                    if let spinner = self.spinnerWrapNode.view.subviews.first as? UIActivityIndicatorView {
                        spinner.stopAnimating()
                    }
                }
            }
        }
    }

    @objc private func inviteTapped() { onInvite?() }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let avatarSize: CGFloat = 40.swh

        avatarBgNode.style.preferredSize = CGSize(width: avatarSize, height: avatarSize)

        let avatarOverlay: ASLayoutElement
        switch avatarMode {
        case .image:
            avatarNode.style.preferredSize = CGSize(width: avatarSize, height: avatarSize)
            avatarOverlay = avatarNode
        case .group:
            groupIconNode.style.preferredSize = CGSize(width: 20.swh, height: 20.swh)
            avatarOverlay = ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: .minimumXY, child: groupIconNode)
        case .initial:
            avatarOverlay = ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: .minimumXY, child: initialNode)
        }
        let avatarComposite = ASOverlayLayoutSpec(child: avatarBgNode, overlay: avatarOverlay)
        avatarComposite.style.preferredSize = CGSize(width: avatarSize, height: avatarSize)

        nameNode.style.flexShrink = 1
        nameNode.style.flexGrow = 0
        let nameOffset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 10.sh, left: 0, bottom: 0, right: 0),
            child: nameNode
        )
        nameOffset.style.flexShrink = 1

        let spacer = ASLayoutSpec()
        spacer.style.flexGrow = 1

        inviteButtonNode.style.minWidth = ASDimensionMake(60.sw)
        inviteButtonNode.style.maxWidth = ASDimensionMake(90.sw)
        inviteButtonNode.style.height = ASDimensionMake(32.sh)

        let spinnerCenter = ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: .minimumXY, child: spinnerWrapNode)
        let buttonWithSpinner = ASOverlayLayoutSpec(child: inviteButtonNode, overlay: spinnerCenter)

        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 10.sw,
            justifyContent: .start,
            alignItems: .center,
            children: [avatarComposite, nameOffset, spacer, buttonWithSpinner]
        )

        let inset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 20.sw, bottom: 0, right: 20.sw),
            child: row
        )
        inset.style.height = ASDimensionMake(60.sh)
        return inset
    }
}

private final class ClanInviteSheetContainerNode: ASDisplayNode {
    let titleNode = ASTextNode()
    let shareButton: ClanInviteActionButtonNode
    let copyButton: ClanInviteActionButtonNode
    let qrButton: ClanInviteActionButtonNode
    let dividerNode = ASDisplayNode()
    let searchWrapNode = ClanInviteSearchWrapNode()
    let listContainerNode = ASDisplayNode()
    let tableNode = ASTableNode(style: .plain)
    let emptyStateNode = ClanInviteEmptyStateNode()
    let loadingSpinner = UIActivityIndicatorView(style: .medium)
    let loadingLabel = UILabel()

    override init() {
        shareButton = ClanInviteActionButtonNode(
            iconAsset: "Invite/ShareIcon",
            fallbackSystemIcon: "square.and.arrow.up",
            title: L(L10n.ClanInviteSheet.share)
        )
        copyButton = ClanInviteActionButtonNode(
            iconAsset: "Invite/LinkIcon",
            fallbackSystemIcon: "link",
            title: L(L10n.ClanInviteSheet.copy)
        )
        qrButton = ClanInviteActionButtonNode(
            iconAsset: "",
            fallbackSystemIcon: "qrcode",
            title: L(L10n.ClanInviteSheet.qrCode)
        )

        super.init()
        automaticallyManagesSubnodes = false

        titleNode.isLayerBacked = true
        dividerNode.isLayerBacked = true

        backgroundColor = UIColor.theme.primary
        cornerRadius = 8.swh
        clipsToBounds = true

        let center = NSMutableParagraphStyle()
        center.alignment = .center
        titleNode.attributedText = NSAttributedString(
            string: L(L10n.ClanInviteSheet.title),
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .bold),
                .foregroundColor: UIColor.theme.textStrong,
                .paragraphStyle: center,
            ]
        )

        listContainerNode.backgroundColor = UIColor.theme.secondary
        listContainerNode.cornerRadius = 10.swh
        listContainerNode.clipsToBounds = true

        tableNode.cornerRadius = 10.swh

        loadingSpinner.startAnimating()
        loadingLabel.text = L(L10n.ClanInviteSheet.loadingInviteLink)
        loadingLabel.font = .systemFont(ofSize: 14.sf, weight: .regular)

        addSubnode(titleNode)
        addSubnode(shareButton)
        addSubnode(copyButton)
        addSubnode(qrButton)
        addSubnode(dividerNode)
        addSubnode(searchWrapNode)
        addSubnode(listContainerNode)
        listContainerNode.addSubnode(tableNode)
        listContainerNode.addSubnode(emptyStateNode)
    }

    override func didLoad() {
        super.didLoad()
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        tableNode.view.separatorStyle = .singleLine
        tableNode.view.separatorColor = UIColor.theme.textDisabled.withAlphaComponent(0.45)
        tableNode.view.separatorInset = .zero
        tableNode.view.layoutMargins = .zero
        tableNode.backgroundColor = .clear
        tableNode.view.showsVerticalScrollIndicator = false

        tableNode.leadingScreensForBatching = 2.0
    }

    func applyTheme() {
        backgroundColor = UIColor.theme.primary

        let center = NSMutableParagraphStyle()
        center.alignment = .center
        titleNode.attributedText = NSAttributedString(
            string: L(L10n.ClanInviteSheet.title),
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .bold),
                .foregroundColor: UIColor.theme.textStrong,
                .paragraphStyle: center,
            ]
        )

        dividerNode.backgroundColor = UIColor.theme.border.withAlphaComponent(0.6)
        searchWrapNode.applyTheme()
        loadingSpinner.color = UIColor.theme.textDisabled
        loadingLabel.textColor = UIColor.theme.textDisabled
        listContainerNode.backgroundColor = UIColor.theme.secondary
        emptyStateNode.applyTheme()
        tableNode.view.separatorColor = UIColor.theme.textDisabled.withAlphaComponent(0.45)
        tableNode.reloadData()
    }

    override func layout() {
        super.layout()
        let b = bounds
        let w = b.width
        var y: CGFloat = 0

        titleNode.frame = CGRect(x: 16.sw, y: 20.sh, width: w - 32.sw, height: 24.sh)
        y = 60.sh

        let aLead: CGFloat = 16.sw
        let aTrail: CGFloat = 16.sw
        let aTop = y + 16.sh

        let shareSz = shareButton.calculateSizeThatFits(CGSize(width: w, height: 62.sh))
        let copySz = copyButton.calculateSizeThatFits(CGSize(width: w, height: 62.sh))
        let qrSz = qrButton.calculateSizeThatFits(CGSize(width: w, height: 62.sh))

        let shareW = shareSz.width
        let copyW = copySz.width
        let qrW = qrSz.width

        shareButton.frame = CGRect(x: aLead, y: aTop, width: shareW, height: 62.sh)
        copyButton.frame = CGRect(x: (w - copyW) / 2, y: aTop, width: copyW, height: 62.sh)
        qrButton.frame = CGRect(x: w - aTrail - qrW, y: aTop, width: qrW, height: 62.sh)
        dividerNode.frame = CGRect(
            x: 0,
            y: y + 94.sh - 1 / UIScreen.main.scale,
            width: w,
            height: 1 / UIScreen.main.scale
        )
        y += 94.sh

        let lx: CGFloat = 16.sw
        let lw = w - 32.sw
        searchWrapNode.frame = CGRect(x: lx, y: y + 16.sh, width: lw, height: 40.sh)
        y += 62.sh

        let lh = max(0, b.height - y - 10.sh)
        listContainerNode.frame = CGRect(x: lx, y: y, width: lw, height: lh)
        tableNode.frame = listContainerNode.bounds
        emptyStateNode.frame = listContainerNode.bounds
    }

    func updateEmptyState(isEmpty: Bool) {
        emptyStateNode.isHidden = !isEmpty
        tableNode.isHidden = isEmpty
    }
}

final class ClanInviteSheetViewController: ViewController {
    private static let inviteIdRegex = try? NSRegularExpression(pattern: "/invite/(\\d+)", options: [])

    private enum InviteTarget: Hashable {
        case friend(userId: Int64)
        case direct(channelId: Int64, type: Int32, isPublic: Bool)
    }

    private struct FriendItem: Hashable {
        let id: Int64
        let name: String
        let avatarURL: String?
        let isGroupDM: Bool
        let target: InviteTarget
    }

    private let context: AccountContext
    private let clanId: Int64

    private var inviteLink: String?
    private var allFriends: [FriendItem] = []
    private var filteredFriends: [FriendItem] = []
    private var sentIds = Set<Int64>()
    private var sendingIds = Set<Int64>()
    private var dmChannelsByUserId: [Int64: Mezon_Api_ChannelDescription] = [:]

    private var foldedNameCache: [Int64: String] = [:]

    private var containerNode: ClanInviteSheetContainerNode { displayNode as! ClanInviteSheetContainerNode }

    init(context: AccountContext, clanId: Int64) {
        self.context = context
        self.clanId = clanId
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) {
        fatalError()
    }

    override func loadDisplayNode() {
        let node = ClanInviteSheetContainerNode()
        displayNode = node

        node.shareButton.onTap = { [weak self] in self?.shareInvite() }
        node.copyButton.onTap = { [weak self] in self?.copyInvite() }
        node.qrButton.onTap = { [weak self] in self?.showQR() }
        node.emptyStateNode.actionButtonNode.addTarget(
            self,
            action: #selector(emptyActionTapped),
            forControlEvents: .touchUpInside
        )

        node.tableNode.dataSource = self
        node.tableNode.delegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        containerNode.searchWrapNode.textField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        containerNode.searchWrapNode.clearButton.addTarget(self, action: #selector(clearSearchTapped), for: .touchUpInside)
        applyTheme()
        loadData()
    }

    private func applyTheme() {
        containerNode.applyTheme()
    }

    private func loadData() {
        Task { @MainActor in
            guard let token = await context.getToken() else {
                self.showSimpleAlert(message: L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            inviteLink = await resolveInviteLink(token: token)

            do {
                async let friendsTask = context.account.network.listFriends(
                    token: token,
                    limit: 100,
                    state: Int32(Mezon_Api_Friend.State.friend.rawValue)
                )
                async let directsTask = context.account.network.listDirectMessageChannels(token: token)
                let friends = try await friendsTask
                let directs = try await directsTask

                let memberIds = Set(context.account.postbox.read { tx in
                    tx.getClanMembers(clanId: self.clanId).map { $0.userId }
                })
                cacheDirectChannels(directs)

                let currentUserId = Int64(context.currentUser?.id ?? "") ?? 0
                var merged = [String: FriendItem]()

                for friend in friends.friends {
                    guard friend.state == Mezon_Api_Friend.State.friend.rawValue else { continue }
                    guard friend.hasUser else { continue }
                    let u = friend.user
                    let uid = u.id
                    guard uid != 0, uid != currentUserId, !memberIds.contains(uid) else { continue }
                    let name = !u.displayName.isEmpty ? u.displayName : (u.username.isEmpty ? "Unknown" : u.username)
                    let avatar = u.avatarURL.isEmpty ? nil : u.avatarURL
                    merged["user_\(uid)"] = FriendItem(
                        id: uid,
                        name: name,
                        avatarURL: avatar,
                        isGroupDM: false,
                        target: .friend(userId: uid)
                    )
                }

                for dm in directs {
                    let isDM = dm.type == MezonConstants.ChannelType.dm.rawValue
                    let isGroup = dm.type == MezonConstants.ChannelType.group.rawValue
                    guard isDM || isGroup else { continue }

                    if isDM {
                        guard let uid = dm.userIds.first else { continue }
                        guard uid != 0, uid != currentUserId, !memberIds.contains(uid) else { continue }
                        guard dm.channelID != 0 else { continue }
                        let name = !dm.channelLabel.isEmpty
                            ? dm.channelLabel
                            : (dm.displayNames.first(where: { !$0.isEmpty })
                                ?? dm.usernames.first(where: { !$0.isEmpty })
                                ?? "Unknown")
                        let avatar = dm.avatars.first(where: { !$0.isEmpty })
                        merged["user_\(uid)"] = FriendItem(
                            id: dm.channelID,
                            name: name,
                            avatarURL: avatar,
                            isGroupDM: false,
                            target: .direct(channelId: dm.channelID, type: dm.type, isPublic: dm.channelPrivate == 0)
                        )
                    } else if isGroup {
                        guard dm.channelID != 0 else { continue }
                        let name = !dm.channelLabel.isEmpty ? dm.channelLabel : "\(dm.creatorName)'s Group"
                        let hasCustomGroupAvatar = !dm.channelAvatar.isEmpty && !dm.channelAvatar.contains("avatar-group.png")
                        let avatar = hasCustomGroupAvatar ? dm.channelAvatar : nil
                        merged["group_\(dm.channelID)"] = FriendItem(
                            id: dm.channelID,
                            name: name,
                            avatarURL: avatar,
                            isGroupDM: true,
                            target: .direct(channelId: dm.channelID, type: dm.type, isPublic: dm.channelPrivate == 0)
                        )
                    }
                }

                self.allFriends = merged.values.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }

                self.rebuildFoldedNameCache()

                self.applyFilter()
                self.containerNode.loadingSpinner.stopAnimating()
            } catch {
                self.containerNode.loadingSpinner.stopAnimating()
                self.filteredFriends = []
                self.updateEmptyStateVisibility()
                await self.containerNode.tableNode.reloadData()
            }
        }
    }

    private func rebuildFoldedNameCache() {
        foldedNameCache.removeAll(keepingCapacity: true)
        for item in allFriends {
            foldedNameCache[item.id] = item.name.folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: .current
            )
        }
    }

    private func resolveInviteLink(token: String) async -> String? {
        let inviteChannelId = await resolveInviteChannelId(token: token)
        guard inviteChannelId != 0 else {
            return nil
        }

        do {
            let invite = try await context.account.network.linkInviteUser(
                clanId: clanId,
                channelId: inviteChannelId,
                expiryTime: 10,
                token: token
            )
            return "\(MezonConfig.chatWebAppBaseURL)/invite/\(invite.inviteLink)"
        } catch {
        }
        return nil
    }

    private func resolveInviteChannelId(token: String) async -> Int64 {
        do {
            let clans = try await context.account.network.listClanDescs(token: token)
            if let clan = clans.first(where: { $0.clanID == clanId }) {
                return clan.welcomeChannelID
            }
        } catch {
        }
        return 0
    }

    private func applyFilter() {
        let keyword = (containerNode.searchWrapNode.textField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if keyword.isEmpty {
            filteredFriends = allFriends
        } else {
            filteredFriends = allFriends.filter {
                (foldedNameCache[$0.id] ?? "").contains(keyword)
            }
        }
        updateEmptyStateVisibility()
        containerNode.tableNode.reloadData()
    }

    private func updateEmptyStateVisibility() {
        let isEmpty = filteredFriends.isEmpty
        containerNode.updateEmptyState(isEmpty: isEmpty)
        containerNode.loadingLabel.text = nil
    }

    private func updateCellState(for item: FriendItem) {
        Task { @MainActor in
            guard let rowIndex = self.filteredFriends.firstIndex(where: { $0.id == item.id }) else { return }
            let indexPath = IndexPath(row: rowIndex, section: 0)
            if let cell = self.containerNode.tableNode.nodeForRow(at: indexPath) as? ClanInviteFriendCellNode {
                let isSent = self.sentIds.contains(item.id)
                let isLoading = self.sendingIds.contains(item.id)
                cell.updateState(isSent: isSent, isLoading: isLoading)
            }
        }
    }

    private func inviteUser(_ item: FriendItem) {
        guard !sentIds.contains(item.id), !sendingIds.contains(item.id) else { return }
        sendingIds.insert(item.id)
        updateCellState(for: item)

        Task { @MainActor in
            defer {
                self.sendingIds.remove(item.id)
                self.updateCellState(for: item)
            }
            do {
                guard let token = await context.getToken() else { throw NSError(domain: "session", code: -1) }
                let resolvedInviteLink: String
                if let existing = inviteLink {
                    resolvedInviteLink = existing
                } else if let generated = await resolveInviteLink(token: token) {
                    inviteLink = generated
                    resolvedInviteLink = generated
                } else {
                    showSimpleAlert(message: L(L10n.ClanInviteSheet.cannotCreateInvite))
                    return
                }

                let dm: Mezon_Api_ChannelDescription
                let isPublic: Bool
                switch item.target {
                case .friend(let userId):
                    dm = try await resolveDirectChannel(for: userId, token: token)
                    isPublic = dm.channelPrivate == 0
                case .direct(let channelId, _, let channelIsPublic):
                    var directChannel = Mezon_Api_ChannelDescription()
                    directChannel.channelID = channelId
                    dm = directChannel
                    isPublic = channelIsPublic
                }

                let payload = try await buildInviteMessagePayload(url: resolvedInviteLink, token: token)
                let contentData = try JSONSerialization.data(withJSONObject: payload)
                let content = String(data: contentData, encoding: .utf8) ?? "{}"
                _ = try await context.account.network.sendChannelMessage(
                    clanId: 0,
                    channelId: dm.channelID,
                    mode: MezonConstants.ChannelStreamMode.dm.rawValue,
                    isPublic: isPublic,
                    content: content,
                    token: token
                )
                self.sentIds.insert(item.id)
            } catch {
                self.showSimpleAlert(message: String(format: L(L10n.ClanInviteSheet.cannotSendInvite), item.name))
            }
        }
    }

    private func buildInviteMessagePayload(url: String, token: String) async throws -> [String: Any] {
        let linkLength = url.count
        var mk: [[String: Any]] = [
            ["s": 0, "e": linkLength, "type": "lk"]
        ]
        var payload: [String: Any] = ["t": url]

        if let inviteId = extractInviteId(from: url), !inviteId.isEmpty {
            do {
                let inviteInfo = try await context.account.network.getInviteInfo(code: inviteId, token: token)
                let memberCount = inviteInfo.member_count ?? 0
                let title = inviteInfo.clan_name ?? L(L10n.ClanInviteSheet.unknownClan)
                let description = L(L10n.ClanAction.memberCount, memberCount)
                let image = inviteInfo.clan_logo ?? ""

                mk.append([
                    "type": "lk_ogp",
                    "s": linkLength,
                    "e": linkLength + 1,
                    "index": 0,
                    "title": title,
                    "description": description,
                    "image": image
                ])
            } catch {
            }
        }

        payload["mk"] = mk
        return payload
    }

    private func extractInviteId(from url: String) -> String? {
        guard let regex = Self.inviteIdRegex else {
            return nil
        }
        let ns = url as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: url, options: [], range: range), match.numberOfRanges > 1 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }

    private func cacheDirectChannels(_ directs: [Mezon_Api_ChannelDescription]) {
        var map: [Int64: Mezon_Api_ChannelDescription] = [:]
        for channel in directs where
            channel.type == MezonConstants.ChannelType.dm.rawValue &&
            channel.userIds.count == 1 &&
            channel.userIds[0] != 0 {
            map[channel.userIds[0]] = channel
        }
        dmChannelsByUserId = map
    }

    private func resolveDirectChannel(for userId: Int64, token: String) async throws -> Mezon_Api_ChannelDescription {
        if let cached = dmChannelsByUserId[userId] {
            return cached
        }

        let dmChannels = try await context.account.network.listDirectMessageChannels(token: token)
        cacheDirectChannels(dmChannels)
        if let existing = dmChannelsByUserId[userId] {
            return existing
        }

        let created = try await context.account.network.createDirectMessage(userId: userId, token: token)
        if created.userIds.count == 1, let peerId = created.userIds.first, peerId != 0 {
            dmChannelsByUserId[peerId] = created
        } else {
            dmChannelsByUserId[userId] = created
        }
        return created
    }

    @objc private func searchChanged() {
        containerNode.searchWrapNode.clearButton.isHidden = (containerNode.searchWrapNode.textField.text ?? "").isEmpty
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(debouncedApplyFilter), object: nil)
        perform(#selector(debouncedApplyFilter), with: nil, afterDelay: 0.15)
    }

    @objc private func debouncedApplyFilter() {
        applyFilter()
    }

    @objc private func clearSearchTapped() {
        containerNode.searchWrapNode.textField.text = ""
        containerNode.searchWrapNode.clearButton.isHidden = true
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(debouncedApplyFilter), object: nil)
        applyFilter()
    }

    private func copyInvite() {
        guard let inviteLink else { return }
        UIPasteboard.general.string = inviteLink
        Toast.success(L(L10n.ClanInviteSheet.linkCopied))
    }

    private func shareInvite() {
        guard let inviteLink else { return }
        let ac = UIActivityViewController(activityItems: [inviteLink], applicationActivities: nil)
        present(ac, animated: true)
    }

    private func showQR() {
        guard let inviteLink else { return }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
        filter.setValue(inviteLink.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return }
        let transform = CGAffineTransform(scaleX: 8, y: 8)
        let image = UIImage(ciImage: output.transformed(by: transform))
        let ac = UIActivityViewController(activityItems: [image, inviteLink], applicationActivities: nil)
        present(ac, animated: true)
    }

    @objc private func emptyActionTapped() {
        Toast.info(L(L10n.ClanInviteSheet.emptyAction))
    }

    private func showSimpleAlert(message: String) {
        let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
    }
}

extension ClanInviteSheetViewController: ASTableDataSource, ASTableDelegate {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        filteredFriends.count
    }

    func tableNode(_ tableNode: ASTableNode, constrainedSizeForRowAt indexPath: IndexPath) -> ASSizeRange {
        ASSizeRange(
            min: CGSize(width: 0, height: 60.sh),
            max: CGSize(width: tableNode.bounds.width, height: 60.sh)
        )
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        let item = filteredFriends[indexPath.row]
        let isSent = sentIds.contains(item.id)
        let isLoading = sendingIds.contains(item.id)
        return { [weak self] in
            let cell = ClanInviteFriendCellNode(
                name: item.name,
                avatarURL: item.avatarURL,
                isGroupDM: item.isGroupDM,
                isSent: isSent,
                isLoading: isLoading
            )
            cell.onInvite = { [weak self] in
                self?.inviteUser(item)
            }
            return cell
        }
    }
}
