import AsyncDisplayKit
import UIKit
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

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let addFriendButton = UIButton(type: .system)

    private let searchContainerView = UIView()
    private let searchIconView = UIImageView()
    private let searchTextField = UITextField()

    private let requestPillView = UIView()
    private let requestIconView = UIImageView()
    private let requestTitleLabel = UILabel()
    private let requestCountLabel = UILabel()
    private let requestChevron = UIImageView()

    private let tableNode: ASTableNode

    private let emptyLabel = UILabel()

    private var currentGroups: [FriendAlphabetGroup] = []
    private var friendRequestReceivedCount: Int = 0
    private var friendRequestSentCount: Int = 0
    private var totalFriendCount: Int = 0
    private var isSearching: Bool = false

    private let interaction: FriendListInteraction
    private let disposables = DisposableSet()
    private var validLayout: (size: CGSize, safeTop: CGFloat, bottomInset: CGFloat)?
    private var previousLayout: (size: CGSize, safeTop: CGFloat, bottomInset: CGFloat)?

    init(signal: Signal<FriendListState, NoError>, interaction: FriendListInteraction) {
        tableNode = ASTableNode(style: .plain)
        self.interaction = interaction
        super.init()

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
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
        updateContent()
    }

    private func setupHeader() {
        let t = UIColor.theme
        let chevronImg = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16.sf, weight: .semibold))
        backButton.setImage(chevronImg, for: .normal)
        backButton.tintColor = t.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        titleLabel.text = L(L10n.FriendList.title)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        titleLabel.textColor = t.textStrong
        titleLabel.textAlignment = .center

        subtitleLabel.font = .systemFont(ofSize: 12.sf)
        subtitleLabel.textColor = t.textDisabled
        subtitleLabel.textAlignment = .center

        addFriendButton.setTitle(L(L10n.FriendList.addFriend), for: .normal)
        addFriendButton.titleLabel?.font = .systemFont(ofSize: 13.sf, weight: .medium)
        addFriendButton.tintColor = UIColor(red: 0.45, green: 0.55, blue: 1.0, alpha: 1.0)
        addFriendButton.setTitleColor(UIColor(red: 0.45, green: 0.55, blue: 1.0, alpha: 1.0), for: .normal)
        addFriendButton.addTarget(self, action: #selector(addFriendTapped), for: .touchUpInside)

        headerView.addSubview(backButton)
        headerView.addSubview(titleLabel)
        headerView.addSubview(subtitleLabel)
        headerView.addSubview(addFriendButton)
        view.addSubview(headerView)
    }

    private func setupSearch() {
        let t = UIColor.theme
        searchContainerView.backgroundColor = t.secondary
        searchContainerView.layer.cornerRadius = 28.sf
        searchContainerView.clipsToBounds = true

        let searchImg = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.sf))
        searchIconView.image = searchImg
        searchIconView.tintColor = t.textDisabled
        searchIconView.contentMode = .scaleAspectFit

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

        searchContainerView.addSubview(searchIconView)
        searchContainerView.addSubview(searchTextField)
        view.addSubview(searchContainerView)
    }

    private func setupRequestPill() {
        let t = UIColor.theme
        requestPillView.backgroundColor = t.secondary
        requestPillView.layer.cornerRadius = 12.sf
        requestPillView.clipsToBounds = true

        let paperPlaneImg = UIImage(systemName: "paperplane.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20.sf))
        requestIconView.image = paperPlaneImg
        requestIconView.tintColor = t.textStrong
        requestIconView.contentMode = .scaleAspectFit

        requestTitleLabel.text = L(L10n.FriendList.friendRequest)
        requestTitleLabel.font = .systemFont(ofSize: 13.sf)
        requestTitleLabel.textColor = t.text

        requestCountLabel.font = .systemFont(ofSize: 13.sf)
        requestCountLabel.textColor = t.text

        let chevronImg = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.sf, weight: .medium))
        requestChevron.image = chevronImg
        requestChevron.tintColor = t.textDisabled
        requestChevron.contentMode = .scaleAspectFit

        requestPillView.addSubview(requestIconView)
        requestPillView.addSubview(requestTitleLabel)
        requestPillView.addSubview(requestCountLabel)
        requestPillView.addSubview(requestChevron)

        let tap = UITapGestureRecognizer(target: self, action: #selector(requestPillTapped))
        requestPillView.addGestureRecognizer(tap)
        requestPillView.isUserInteractionEnabled = true

        view.addSubview(requestPillView)
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
        emptyLabel.text = "Không tìm thấy kết quả bạn bè"
        emptyLabel.font = .systemFont(ofSize: 14.sf)
        emptyLabel.textColor = UIColor.theme.textDisabled
        emptyLabel.textAlignment = .left
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)
    }

    private func updateContent() {
        guard isNodeLoaded else { return }

        let isEmpty = currentGroups.isEmpty
        tableNode.isHidden = isEmpty
        emptyLabel.isHidden = !isEmpty || !isSearching
        requestPillView.isHidden = false

        subtitleLabel.isHidden = totalFriendCount == 0
        subtitleLabel.text = "\(totalFriendCount) " + L(L10n.FriendList.friendCount)

        requestCountLabel.text = "\(friendRequestReceivedCount) " + L(L10n.FriendList.received) + " • " + "\(friendRequestSentCount) " + L(L10n.FriendList.sent)

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

        transition.updateFrame(view: headerView, frame: CGRect(x: 0, y: headerY, width: size.width, height: headerH))
        let backSize: CGFloat = 36.swh
        transition.updateFrame(view: backButton, frame: CGRect(x: sideInset - 8.sw, y: (headerH - backSize) / 2, width: backSize, height: backSize))

        let headerContentW = size.width - (backSize + sideInset) * 2
        let headerSideInset = backSize + sideInset
        let titleH: CGFloat = 22.sh
        let subH: CGFloat = 18.sh
        
        if subtitleLabel.isHidden {
            let titleY = (headerH - titleH) / 2
            transition.updateFrame(view: titleLabel, frame: CGRect(x: headerSideInset, y: titleY, width: headerContentW, height: titleH))
        } else {
            let titleY = (headerH - titleH - subH) / 2
            transition.updateFrame(view: titleLabel, frame: CGRect(x: headerSideInset, y: titleY, width: headerContentW, height: titleH))
            transition.updateFrame(view: subtitleLabel, frame: CGRect(x: headerSideInset, y: titleY + titleH, width: headerContentW, height: subH))
        }

        addFriendButton.sizeToFit()
        let addW = addFriendButton.frame.width + 16.sw
        let addH: CGFloat = 32.sh
        transition.updateFrame(view: addFriendButton, frame: CGRect(x: size.width - sideInset - addW, y: (headerH - addH) / 2, width: addW, height: addH))

        let searchY = headerY + headerH + 8.sh
        let searchH: CGFloat = 56.sh
        transition.updateFrame(view: searchContainerView, frame: CGRect(x: sideInset, y: searchY, width: size.width - sideInset * 2, height: searchH))

        let iconSize: CGFloat = 18.swh
        let iconX: CGFloat = 12.sw
        transition.updateFrame(view: searchIconView, frame: CGRect(x: iconX, y: (searchH - iconSize) / 2, width: iconSize, height: iconSize))
        transition.updateFrame(view: searchTextField, frame: CGRect(x: iconX + iconSize + 8.sw, y: 0, width: size.width - sideInset * 2 - iconX - iconSize - 20.sw, height: searchH))

        var contentY = searchY + searchH + 16.sh
        
        if !emptyLabel.isHidden {
            let emptyH: CGFloat = 30.sh
            transition.updateFrame(view: emptyLabel, frame: CGRect(x: sideInset, y: contentY, width: size.width - sideInset * 2, height: emptyH))
            contentY += emptyH + 8.sh
        }
        
        if !requestPillView.isHidden {
            let pillH: CGFloat = 56.sh
            transition.updateFrame(view: requestPillView, frame: CGRect(x: sideInset, y: contentY, width: size.width - sideInset * 2, height: pillH))
            
            let pillInset: CGFloat = 14.sw
            let reqIconSize: CGFloat = 30.swh
            transition.updateFrame(view: requestIconView, frame: CGRect(x: pillInset, y: (pillH - reqIconSize) / 2, width: reqIconSize, height: reqIconSize))

            let chevW: CGFloat = 16.swh
            let chevX = size.width - sideInset * 2 - pillInset - chevW
            transition.updateFrame(view: requestChevron, frame: CGRect(x: chevX, y: (pillH - chevW) / 2, width: chevW, height: chevW))

            let textX = pillInset + reqIconSize + 12.sw
            let textW = chevX - textX - 8.sw
            transition.updateFrame(view: requestTitleLabel, frame: CGRect(x: textX, y: 8.sh, width: textW, height: 22.sh))
            transition.updateFrame(view: requestCountLabel, frame: CGRect(x: textX, y: 28.sh, width: textW, height: 18.sh))

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

        backButton.tintColor = t.textStrong
        titleLabel.textColor = t.textStrong
        subtitleLabel.textColor = t.textDisabled
        searchContainerView.backgroundColor = t.secondary
        searchIconView.tintColor = t.textDisabled
        searchTextField.textColor = t.textStrong
        requestPillView.backgroundColor = t.secondary
        requestIconView.tintColor = t.textStrong
        requestTitleLabel.textColor = t.text
        requestCountLabel.textColor = t.text
        requestChevron.tintColor = t.textDisabled
        emptyLabel.textColor = t.textDisabled

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
    private let onlineIndicatorNode: ASDisplayNode
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
        self.onlineIndicatorNode = ASDisplayNode()
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
        onlineIndicatorNode.cornerRadius = dotSize / 2
        let statusColor: UIColor
        switch user.status {
        case "online":
            statusColor = UIColor(red: 0.3, green: 0.78, blue: 0.47, alpha: 1)
        case "idle":
            statusColor = .orange
        case "dnd":
            statusColor = .red
        default:
            statusColor = user.online ? UIColor(red: 0.3, green: 0.78, blue: 0.47, alpha: 1) : UIColor.gray
        }
        onlineIndicatorNode.backgroundColor = statusColor

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
        interaction.onCallFriend(friend)
    }

    @objc private func messageTapped() {
        interaction.onMessageFriend(friend)
    }
}
