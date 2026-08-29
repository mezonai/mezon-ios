import AsyncDisplayKit

struct FriendRequestInteraction {
    let onBackTapped: () -> Void
    let onSearchTapped: () -> Void
    let onAcceptFriend: (Mezon_Api_Friend) -> Void
    let onRejectFriend: (Mezon_Api_Friend) -> Void
}

final class FriendRequestContainerNode: ASDisplayNode {

    private lazy var gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.startPoint = CGPoint(x: 0.5, y: 0)
        gl.endPoint   = CGPoint(x: 0.5, y: 1)
        return gl
    }()

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    private let searchPillView = UIView()
    private let searchPillLabel = UILabel()
    private let searchPillChevron = UIImageView()
    private let incomingTitleLabel = UILabel()

    private let tableNode: ASTableNode

    private let emptyContainerView = UIView()
    private let emptyImageView = UIImageView()
    private let emptyTitleLabel = UILabel()
    private let emptyDescLabel = UILabel()

    private var currentFriends: [Mezon_Api_Friend] = []
    private let interaction: FriendRequestInteraction
    private let disposables = DisposableSet()
    private var validLayout: (size: CGSize, safeTop: CGFloat, bottomInset: CGFloat)?
    private var previousLayout: (size: CGSize, safeTop: CGFloat, bottomInset: CGFloat)?

    init(signal: Signal<FriendRequestState, NoError>, interaction: FriendRequestInteraction) {
        tableNode = ASTableNode(style: .plain)
        self.interaction = interaction
        super.init()

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                let oldFriends = self.currentFriends
                self.currentFriends = newState.receivedRequests
                self.updateContent(oldFriends: oldFriends, newFriends: self.currentFriends)
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
        setupSearchPill()
        setupIncomingTitle()
        setupTableView()
        setupEmptyState()

        if validLayout != nil {
            applyLayout(transition: .immediate)
        }

        updateContent(oldFriends: [], newFriends: currentFriends)
    }

    private func setupHeader() {
        let t = UIColor.theme
        let chevronImg = UIImage.mezonSystemImage("chevron.left", withConfiguration: MezonSymbolConfiguration(pointSize: 16.sf, weight: .semibold))
        backButton.setImage(chevronImg, for: .normal)
        backButton.tintColor = t.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        titleLabel.text = L(L10n.FriendRequest.title)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        titleLabel.textColor = t.textStrong
        titleLabel.textAlignment = .center

        headerView.addSubview(backButton)
        headerView.addSubview(titleLabel)
        view.addSubview(headerView)
    }

    private func setupSearchPill() {
        let t = UIColor.theme
        searchPillView.backgroundColor = t.secondary
        searchPillView.layer.cornerRadius = 12.sf
        searchPillView.clipsToBounds = true

        searchPillLabel.text = L(L10n.FriendRequest.addByTitle)
        searchPillLabel.font = .systemFont(ofSize: 14.sf)
        searchPillLabel.textColor = t.textStrong
        searchPillLabel.numberOfLines = 1

        let chevronImg = UIImage.mezonSystemImage("chevron.right", withConfiguration: MezonSymbolConfiguration(pointSize: 12.sf, weight: .medium))
        searchPillChevron.image = chevronImg
        searchPillChevron.tintColor = t.textStrong
        searchPillChevron.contentMode = .scaleAspectFit

        searchPillView.addSubview(searchPillLabel)
        searchPillView.addSubview(searchPillChevron)

        let tap = UITapGestureRecognizer(target: self, action: #selector(searchTapped))
        searchPillView.addGestureRecognizer(tap)
        searchPillView.isUserInteractionEnabled = true

        view.addSubview(searchPillView)
    }

    private func setupTableView() {
        tableNode.view.backgroundColor = .clear
        tableNode.view.separatorStyle = .none
        tableNode.view.rowHeight = UITableView.automaticDimension
        tableNode.view.estimatedRowHeight = 68.sh
        tableNode.dataSource = self
        tableNode.delegate = self
        addSubnode(tableNode)
    }

    private func setupIncomingTitle() {
        let t = UIColor.theme
        incomingTitleLabel.text = "Incoming Friend Request"
        incomingTitleLabel.font = .systemFont(ofSize: 14.sf)
        incomingTitleLabel.textColor = t.textStrong
        incomingTitleLabel.numberOfLines = 1
        incomingTitleLabel.textAlignment = .left
        view.addSubview(incomingTitleLabel)
    }

    private func setupEmptyState() {
        let t = UIColor.theme

        emptyContainerView.backgroundColor = .clear
        emptyContainerView.isHidden = true

        emptyImageView.image = UIImage(named: "Invite/NewEmptyFriendIcon")
        emptyImageView.contentMode = .scaleAspectFit
        emptyImageView.clipsToBounds = true

        emptyTitleLabel.font = .systemFont(ofSize: 18.sf, weight: .bold)
        emptyTitleLabel.textColor = t.textStrong
        emptyTitleLabel.textAlignment = .center
        emptyTitleLabel.numberOfLines = 0

        emptyDescLabel.font = .systemFont(ofSize: 14.sf)
        emptyDescLabel.textColor = t.textDisabled
        emptyDescLabel.textAlignment = .center
        emptyDescLabel.numberOfLines = 0

        emptyContainerView.addSubview(emptyImageView)
        emptyContainerView.addSubview(emptyTitleLabel)
        emptyContainerView.addSubview(emptyDescLabel)
        view.addSubview(emptyContainerView)
    }

    private func updateContent(oldFriends: [Mezon_Api_Friend], newFriends: [Mezon_Api_Friend]) {
        let isEmpty = newFriends.isEmpty
        tableNode.isHidden = isEmpty
        emptyContainerView.isHidden = !isEmpty
        incomingTitleLabel.isHidden = isEmpty

        if isEmpty {
            emptyTitleLabel.text = L(L10n.FriendRequest.emptyReceivedTitle)
            emptyDescLabel.text = L(L10n.FriendRequest.emptyReceivedDesc)
        }

        if isNodeLoaded, validLayout != nil {
            applyLayout(transition: .immediate)
        }

        applyFriendDiff(oldFriends: oldFriends, newFriends: newFriends)
    }

    private func applyFriendDiff(oldFriends: [Mezon_Api_Friend], newFriends: [Mezon_Api_Friend]) {
        guard isNodeLoaded else { return }
        let oldIds = oldFriends.map(\.user.id)
        let newIds = newFriends.map(\.user.id)

        if oldIds.isEmpty && newIds.isEmpty { return }
        if oldIds == newIds {
            tableNode.reloadData()
            return
        }

        let oldUniqueCount = Set(oldIds).count
        let newUniqueCount = Set(newIds).count
        if oldUniqueCount != oldIds.count || newUniqueCount != newIds.count {
            tableNode.reloadData()
            return
        }
        if oldIds.count == newIds.count && Set(oldIds) == Set(newIds) {
            tableNode.reloadData()
            return
        }

        let oldIndexById = Dictionary(oldIds.enumerated().map { ($1, $0) }, uniquingKeysWith: { _, new in new })
        let newIndexById = Dictionary(newIds.enumerated().map { ($1, $0) }, uniquingKeysWith: { _, new in new })
        let oldFriendById = Dictionary(oldFriends.map { ($0.user.id, $0) }, uniquingKeysWith: { _, new in new })
        let newFriendById = Dictionary(newFriends.map { ($0.user.id, $0) }, uniquingKeysWith: { _, new in new })

        let deletes = oldIndexById
            .filter { newIndexById[$0.key] == nil }
            .map { IndexPath(row: $0.value, section: 0) }
            .sorted { $0.row > $1.row }
        let inserts = newIndexById
            .filter { oldIndexById[$0.key] == nil }
            .map { IndexPath(row: $0.value, section: 0) }
            .sorted { $0.row < $1.row }
        let changedRows = newIndexById.compactMap { id, newIndex -> IndexPath? in
            guard oldIndexById[id] != nil,
                  let oldFriend = oldFriendById[id],
                  let newFriend = newFriendById[id],
                  friendDisplaySignature(oldFriend) != friendDisplaySignature(newFriend) else {
                return nil
            }
            return IndexPath(row: newIndex, section: 0)
        }

        if deletes.isEmpty && inserts.isEmpty && changedRows.isEmpty {
            tableNode.reloadData()
            return
        }

        tableNode.performBatchUpdates({
            if !deletes.isEmpty { tableNode.deleteRows(at: deletes, with: .automatic) }
            if !inserts.isEmpty { tableNode.insertRows(at: inserts, with: .automatic) }
        }, completion: { [weak self] _ in
            guard let self else { return }
            guard !changedRows.isEmpty else { return }
            self.tableNode.reloadRows(at: changedRows, with: .none)
        })
    }

    private func friendDisplaySignature(_ friend: Mezon_Api_Friend) -> String {
        let user = friend.user
        return [
            "\(friend.state)",
            "\(user.id)",
            user.displayName,
            user.username,
            user.avatarURL
        ].joined(separator: "|")
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

        let sideInset: CGFloat = 18.sw
        let headerH: CGFloat = 44.sh
        let headerY = safeTop

        transition.updateFrame(view: headerView, frame: CGRect(x: 0, y: headerY, width: size.width, height: headerH))
        let backSize: CGFloat = 36.swh
        transition.updateFrame(view: backButton, frame: CGRect(x: sideInset - 8.sw, y: (headerH - backSize) / 2, width: backSize, height: backSize))
        transition.updateFrame(view: titleLabel, frame: CGRect(x: backSize + sideInset, y: 0, width: size.width - (backSize + sideInset) * 2, height: headerH))

        let searchY = headerY + headerH + 10.sh
        let searchH: CGFloat = 44.sh
        transition.updateFrame(view: searchPillView, frame: CGRect(x: sideInset, y: searchY, width: size.width - sideInset * 2, height: searchH))

        let pillInset: CGFloat = 16.sw
        let chevronW: CGFloat = 16.swh
        let chevronX = size.width - sideInset * 2 - pillInset - chevronW
        transition.updateFrame(view: searchPillLabel, frame: CGRect(x: pillInset, y: 0, width: size.width - sideInset * 2 - pillInset * 2 - chevronW - 8.sw, height: searchH))
        transition.updateFrame(view: searchPillChevron, frame: CGRect(x: chevronX, y: (searchH - chevronW) / 2, width: chevronW, height: chevronW))

        let showsIncomingTitle = !currentFriends.isEmpty
        let incomingTitleY = searchY + searchH + 12.sh
        let incomingTitleH: CGFloat = showsIncomingTitle ? 20.sh : 0
        transition.updateFrame(
            view: incomingTitleLabel,
            frame: CGRect(x: sideInset, y: incomingTitleY, width: size.width - sideInset * 2, height: incomingTitleH)
        )

        let contentY = showsIncomingTitle ? (incomingTitleY + incomingTitleH + 8.sh) : (searchY + searchH + 12.sh)
        let contentH = size.height - contentY - bottomInset

        transition.updateFrame(node: tableNode, frame: CGRect(x: 0, y: contentY, width: size.width, height: contentH))

        let emptyW = size.width - sideInset * 2
        let imgSize: CGFloat = min(200.swh, emptyW * 0.55)
        let titleMaxWidth = emptyW
        let descMaxWidth = emptyW - 40.sw
        let titleH = ceil(emptyTitleLabel.sizeThatFits(
            CGSize(width: titleMaxWidth, height: CGFloat.greatestFiniteMagnitude)
        ).height)
        let descH = ceil(emptyDescLabel.sizeThatFits(
            CGSize(width: descMaxWidth, height: CGFloat.greatestFiniteMagnitude)
        ).height)
        let titleDescGap: CGFloat = 2.sh
        let emptyTotalH = imgSize + 24.sh + titleH + titleDescGap + descH
        let emptyY = contentY + max(0, (contentH - emptyTotalH) / 2)

        transition.updateFrame(view: emptyContainerView, frame: CGRect(x: sideInset, y: emptyY, width: emptyW, height: emptyTotalH))
        transition.updateFrame(view: emptyImageView, frame: CGRect(x: (emptyW - imgSize) / 2, y: 0, width: imgSize, height: imgSize))
        transition.updateFrame(view: emptyTitleLabel, frame: CGRect(x: 0, y: imgSize + 24.sh, width: emptyW, height: titleH))
        transition.updateFrame(view: emptyDescLabel, frame: CGRect(x: 20.sw, y: imgSize + 24.sh + titleH + titleDescGap, width: descMaxWidth, height: descH))

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
        searchPillView.backgroundColor = t.secondary
        searchPillChevron.tintColor = t.textStrong
        searchPillLabel.textColor = searchPillChevron.tintColor
        incomingTitleLabel.textColor = t.textStrong
        emptyTitleLabel.textColor = t.textStrong
        emptyDescLabel.textColor = t.textDisabled

        guard isNodeLoaded else { return }
        tableNode.reloadData()
    }

    @objc private func backTapped() { interaction.onBackTapped() }
    @objc private func searchTapped() { interaction.onSearchTapped() }

}

extension FriendRequestContainerNode: ASTableDataSource, ASTableDelegate {

    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        currentFriends.count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        let friend = currentFriends[indexPath.row]
        let interaction = interaction
        return {
            FriendRequestItemNode(friend: friend, interaction: interaction)
        }
    }
}

final class FriendRequestItemNode: ASCellNode, ASNetworkImageNodeDelegate {
    private let friend: Mezon_Api_Friend
    private let interaction: FriendRequestInteraction

    private let cardNode = ASDisplayNode()
    private let avatarNode = ASNetworkImageNode()
    private let textAvatarNode = TextAvatarNode(username: "", size: 44.swh, fontSize: 16.sf)
    private let displayNameNode = ASTextNode()
    private let usernameNode = ASTextNode()
    private let rejectButton = ASButtonNode()
    private let acceptButton = ASButtonNode()

    init(friend: Mezon_Api_Friend, interaction: FriendRequestInteraction) {
        self.friend = friend
        self.interaction = interaction
        super.init()
        automaticallyManagesSubnodes = true
        setupUI()
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear

        let t = UIColor.theme
        cardNode.backgroundColor = t.secondary
        cardNode.cornerRadius = 12.sf
        cardNode.clipsToBounds = true

        avatarNode.cornerRadius = 22.swh
        avatarNode.clipsToBounds = true
        avatarNode.contentMode = .scaleAspectFill
        avatarNode.defaultImage = nil
        avatarNode.shouldRenderProgressImages = false
        avatarNode.delegate = self

        let user = friend.user
        let name = user.displayName.isEmpty ? user.username : user.displayName

        let avatarRaw = user.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !avatarRaw.isEmpty {
            let proxied = ImgproxyURL.create(from: avatarRaw, width: 120, height: 120)
            if let url = URL(string: proxied) {
                avatarNode.url = url
                textAvatarNode.showSkeleton()
            } else {
                avatarNode.url = nil
                textAvatarNode.configure(username: user.username, fontSize: 16.sf)
            }
        } else {
            avatarNode.url = nil
            textAvatarNode.configure(username: user.username, fontSize: 16.sf)
        }

        displayNameNode.attributedText = NSAttributedString(
            string: name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf, weight: .semibold),
                .foregroundColor: t.textStrong
            ]
        )
        usernameNode.attributedText = NSAttributedString(
            string: user.username,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf),
                .foregroundColor: t.textDisabled
            ]
        )

        let xImg = UIImage.mezonSystemImage("xmark", withConfiguration: MezonSymbolConfiguration(pointSize: 12.sf, weight: .medium))?
            .withRenderingMode(.alwaysTemplate)
        rejectButton.setImage(xImg, for: .normal)
        rejectButton.tintColor = t.textStrong
        rejectButton.style.preferredSize = CGSize(width: 32.swh, height: 32.swh)
        rejectButton.addTarget(self, action: #selector(rejectTapped), forControlEvents: .touchUpInside)

        let checkImg = UIImage.mezonSystemImage("checkmark", withConfiguration: MezonSymbolConfiguration(pointSize: 14.sf, weight: .bold))?
            .withRenderingMode(.alwaysTemplate)
        acceptButton.setImage(checkImg, for: .normal)
        acceptButton.tintColor = UIColor.white
        acceptButton.backgroundColor = UIColor(red: 0.3, green: 0.78, blue: 0.47, alpha: 1)
        acceptButton.cornerRadius = 18.swh
        acceptButton.clipsToBounds = true
        acceptButton.style.preferredSize = CGSize(width: 36.swh, height: 36.swh)
        acceptButton.addTarget(self, action: #selector(acceptTapped), forControlEvents: .touchUpInside)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        avatarNode.style.preferredSize = CGSize(width: 44.swh, height: 44.swh)
        avatarNode.style.flexShrink = 0

        let avatarOverlay = ASOverlayLayoutSpec(
            child: textAvatarNode,
            overlay: avatarNode
        )
        avatarOverlay.style.flexShrink = 0

        let titleStack = ASStackLayoutSpec.vertical()
        titleStack.spacing = 2.sh
        titleStack.justifyContent = .center
        titleStack.alignItems = .start
        titleStack.children = [displayNameNode, usernameNode]
        titleStack.style.flexGrow = 1
        titleStack.style.flexShrink = 1

        let actionsStack = ASStackLayoutSpec.horizontal()
        actionsStack.spacing = 8.sw
        actionsStack.alignItems = .center
        actionsStack.children = [rejectButton, acceptButton]

        let contentStack = ASStackLayoutSpec.horizontal()
        contentStack.spacing = 12.sw
        contentStack.alignItems = .center
        contentStack.children = [avatarOverlay, titleStack, actionsStack]

        let paddedContent = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 12.sh, left: 14.sw, bottom: 12.sh, right: 14.sw),
            child: contentStack
        )
        let cardInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 4.sh, left: 18.sw, bottom: 4.sh, right: 18.sw),
            child: ASBackgroundLayoutSpec(child: paddedContent, background: cardNode)
        )
        return cardInset
    }

    @objc private func rejectTapped() {
        interaction.onRejectFriend(friend)
    }

    @objc private func acceptTapped() {
        interaction.onAcceptFriend(friend)
    }

    @objc func imageNode(_ imageNode: ASNetworkImageNode, didFailWithError error: Error) {
        guard imageNode === avatarNode else { return }
        textAvatarNode.configure(username: friend.user.username, fontSize: 16.sf)
    }

    @objc func imageNode(_ imageNode: ASNetworkImageNode, didLoad image: UIImage) {
        guard imageNode === avatarNode else { return }
        if image.size.width < 0.5 || image.size.height < 0.5 {
            textAvatarNode.configure(username: friend.user.username, fontSize: 16.sf)
        } else {
            textAvatarNode.showImageMode()
        }
    }
}
