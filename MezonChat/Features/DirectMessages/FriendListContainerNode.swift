import AsyncDisplayKit
import SwiftProtobuf

struct FriendListInteraction {
    let onBackTapped: () -> Void
    let onAddFriendTapped: () -> Void
    let onFriendRequestTapped: () -> Void
    let onCallFriend: (Mezon_Api_Friend) -> Void
    let onMessageFriend: (Mezon_Api_Friend) -> Void
    let onShowProfile: (Mezon_Api_Friend) -> Void
}

final class FriendListContainerNode: ASDisplayNode {
    private lazy var gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.startPoint = CGPoint(x: 0.5, y: 0)
        gl.endPoint   = CGPoint(x: 0.5, y: 1)
        return gl
    }()

    private let headerNode = ASDisplayNode()
    private let backButtonNode = ASButtonNode()
    private let titleNode = ASTextNode()
    private let subtitleNode = ASTextNode()
    private let addFriendButtonNode = ASButtonNode()

    private let searchContainerNode = ASDisplayNode()
    private let searchIconNode = ASImageNode()
    private let searchTextField = UITextField()

    private let requestPillNode = ASDisplayNode()
    private let requestIconNode = ASImageNode()
    private let requestTitleNode = ASTextNode()
    private let requestCountNode = ASTextNode()
    private let requestChevronNode = ASImageNode()

    private let tableNode: ASTableNode

    private let emptyNode = ASTextNode()

    private var currentGroups: [FriendAlphabetGroup] = []
    private var friendRequestReceivedCount: Int = 0
    private var friendRequestSentCount: Int = 0
    private var totalFriendCount: Int = 0
    private var isSearching: Bool = false

    private let interaction: FriendListInteraction
    private let disposables = DisposableSet()
    private var validLayout: (size: CGSize, safeTop: CGFloat, bottomInset: CGFloat)?
    private var previousLayout: (size: CGSize, safeTop: CGFloat, bottomInset: CGFloat)?
    private var hasReceivedInitialState: Bool = false

    private let centeredParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }()

    private func makeSymbolImage(name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight? = nil) -> UIImage? {
        let config: UIImage.SymbolConfiguration
        if let weight {
            config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        } else {
            config = UIImage.SymbolConfiguration(pointSize: pointSize)
        }
        return UIImage(systemName: name, withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
    }

    init(signal: Signal<FriendListState, NoError>, interaction: FriendListInteraction) {
        tableNode = ASTableNode(style: .plain)
        self.interaction = interaction
        super.init()

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                self.hasReceivedInitialState = true
                self.currentGroups = newState.groups
                self.friendRequestReceivedCount = newState.receivedRequestCount
                self.friendRequestSentCount = newState.sentRequestCount
                self.totalFriendCount = newState.totalFriendCount
                self.isSearching = newState.isSearching
                self.updateContent()
            })
        )
    }

    deinit { disposables.dispose() }

    override func didLoad() {
        super.didLoad()

        let t = UIColor.theme
        gradientLayer.colors = [t.primary.cgColor, t.primaryGradient.cgColor]
        layer.addSublayer(gradientLayer)

        setupHeader()
        setupSearch()
        setupRequestPill()
        setupTable()
        setupEmptyState()

        if validLayout != nil {
            applyLayout(transition: .immediate)
        }
        if hasReceivedInitialState {
            updateContent()
        } else {
            tableNode.isHidden = true
            requestPillNode.isHidden = true
            emptyNode.isHidden = true
            subtitleNode.isHidden = true
        }
    }

    private func setupHeader() {
        let t = UIColor.theme
        let chevronImg = makeSymbolImage(name: "chevron.left", pointSize: 16.sf, weight: .semibold)
        backButtonNode.setImage(chevronImg, for: .normal)
        backButtonNode.tintColor = t.textStrong
        backButtonNode.imageNode.contentMode = .scaleAspectFit
        backButtonNode.addTarget(self, action: #selector(backTapped), forControlEvents: .touchUpInside)

        titleNode.attributedText = NSAttributedString(
            string: L(L10n.FriendList.title),
            attributes: [
                .font: UIFont.systemFont(ofSize: 17.sf, weight: .semibold),
                .foregroundColor: t.textStrong,
                .paragraphStyle: centeredParagraphStyle
            ]
        )
        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail

        subtitleNode.maximumNumberOfLines = 1
        subtitleNode.truncationMode = .byTruncatingTail

        addFriendButtonNode.setTitle(
            L(L10n.FriendList.addFriend),
            with: .systemFont(ofSize: 13.sf, weight: .medium),
            with: UIColor(red: 0.45, green: 0.55, blue: 1.0, alpha: 1.0),
            for: .normal
        )
        addFriendButtonNode.tintColor = UIColor(red: 0.45, green: 0.55, blue: 1.0, alpha: 1.0)
        addFriendButtonNode.contentHorizontalAlignment = .right
        addFriendButtonNode.addTarget(self, action: #selector(addFriendTapped), forControlEvents: .touchUpInside)

        addSubnode(headerNode)
        headerNode.addSubnode(backButtonNode)
        headerNode.addSubnode(titleNode)
        headerNode.addSubnode(subtitleNode)
        headerNode.addSubnode(addFriendButtonNode)
    }

    private func setupSearch() {
        let t = UIColor.theme
        searchContainerNode.backgroundColor = t.secondary
        searchContainerNode.cornerRadius = 28.sf
        searchContainerNode.clipsToBounds = true

        let searchImg = makeSymbolImage(name: "magnifyingglass", pointSize: 14.sf)
        searchIconNode.image = searchImg
        searchIconNode.tintColor = t.textDisabled
        searchIconNode.contentMode = .scaleAspectFit

        searchTextField.placeholder = L(L10n.FriendList.searchPlaceholder)
        searchTextField.font = .systemFont(ofSize: 14.sf)
        searchTextField.textColor = t.textStrong
        searchTextField.tintColor = t.textStrong
        searchTextField.returnKeyType = .search
        searchTextField.autocorrectionType = .no
        searchTextField.autocapitalizationType = .none
        searchTextField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.FriendList.searchPlaceholder),
            attributes: [.foregroundColor: t.textDisabled]
        )
        searchTextField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)

        addSubnode(searchContainerNode)
        searchContainerNode.addSubnode(searchIconNode)
        searchContainerNode.view.addSubview(searchTextField)
    }

    private func setupRequestPill() {
        let t = UIColor.theme
        requestPillNode.backgroundColor = t.secondary
        requestPillNode.cornerRadius = 12.sf
        requestPillNode.clipsToBounds = true

        let paperPlaneImg = makeSymbolImage(name: "paperplane.fill", pointSize: 20.sf)
        requestIconNode.image = paperPlaneImg
        requestIconNode.tintColor = t.textStrong
        requestIconNode.contentMode = .scaleAspectFit

        requestTitleNode.attributedText = NSAttributedString(
            string: L(L10n.FriendList.friendRequest),
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf),
                .foregroundColor: t.text
            ]
        )

        requestCountNode.attributedText = NSAttributedString(
            string: "",
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf),
                .foregroundColor: t.text
            ]
        )

        let chevronImg = makeSymbolImage(name: "chevron.right", pointSize: 12.sf, weight: .medium)
        requestChevronNode.image = chevronImg
        requestChevronNode.tintColor = t.textDisabled
        requestChevronNode.contentMode = .scaleAspectFit

        requestPillNode.addSubnode(requestIconNode)
        requestPillNode.addSubnode(requestTitleNode)
        requestPillNode.addSubnode(requestCountNode)
        requestPillNode.addSubnode(requestChevronNode)

        let tap = UITapGestureRecognizer(target: self, action: #selector(requestPillTapped))
        requestPillNode.view.addGestureRecognizer(tap)
        requestPillNode.isUserInteractionEnabled = true

        addSubnode(requestPillNode)
    }

    private func setupTable() {
        tableNode.view.backgroundColor = .clear
        tableNode.view.separatorStyle = .none
        tableNode.view.showsVerticalScrollIndicator = false
        tableNode.view.keyboardDismissMode = .onDrag
        tableNode.dataSource = self
        tableNode.delegate = self
        addSubnode(tableNode)
    }

    private func setupEmptyState() {
        emptyNode.attributedText = NSAttributedString(
            string: L(L10n.FriendList.noResults),
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf),
                .foregroundColor: UIColor.theme.textDisabled
            ]
        )
        emptyNode.isHidden = true
        addSubnode(emptyNode)
    }

    private func updateContent() {
        guard isNodeLoaded else { return }

        let isEmpty = currentGroups.isEmpty
        tableNode.isHidden = isEmpty
        emptyNode.isHidden = !isEmpty || !isSearching
        requestPillNode.isHidden = false

        subtitleNode.isHidden = totalFriendCount == 0
        subtitleNode.attributedText = NSAttributedString(
            string: "\(totalFriendCount) " + L(L10n.FriendList.friendCount),
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf),
                .foregroundColor: UIColor.theme.textDisabled,
                .paragraphStyle: centeredParagraphStyle
            ]
        )

        requestCountNode.attributedText = NSAttributedString(
            string: "\(friendRequestReceivedCount) " + L(L10n.FriendList.received) + " • " + "\(friendRequestSentCount) " + L(L10n.FriendList.sent),
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf),
                .foregroundColor: UIColor.theme.text
            ]
        )

        if validLayout != nil {
            applyLayout(transition: .immediate)
        }

        tableNode.reloadData()
    }

    func updateLayout(size: CGSize, safeTop: CGFloat, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) {
        let top = isNodeLoaded ? max(safeTop, view.safeAreaInsets.top) : safeTop
        let nextLayout: (size: CGSize, safeTop: CGFloat, bottomInset: CGFloat) = (size, top, bottomInset)
        if let previousLayout,
           previousLayout.size == nextLayout.size,
           previousLayout.safeTop == nextLayout.safeTop,
           previousLayout.bottomInset == nextLayout.bottomInset {
            return
        }
        previousLayout = nextLayout
        self.validLayout = nextLayout
        applyLayout(transition: transition)
    }

    private func applyLayout(transition: ContainedViewLayoutTransition) {
        guard let (size, safeTop, bottomInset) = validLayout else { return }

        let sideInset: CGFloat = 20.sw
        let headerH: CGFloat = 52.sh
        let headerY = safeTop

        transition.updateFrame(node: headerNode, frame: CGRect(x: 0, y: headerY, width: size.width, height: headerH))
        let backSize: CGFloat = 36.swh
        transition.updateFrame(node: backButtonNode, frame: CGRect(x: sideInset - 8.sw, y: (headerH - backSize) / 2, width: backSize, height: backSize))

        let headerContentW = size.width - (backSize + sideInset) * 2
        let headerSideInset = backSize + sideInset
        let titleH: CGFloat = 22.sh
        let subH: CGFloat = 18.sh
        
        if subtitleNode.isHidden {
            let titleY = (headerH - titleH) / 2
            transition.updateFrame(node: titleNode, frame: CGRect(x: headerSideInset, y: titleY, width: headerContentW, height: titleH))
        } else {
            let titleY = (headerH - titleH - subH) / 2
            transition.updateFrame(node: titleNode, frame: CGRect(x: headerSideInset, y: titleY, width: headerContentW, height: titleH))
            transition.updateFrame(node: subtitleNode, frame: CGRect(x: headerSideInset, y: titleY + titleH, width: headerContentW, height: subH))
        }

        let addW = addFriendButtonNode.calculateSizeThatFits(CGSize(width: 200.sw, height: 32.sh)).width + 16.sw
        let addH: CGFloat = 32.sh
        transition.updateFrame(node: addFriendButtonNode, frame: CGRect(x: size.width - sideInset - addW, y: (headerH - addH) / 2, width: addW, height: addH))

        let searchY = headerY + headerH + 8.sh
        let searchH: CGFloat = 56.sh
        transition.updateFrame(node: searchContainerNode, frame: CGRect(x: sideInset, y: searchY, width: size.width - sideInset * 2, height: searchH))

        let iconSize: CGFloat = 18.swh
        let iconX: CGFloat = 12.sw
        transition.updateFrame(node: searchIconNode, frame: CGRect(x: iconX, y: (searchH - iconSize) / 2, width: iconSize, height: iconSize))
        transition.updateFrame(view: searchTextField, frame: CGRect(x: iconX + iconSize + 8.sw, y: 0, width: size.width - sideInset * 2 - iconX - iconSize - 20.sw, height: searchH))

        var contentY = searchY + searchH + 16.sh
        
        if !emptyNode.isHidden {
            let emptyH: CGFloat = 30.sh
            transition.updateFrame(node: emptyNode, frame: CGRect(x: sideInset, y: contentY, width: size.width - sideInset * 2, height: emptyH))
            contentY += emptyH + 8.sh
        }
        
        if !requestPillNode.isHidden {
            let pillH: CGFloat = 56.sh
            transition.updateFrame(node: requestPillNode, frame: CGRect(x: sideInset, y: contentY, width: size.width - sideInset * 2, height: pillH))
            
            let pillInset: CGFloat = 14.sw
            let reqIconSize: CGFloat = 30.swh
            transition.updateFrame(node: requestIconNode, frame: CGRect(x: pillInset, y: (pillH - reqIconSize) / 2, width: reqIconSize, height: reqIconSize))

            let chevW: CGFloat = 16.swh
            let chevX = size.width - sideInset * 2 - pillInset - chevW
            transition.updateFrame(node: requestChevronNode, frame: CGRect(x: chevX, y: (pillH - chevW) / 2, width: chevW, height: chevW))

            let textX = pillInset + reqIconSize + 12.sw
            let textW = chevX - textX - 8.sw
            transition.updateFrame(node: requestTitleNode, frame: CGRect(x: textX, y: 8.sh, width: textW, height: 22.sh))
            transition.updateFrame(node: requestCountNode, frame: CGRect(x: textX, y: 28.sh, width: textW, height: 18.sh))

            contentY += pillH + 8.sh
        }

        let tableH = size.height - contentY - bottomInset
        transition.updateFrame(node: tableNode, frame: CGRect(x: 0, y: contentY, width: size.width, height: tableH))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = CGRect(origin: .zero, size: size)
        CATransaction.commit()
    }

    func applyTheme() {
        let t = UIColor.theme
        gradientLayer.colors = [t.primary.cgColor, t.primaryGradient.cgColor]

        backButtonNode.setImage(makeSymbolImage(name: "chevron.left", pointSize: 16.sf, weight: .semibold), for: .normal)
        backButtonNode.tintColor = t.textStrong
        titleNode.attributedText = NSAttributedString(
            string: L(L10n.FriendList.title),
            attributes: [
                .font: UIFont.systemFont(ofSize: 17.sf, weight: .semibold),
                .foregroundColor: t.textStrong,
                .paragraphStyle: centeredParagraphStyle
            ]
        )
        searchContainerNode.backgroundColor = t.secondary
        searchIconNode.image = makeSymbolImage(name: "magnifyingglass", pointSize: 14.sf)
        searchIconNode.tintColor = t.textDisabled
        searchTextField.textColor = t.textStrong
        requestPillNode.backgroundColor = t.secondary
        requestIconNode.image = makeSymbolImage(name: "paperplane.fill", pointSize: 20.sf)
        requestIconNode.tintColor = t.textStrong
        requestChevronNode.image = makeSymbolImage(name: "chevron.right", pointSize: 12.sf, weight: .medium)
        requestChevronNode.tintColor = t.textDisabled
        requestTitleNode.attributedText = NSAttributedString(
            string: L(L10n.FriendList.friendRequest),
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf),
                .foregroundColor: t.text
            ]
        )
        emptyNode.attributedText = NSAttributedString(
            string: L(L10n.FriendList.noResults),
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf),
                .foregroundColor: t.textDisabled
            ]
        )

        guard isNodeLoaded else { return }
        tableNode.reloadData()
    }

    var onSearchTextChanged: ((String) -> Void)?

    @objc private func searchTextChanged() {
        let text = searchTextField.text ?? ""
        onSearchTextChanged?(text)
    }

    @objc private func backTapped() { interaction.onBackTapped() }
    @objc private func addFriendTapped() { interaction.onAddFriendTapped() }
    @objc private func requestPillTapped() { interaction.onFriendRequestTapped() }
}

extension FriendListContainerNode: ASTableDataSource, ASTableDelegate {

    func numberOfSections(in tableNode: ASTableNode) -> Int {
        currentGroups.count
    }

    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        guard section < currentGroups.count else { return 0 }
        return currentGroups[section].friends.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section < currentGroups.count else { return nil }
        let character = currentGroups[section].character
        let header = UIView()
        header.backgroundColor = .clear
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: character,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .semibold),
                .foregroundColor: UIColor.theme.textDisabled,
            ]
        )
        label.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20.sw),
            label.topAnchor.constraint(equalTo: header.topAnchor, constant: 0),
        ])
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        24.sh
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        guard indexPath.section < currentGroups.count else {
            return { ASCellNode() }
        }
        let group = currentGroups[indexPath.section]
        guard indexPath.row < group.friends.count else {
            return { ASCellNode() }
        }
        let friend = group.friends[indexPath.row]
        let isFirst = indexPath.row == 0
        let isLast = indexPath.row == group.friends.count - 1
        let interaction = interaction
        return {
            FriendListItemNode(friend: friend, isFirst: isFirst, isLast: isLast, interaction: interaction)
        }
    }

    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        tableNode.deselectRow(at: indexPath, animated: true)
        guard indexPath.section < currentGroups.count else { return }
        let group = currentGroups[indexPath.section]
        guard indexPath.row < group.friends.count else { return }
        interaction.onShowProfile(group.friends[indexPath.row])
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        searchTextField.resignFirstResponder()
    }
}

final class FriendListItemNode: ASCellNode {

    private let friend: Mezon_Api_Friend
    private let interaction: FriendListInteraction
    private let isFirst: Bool
    private let isLast: Bool

    private let cardNode: ASDisplayNode
    private let avatarNode: ASNetworkImageNode
    private let avatarPlaceholderNode: ASTextNode
    private let onlineIndicatorNode: ASImageNode
    private let displayNameNode: ASTextNode
    private let callButtonNode: ASButtonNode
    private let messageButtonNode: ASButtonNode
    private let separatorNode: ASDisplayNode

    init(friend: Mezon_Api_Friend, isFirst: Bool, isLast: Bool, interaction: FriendListInteraction) {
        self.friend = friend
        self.isFirst = isFirst
        self.isLast = isLast
        self.interaction = interaction
        
        self.cardNode = ASDisplayNode()
        self.avatarNode = ASNetworkImageNode()
        self.avatarPlaceholderNode = ASTextNode()
        self.onlineIndicatorNode = ASImageNode()
        self.displayNameNode = ASTextNode()
        self.callButtonNode = ASButtonNode()
        self.messageButtonNode = ASButtonNode()
        self.separatorNode = ASDisplayNode()
        
        super.init()
        automaticallyManagesSubnodes = true
        setupUI()
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear

        let t = UIColor.theme
        cardNode.backgroundColor = t.secondary
        cardNode.clipsToBounds = true
        
        let cornerRadius: CGFloat = 12.sf
        if isFirst && isLast {
            cardNode.cornerRadius = cornerRadius
        } else if isFirst {
            cardNode.cornerRadius = cornerRadius
            cardNode.onDidLoad { node in
                node.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            }
        } else if isLast {
            cardNode.cornerRadius = cornerRadius
            cardNode.onDidLoad { node in
                node.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            }
        } else {
            cardNode.cornerRadius = 0
        }
        let user = friend.user

        let avatarSize: CGFloat = 44.swh
        avatarNode.cornerRadius = avatarSize / 2
        avatarNode.clipsToBounds = true
        avatarNode.contentMode = .scaleAspectFill
        avatarNode.shouldRenderProgressImages = false

        let name = user.displayName.isEmpty ? user.username : user.displayName
        let initialSource = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialChar = initialSource.isEmpty ? "?" : String(initialSource.prefix(1)).uppercased()
        avatarPlaceholderNode.attributedText = NSAttributedString(
            string: initialChar,
            attributes: [
                .font: UIFont.systemFont(ofSize: 18.sf, weight: .semibold),
                .foregroundColor: UIColor.mezonTextPrimary
            ]
        )

        let avatarRaw = user.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !avatarRaw.isEmpty {
            let proxied = ImgproxyURL.create(from: avatarRaw, width: 120, height: 120)
            if let url = URL(string: proxied) {
                avatarNode.url = url
                avatarPlaceholderNode.isHidden = true
                avatarNode.backgroundColor = .clear
            } else {
                avatarNode.url = nil
                avatarPlaceholderNode.isHidden = false
                avatarNode.backgroundColor = t.colorActiveClan.withAlphaComponent(0.3)
            }
        } else {
            avatarNode.url = nil
            avatarPlaceholderNode.isHidden = false
            avatarNode.backgroundColor = t.colorActiveClan.withAlphaComponent(0.3)
        }

        let dotSize: CGFloat = 14.swh
        let statusIconName: String
        switch user.status {
        case "online":
            statusIconName = "OnlineIcon"
        case "idle":
            statusIconName = "IdleIcon"
        case "dnd":
            statusIconName = "DisturbIcon"
        default:
            statusIconName = user.online ? "OnlineIcon" : "InvisibleIcon"
        }
        onlineIndicatorNode.image = UIImage(named: "Profile/\(statusIconName)", in: Bundle.main, compatibleWith: nil)?
            .withRenderingMode(.alwaysOriginal)
        onlineIndicatorNode.contentMode = .scaleAspectFit

        displayNameNode.attributedText = NSAttributedString(
            string: name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf),
                .foregroundColor: t.textStrong,
            ]
        )
        displayNameNode.maximumNumberOfLines = 1
        displayNameNode.truncationMode = .byTruncatingTail

        let callImg = UIImage(named: "Chat/CallIcon")?.withRenderingMode(.alwaysTemplate)
        callButtonNode.setImage(callImg, for: .normal)
        callButtonNode.tintColor = t.textStrong
        callButtonNode.style.preferredSize = CGSize(width: 20.swh, height: 20.swh)
        callButtonNode.imageNode.contentMode = .scaleAspectFit
        callButtonNode.hitTestSlop = UIEdgeInsets(top: -10.sh, left: -10.sw, bottom: -10.sh, right: -10.sw)
        callButtonNode.addTarget(self, action: #selector(callTapped), forControlEvents: .touchUpInside)

        let msgImg = UIImage(named: "Chat/MessageIcon")?.withRenderingMode(.alwaysTemplate)
        messageButtonNode.setImage(msgImg, for: .normal)
        messageButtonNode.tintColor = t.textStrong
        messageButtonNode.style.preferredSize = CGSize(width: 20.swh, height: 20.swh)
        messageButtonNode.imageNode.contentMode = .scaleAspectFit
        messageButtonNode.hitTestSlop = UIEdgeInsets(top: -10.sh, left: -10.sw, bottom: -10.sh, right: -10.sw)
        messageButtonNode.addTarget(self, action: #selector(messageTapped), forControlEvents: .touchUpInside)

        separatorNode.backgroundColor = t.secondary
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let avatarSize: CGFloat = 44.swh
        avatarNode.style.preferredSize = CGSize(width: avatarSize, height: avatarSize)
        avatarNode.style.flexShrink = 0

        let avatarOverlay = ASOverlayLayoutSpec(
            child: avatarNode,
            overlay: ASCenterLayoutSpec(
                centeringOptions: .XY,
                sizingOptions: .minimumXY,
                child: avatarPlaceholderNode
            )
        )
        avatarOverlay.style.flexShrink = 0

        let dotSize: CGFloat = 12.swh
        onlineIndicatorNode.style.preferredSize = CGSize(width: dotSize, height: dotSize)

        let avatarWithDot = ASCornerLayoutSpec(
            child: avatarOverlay,
            corner: onlineIndicatorNode,
            location: .bottomRight
        )
        avatarWithDot.offset = CGPoint(x: -6.2.sw, y: -6.2.sh)

        displayNameNode.style.flexGrow = 1
        displayNameNode.style.flexShrink = 1

        let actionsStack = ASStackLayoutSpec.horizontal()
        actionsStack.spacing = 12.sw
        actionsStack.alignItems = .center
        actionsStack.children = [callButtonNode, messageButtonNode]
        actionsStack.style.flexShrink = 0

        let contentStack = ASStackLayoutSpec.horizontal()
        contentStack.spacing = 16.sw
        contentStack.alignItems = .center
        contentStack.children = [avatarWithDot, displayNameNode, actionsStack]

        let paddedContent = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 8.sh, left: 16.sw, bottom: 8.sh, right: 16.sw),
            child: contentStack
        )

        let cardBackground = ASBackgroundLayoutSpec(child: paddedContent, background: cardNode)
        let cardMargin = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 20.sw, bottom: 0, right: 20.sw),
            child: cardBackground
        )

        if isLast {
            return cardMargin
        }

        separatorNode.style.preferredSize = CGSize(width: ASDimensionAuto.value, height: 0.5)
        let separatorInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 16.sw + 44.swh + 16.sw, bottom: 0, right: 16.sw),
            child: separatorNode
        )

        let stack = ASStackLayoutSpec.vertical()
        stack.children = [cardBackground, separatorInset]
        
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 20.sw, bottom: 0, right: 20.sw),
            child: stack
        )
    }

    @objc private func callTapped() {
        Toast.comingSoonLine(L(L10n.Common.comingSoon))
    }

    @objc private func messageTapped() {
        interaction.onMessageFriend(friend)
    }
}
