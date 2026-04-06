import AsyncDisplayKit
import UIKit

final class MessageReactionDetailSheetController: ViewController {

    private let reactions: [ParsedReaction]
    private let display: ChatMessageDisplay
    private let context: AccountContext
    private let reactionMemberLookupClanId: Int64
    private let initialEmojiId: String
    private let onRemoveReaction: (String, String, Int32, ChatMessageDisplay) -> Void

    private var sheetNode: MessageReactionDetailSheetNode {
        displayNode as! MessageReactionDetailSheetNode
    }

    init(
        reactions: [ParsedReaction],
        display: ChatMessageDisplay,
        context: AccountContext,
        reactionMemberLookupClanId: Int64,
        initialEmojiId: String,
        onRemoveReaction: @escaping (String, String, Int32, ChatMessageDisplay) -> Void
    ) {
        self.reactions = reactions
        self.display = display
        self.context = context
        self.reactionMemberLookupClanId = reactionMemberLookupClanId
        self.initialEmojiId = initialEmojiId
        self.onRemoveReaction = onRemoveReaction
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Hide
        self.blocksBackgroundWhenInOverlay = true
    }

    required init(coder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        self.displayNode = MessageReactionDetailSheetNode(
            reactions: reactions,
            display: display,
            context: context,
            reactionMemberLookupClanId: reactionMemberLookupClanId,
            initialEmojiId: initialEmojiId,
            onDimTapped: { [weak self] in self?.animateDismiss(completion: nil) },
            onRemoveReaction: { [weak self] emojiId, shortname, count, display in
                self?.onRemoveReaction(emojiId, shortname, count, display)
            }
        )
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        sheetNode.updateLayout(layout: layout, transition: transition)
    }

    func animateIn() {
        sheetNode.animateIn()
    }

    private func animateDismiss(completion: (() -> Void)?) {
        sheetNode.animateOut { [weak self] in
            self?.dismiss(animated: false)
            completion?()
        }
    }
}

private final class MessageReactionDetailSheetNode: ASDisplayNode, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UITableViewDelegate, UITableViewDataSource, UIGestureRecognizerDelegate, UIScrollViewDelegate {

    private var reactions: [ParsedReaction]
    private let display: ChatMessageDisplay
    private let context: AccountContext
    private let reactionMemberLookupClanId: Int64
    private var selectedEmojiId: String
    private let onDimTapped: () -> Void
    private let onRemoveReaction: (String, String, Int32, ChatMessageDisplay) -> Void

    private let dimmingNode = ASDisplayNode()
    private let containerNode = ASDisplayNode()
    private let handleNode = ASDisplayNode()

    private let collectionView: UICollectionView
    private let headerContainer = UIView()
    private let emojiTitleLabel = UILabel()
    private let trashButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyStateLabel = UILabel()

    private var panGesture: UIPanGestureRecognizer!
    private var panStartY: CGFloat = 0
    private var containerHeight: CGFloat = 0
    private var validLayout: ContainerViewLayout?

    private let handleH: CGFloat = 25
    private let tabBarH: CGFloat = 52
    private let headerRowH: CGFloat = 44
    private let tableMinH: CGFloat = 220

    init(
        reactions: [ParsedReaction],
        display: ChatMessageDisplay,
        context: AccountContext,
        reactionMemberLookupClanId: Int64,
        initialEmojiId: String,
        onDimTapped: @escaping () -> Void,
        onRemoveReaction: @escaping (String, String, Int32, ChatMessageDisplay) -> Void
    ) {
        self.reactions = reactions
        self.display = display
        self.context = context
        self.reactionMemberLookupClanId = reactionMemberLookupClanId
        self.selectedEmojiId = reactions.contains(where: { $0.emojiId == initialEmojiId }) ? initialEmojiId : (reactions.first?.emojiId ?? initialEmojiId)
        self.onDimTapped = onDimTapped
        self.onRemoveReaction = onRemoveReaction

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init()

        dimmingNode.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimmingNode.alpha = 0

        let t = UIColor.theme
        containerNode.backgroundColor = t.primary
        containerNode.cornerRadius = 14
        containerNode.clipsToBounds = true

        handleNode.backgroundColor = t.textDisabled
        handleNode.cornerRadius = 2.5

        addSubnode(dimmingNode)
        addSubnode(containerNode)
        containerNode.addSubnode(handleNode)
    }

    override func didLoad() {
        super.didLoad()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimmingNode.view.addGestureRecognizer(tap)

        containerNode.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        let t = UIColor.theme
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(ReactionEmojiTabCell.self, forCellWithReuseIdentifier: ReactionEmojiTabCell.reuseId)
        containerNode.view.addSubview(collectionView)

        headerContainer.backgroundColor = .clear
        containerNode.view.addSubview(headerContainer)

        emojiTitleLabel.font = UIFont.systemFont(ofSize: 15.sf, weight: .semibold)
        emojiTitleLabel.textColor = t.textStrong
        emojiTitleLabel.lineBreakMode = .byTruncatingTail
        headerContainer.addSubview(emojiTitleLabel)

        var trashCfg = UIButton.Configuration.plain()
        trashCfg.image = UIImage(systemName: "trash.fill")
        trashCfg.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        trashCfg.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        trashButton.configuration = trashCfg
        trashButton.tintColor = .white
        trashButton.backgroundColor = UIColor.systemRed
        trashButton.layer.cornerRadius = 6
        trashButton.addTarget(self, action: #selector(trashTapped), for: .touchUpInside)
        headerContainer.addSubview(trashButton)

        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 56, bottom: 0, right: 0)
        tableView.backgroundColor = t.primary
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ReactionParticipantCell.self, forCellReuseIdentifier: ReactionParticipantCell.reuseId)
        tableView.delaysContentTouches = false
        containerNode.view.addSubview(tableView)

        emptyStateLabel.font = UIFont.systemFont(ofSize: 15.sf, weight: .regular)
        emptyStateLabel.textColor = t.textDisabled
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.text = Self.emptyReactionsText
        emptyStateLabel.isHidden = true
        containerNode.view.addSubview(emptyStateLabel)

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        containerNode.view.addGestureRecognizer(panGesture)
        tableView.panGestureRecognizer.require(toFail: panGesture)

        refreshFullUI()
    }

    private static var emptyReactionsText: String {
        NSLocalizedString("reactions.empty", tableName: nil, bundle: .main, value: "No reactions", comment: "Shown when all reactions were removed in the detail sheet")
    }

    @objc private func dimTapped() {
        onDimTapped()
    }

    @objc private func trashTapped() {
        performRemoveForCurrentUser(onEmojiId: selectedEmojiId)
    }

    private func performRemoveForCurrentUser(onEmojiId emojiId: String) {
        guard let uid = context.currentUser?.id else { return }
        guard let idx = reactions.firstIndex(where: { $0.emojiId == emojiId }),
              let entry = reactions[idx].senders.first(where: { $0.userId == uid }) else { return }
        let eid = reactions[idx].emojiId
        let em = reactions[idx].emoji
        let c = Int32(entry.count)
        applyOptimisticRemoveCurrentUser(forEmojiId: eid, myUserId: uid)
        onRemoveReaction(eid, em, c, display)
    }

    private func neighborEmojiIdAfterRemoving(at removedIndex: Int, oldTabs: [ParsedReaction], newTabs: [ParsedReaction]) -> String? {
        let remaining = Set(newTabs.map(\.emojiId))
        var i = removedIndex - 1
        while i >= 0 {
            let id = oldTabs[i].emojiId
            if remaining.contains(id) { return id }
            i -= 1
        }
        i = removedIndex + 1
        while i < oldTabs.count {
            let id = oldTabs[i].emojiId
            if remaining.contains(id) { return id }
            i += 1
        }
        return newTabs.first?.emojiId
    }

    private func applyOptimisticRemoveCurrentUser(forEmojiId emojiId: String, myUserId uid: String) {
        let oldTabs = reactions
        guard let oldIndex = oldTabs.firstIndex(where: { $0.emojiId == emojiId }) else { return }
        let rx = oldTabs[oldIndex]
        guard rx.senders.contains(where: { $0.userId == uid }) else { return }

        var newTabs = oldTabs
        let newSenders = rx.senders.filter { $0.userId != uid }
        if newSenders.isEmpty {
            newTabs.remove(at: oldIndex)
            selectedEmojiId = neighborEmojiIdAfterRemoving(at: oldIndex, oldTabs: oldTabs, newTabs: newTabs) ?? ""
        } else {
            let sum = newSenders.reduce(0) { $0 + $1.count }
            newTabs[oldIndex] = ParsedReaction(
                emojiId: rx.emojiId,
                emoji: rx.emoji,
                count: sum,
                senders: newSenders,
                isMe: false
            )
            selectedEmojiId = emojiId
        }
        reactions = newTabs
        refreshFullUI()
    }

    private func refreshFullUI() {
        let showChrome = !reactions.isEmpty
        collectionView.isHidden = !showChrome
        headerContainer.isHidden = !showChrome
        emptyStateLabel.isHidden = showChrome
        collectionView.reloadData()
        refreshHeaderAndTable()
        view.setNeedsLayout()
        if let layout = validLayout {
            updateLayout(layout: layout, transition: .immediate)
        }
        if showChrome, let sidx = reactions.firstIndex(where: { $0.emojiId == selectedEmojiId }), sidx < reactions.count {
            collectionView.scrollToItem(at: IndexPath(item: sidx, section: 0), at: .centeredHorizontally, animated: true)
        }
    }

    private func refreshHeaderAndTable() {
        let rx = reactions.first(where: { $0.emojiId == selectedEmojiId })
        emojiTitleLabel.text = rx?.emoji ?? ""
        if let uid = context.currentUser?.id, let r = rx, r.senders.contains(where: { $0.userId == uid }) {
            trashButton.isHidden = false
        } else {
            trashButton.isHidden = true
        }
        tableView.reloadData()
    }

    private func selectEmojiId(_ id: String) {
        guard selectedEmojiId != id else { return }
        selectedEmojiId = id
        collectionView.reloadData()
        refreshHeaderAndTable()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        reactions.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ReactionEmojiTabCell.reuseId, for: indexPath) as! ReactionEmojiTabCell
        let r = reactions[indexPath.item]
        cell.configure(reaction: r, selected: r.emojiId == selectedEmojiId)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectEmojiId(reactions[indexPath.item].emojiId)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: 52, height: 40)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        reactions.first(where: { $0.emojiId == selectedEmojiId })?.senders.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ReactionParticipantCell.reuseId, for: indexPath) as! ReactionParticipantCell
        guard let rx = reactions.first(where: { $0.emojiId == selectedEmojiId }),
              indexPath.row < rx.senders.count else { return cell }
        let sender = rx.senders[indexPath.row]
        let visual = Self.resolveReactionParticipantVisual(
            sender: sender,
            context: context,
            clanId: reactionMemberLookupClanId
        )
        cell.configure(displayName: visual.name, avatarURLString: visual.avatarURL, reactionCount: sender.count, theme: ThemeManager.shared.attributes)
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        56
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let uid = context.currentUser?.id,
              let rx = reactions.first(where: { $0.emojiId == selectedEmojiId }),
              indexPath.row < rx.senders.count else { return nil }
        let sender = rx.senders[indexPath.row]
        guard sender.userId == uid else { return nil }

        let remove = UIContextualAction(style: .destructive, title: Self.removeActionTitle) { [weak self] _, _, done in
            guard let self else { done(false); return }
            self.performRemoveForCurrentUser(onEmojiId: rx.emojiId)
            done(true)
        }
        remove.image = UIImage(systemName: "trash.fill")
        remove.backgroundColor = UIColor.systemRed
        let cfg = UISwipeActionsConfiguration(actions: [remove])
        cfg.performsFirstActionWithFullSwipe = true
        return cfg
    }

    private static var removeActionTitle: String {
        NSLocalizedString("reactions.remove", tableName: nil, bundle: .main, value: "Remove", comment: "Remove reaction swipe action")
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let layout = validLayout else { return }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .began:
            panStartY = containerNode.frame.origin.y
        case .changed:
            let offsetY = max(0, translation.y)
            containerNode.frame.origin.y = panStartY + offsetY
            dimmingNode.alpha = 1 - offsetY / max(containerHeight, 1)
        case .ended, .cancelled:
            if translation.y > containerHeight * 0.3 || velocity.y > 500 {
                onDimTapped()
            } else {
                let targetY = layout.size.height - containerHeight
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: []) {
                    self.containerNode.frame.origin.y = targetY
                    self.dimmingNode.alpha = 1
                }
            }
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        let vel = panGesture.velocity(in: view)
        return tableView.contentOffset.y <= 0 && vel.y > 0
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === tableView, tableView.contentOffset.y < 0 {
            tableView.contentOffset.y = 0
        }
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        let bounds = CGRect(origin: .zero, size: layout.size)
        let safeBottom = layout.intrinsicInsets.bottom
        let screenW = layout.size.width

        transition.updateFrame(node: dimmingNode, frame: bounds)

        let showChrome = !reactions.isEmpty
        let tabH = showChrome ? tabBarH : 0
        let headH = showChrome ? headerRowH : 0
        let maxTableH = layout.size.height * 0.5
        let rowCount = reactions.isEmpty ? 0 : tableView.numberOfRows(inSection: 0)
        let tableH: CGFloat
        if reactions.isEmpty {
            tableH = 140
        } else {
            tableH = min(maxTableH, max(tableMinH, CGFloat(rowCount) * 56))
        }
        let contentH = handleH + tabH + headH + tableH + 8
        let maxSheetH = layout.size.height * 0.62
        containerHeight = min(contentH + safeBottom, maxSheetH)

        let containerY = layout.size.height - containerHeight
        transition.updateFrame(node: containerNode, frame: CGRect(x: 0, y: containerY, width: screenW, height: containerHeight))
        transition.updateFrame(node: handleNode, frame: CGRect(x: (screenW - 36) / 2, y: 8, width: 36, height: 5))

        collectionView.frame = CGRect(x: 0, y: handleH, width: screenW, height: tabH)
        headerContainer.frame = CGRect(x: 0, y: handleH + tabH, width: screenW, height: headH)
        emojiTitleLabel.frame = CGRect(x: 16, y: 0, width: screenW - 16 - 8 - 44, height: headH)
        trashButton.frame = CGRect(x: screenW - 44 - 12, y: (headH - 36) / 2, width: 36, height: 36)

        let tvY = handleH + tabH + headH
        let tvH = containerHeight - tvY - safeBottom - 8
        tableView.frame = CGRect(x: 0, y: tvY, width: screenW, height: max(120, tvH))
        emptyStateLabel.frame = CGRect(x: 24, y: tvY + max(0, (tvH - 48) / 2), width: screenW - 48, height: 80)
    }

    func animateIn() {
        guard let layout = validLayout else { return }
        let fromY = layout.size.height
        let toY = layout.size.height - containerHeight
        containerNode.frame.origin.y = fromY
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: []) {
            self.dimmingNode.alpha = 1
            self.containerNode.frame.origin.y = toY
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        guard let layout = validLayout else {
            completion()
            return
        }
        let bottomY = layout.size.height
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
            self.dimmingNode.alpha = 0
            self.containerNode.frame.origin.y = bottomY
        }) { _ in
            completion()
        }
    }

    private static func resolveReactionParticipantVisual(
        sender: ParsedReactionSender,
        context: AccountContext,
        clanId: Int64
    ) -> (name: String, avatarURL: String?) {
        let uid = sender.userId
        if let cur = context.currentUser, cur.id == uid {
            let name: String = {
                if !cur.displayName.isEmpty { return cur.displayName }
                if !cur.username.isEmpty { return cur.username }
                return uid
            }()
            return (name, cur.avatarURL?.absoluteString)
        }
        if clanId != 0, let id64 = Int64(uid), let list = context.engine.clanData.getClanUsers(clanId: clanId) {
            for cu in list.clanUsers where cu.user.id == id64 {
                let name: String = {
                    if !cu.clanNick.isEmpty { return cu.clanNick }
                    if !cu.user.displayName.isEmpty { return cu.user.displayName }
                    if !cu.user.username.isEmpty { return cu.user.username }
                    return uid
                }()
                let avatar: String? = {
                    if !cu.clanAvatar.isEmpty { return cu.clanAvatar }
                    if !cu.user.avatarURL.isEmpty { return cu.user.avatarURL }
                    return nil
                }()
                return (name, avatar)
            }
        }
        let profile = context.account.postbox.read { tx in tx.getProfile(userId: uid) }
        let name: String = {
            if let h = sender.nameHint, !h.isEmpty { return h }
            if let p = profile {
                if let d = p.displayName, !d.isEmpty { return d }
                if !p.username.isEmpty { return p.username }
            }
            return uid
        }()
        return (name, profile?.avatarUrl)
    }
}

private final class ReactionEmojiTabCell: UICollectionViewCell {
    static let reuseId = "ReactionEmojiTabCell"

    private let imageView = UIImageView()
    private let countLabel = UILabel()
    private var task: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true

        imageView.contentMode = .scaleAspectFit
        contentView.addSubview(imageView)
        countLabel.font = UIFont.systemFont(ofSize: 12.sf, weight: .semibold)
        contentView.addSubview(countLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
        imageView.image = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = CGRect(x: 6, y: (bounds.height - 22) / 2, width: 22, height: 22)
        countLabel.frame = CGRect(x: 30, y: 0, width: bounds.width - 34, height: bounds.height)
    }

    func configure(reaction: ParsedReaction, selected: Bool) {
        let t = UIColor.theme
        countLabel.text = "\(reaction.count)"
        countLabel.textColor = t.textStrong
        if selected {
            contentView.backgroundColor = t.secondary
        } else {
            contentView.backgroundColor = .clear
        }

        task?.cancel()
        imageView.image = nil
        if let url = MezonConfig.emojiResourceURL(emojiId: reaction.emojiId, imgproxyFitSide: 32) {
            let key = url.absoluteString
            if let img = ImageCache.shared.image(forKey: key) {
                imageView.image = img
            } else {
                task = URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data, let image = UIImage.animatedImage(from: data) ?? UIImage.decodeImage(from: data) else { return }
                    ImageCache.shared.setImage(image, data: data, forKey: key)
                    DispatchQueue.main.async { [weak self] in
                        self?.imageView.image = image
                    }
                }
                task?.resume()
            }
        }
    }
}

private final class ReactionParticipantCell: UITableViewCell {
    static let reuseId = "ReactionParticipantCell"

    private let avatarView = UIImageView()
    private let placeholderLabel = UILabel()
    private let nameLabel = UILabel()
    private let countLabel = UILabel()
    private var task: URLSessionDataTask?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 20
        contentView.addSubview(avatarView)

        placeholderLabel.textAlignment = .center
        placeholderLabel.font = UIFont.systemFont(ofSize: 14.sf, weight: .semibold)
        placeholderLabel.textColor = .white
        avatarView.addSubview(placeholderLabel)

        nameLabel.font = UIFont.systemFont(ofSize: 15.sf, weight: .semibold)
        contentView.addSubview(nameLabel)

        countLabel.font = UIFont.systemFont(ofSize: 13.sf, weight: .regular)
        contentView.addSubview(countLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
        avatarView.image = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        avatarView.frame = CGRect(x: 12, y: (bounds.height - 40) / 2, width: 40, height: 40)
        placeholderLabel.frame = avatarView.bounds
        nameLabel.frame = CGRect(x: 60, y: 10, width: bounds.width - 120, height: 20)
        countLabel.frame = CGRect(x: 60, y: 30, width: bounds.width - 120, height: 18)
    }

    func configure(displayName: String, avatarURLString: String?, reactionCount: Int, theme: ThemeAttributes) {
        nameLabel.textColor = theme.textStrong
        countLabel.textColor = theme.textDisabled

        nameLabel.text = displayName
        countLabel.text = "×\(reactionCount)"

        let initial = String(displayName.prefix(1)).uppercased()
        placeholderLabel.text = initial

        task?.cancel()
        avatarView.image = nil
        avatarView.backgroundColor = UIColor.colorAvatarDefault

        if let urlStr = avatarURLString, let url = URL(string: urlStr) {
            let key = url.absoluteString
            if let img = ImageCache.shared.image(forKey: key) {
                avatarView.image = img
                placeholderLabel.isHidden = true
            } else {
                placeholderLabel.isHidden = false
                task = URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data, let image = UIImage.decodeImage(from: data) else { return }
                    ImageCache.shared.setImage(image, data: data, forKey: key)
                    DispatchQueue.main.async { [weak self] in
                        self?.avatarView.image = image
                        self?.placeholderLabel.isHidden = true
                    }
                }
                task?.resume()
            }
        } else {
            placeholderLabel.isHidden = false
        }
    }
}
