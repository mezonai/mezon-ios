import UIKit
import AsyncDisplayKit

struct DirectMessagesInteraction {
    let onSelectDirectMessage: (Mezon_Api_ChannelDescription) -> Void
    let onAddFriendTapped: () -> Void
    let onSearchTapped: () -> Void
    let onBackTapped: () -> Void
    let onRefresh: () -> Void
}

final class DirectMessagesContainerNode: ASDisplayNode {

    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let addFriendButton = UIButton(type: .system)
    private let badgeLabel = UILabel()
    private let searchButton = UIButton(type: .system)
    private let tableView: UITableView

    private var state: DirectMessagesState = .empty
    private let interaction: DirectMessagesInteraction
    private let disposables = DisposableSet()
    private let context: AccountContext
    private var needsReloadOnLayout = false

    private let refreshControl = UIRefreshControl()
    private var validLayout: (size: CGSize, safeTop: CGFloat, bottomInset: CGFloat)?

    init(signal: Signal<DirectMessagesState, NoError>, interaction: DirectMessagesInteraction, context: AccountContext) {
        tableView = UITableView(frame: .zero, style: .plain)
        self.interaction = interaction
        self.context = context
        super.init()
        let t0 = UIColor.theme
        backgroundColor = t0.primary

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                self.state = newState
                
                if newState.incomingFriendRequestCount > 0 {
                    self.badgeLabel.text = "\(newState.incomingFriendRequestCount)"
                    self.badgeLabel.isHidden = false
                    self.view.setNeedsLayout() // ensure it layouts if intrinsic content size changes
                } else {
                    self.badgeLabel.isHidden = true
                }
                
                if self.tableView.frame.width > 0 {
                    self.tableView.reloadData()
                    if !self.badgeLabel.isHidden {
                        self.applyLayout(transition: .immediate)
                    }
                } else {
                    self.needsReloadOnLayout = true
                }
            })
        )
    }

    deinit { disposables.dispose() }

    override func didLoad() {
        super.didLoad()

        let t = UIColor.theme
        backgroundColor = t.primary
        view.backgroundColor = t.primary
        tableView.isOpaque = false
        tableView.backgroundView = nil

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 62.sh
        tableView.register(DmListItemCell.self, forCellReuseIdentifier: DmListItemCell.reuseId)
        tableView.dataSource = self
        tableView.delegate = self

        refreshControl.tintColor = .mezonTextPrimary
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        
        badgeLabel.backgroundColor = UIColor(red: 236/255.0, green: 56/255.0, blue: 50/255.0, alpha: 1.0)
        badgeLabel.textColor = .white
        badgeLabel.font = .systemFont(ofSize: 11.sf, weight: .semibold)
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 10.sh
        badgeLabel.clipsToBounds = true
        badgeLabel.isHidden = true

        titleLabel.text = L(L10n.Tab.messages)
        titleLabel.font = .systemFont(ofSize: 18.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong

        if #available(iOS 15.0, *) {
            var addCfg = UIButton.Configuration.filled()
            addCfg.image = UIImage(systemName: "person.badge.plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.sf))
            addCfg.title = " \(L(L10n.DirectMessage.addFriend))"
            addCfg.baseForegroundColor = UIColor.theme.textStrong
            addCfg.baseBackgroundColor = UIColor.theme.primary
            addCfg.cornerStyle = .capsule
            addCfg.contentInsets = NSDirectionalEdgeInsets(top: 6.sh, leading: 10.sw, bottom: 6.sh, trailing: 10.sw)
            addCfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
                var a = a; a.font = .systemFont(ofSize: 12.sf, weight: .medium); return a
            }
            addFriendButton.configuration = addCfg
        } else {
            addFriendButton.setImage(UIImage(systemName: "person.badge.plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.sf)), for: .normal)
            addFriendButton.setTitle(" \(L(L10n.DirectMessage.addFriend))", for: .normal)
            addFriendButton.titleLabel?.font = .systemFont(ofSize: 12.sf, weight: .medium)
            addFriendButton.setTitleColor(UIColor.theme.textStrong, for: .normal)
            addFriendButton.tintColor = UIColor.theme.textStrong
            addFriendButton.backgroundColor = UIColor.theme.primary
            addFriendButton.contentEdgeInsets = UIEdgeInsets(top: 6.sh, left: 10.sw, bottom: 6.sh, right: 10.sw)
            addFriendButton.layer.cornerRadius = 16
        }
        addFriendButton.addTarget(self, action: #selector(addFriendTapped), for: .touchUpInside)

        if #available(iOS 15.0, *) {
            var searchCfg = UIButton.Configuration.filled()
            searchCfg.image = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.sf))
            searchCfg.baseForegroundColor = UIColor.theme.textStrong
            searchCfg.baseBackgroundColor = UIColor.theme.primary
            searchCfg.cornerStyle = .capsule
            searchButton.configuration = searchCfg
        } else {
            searchButton.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.sf)), for: .normal)
            searchButton.tintColor = UIColor.theme.textStrong
            searchButton.backgroundColor = UIColor.theme.primary
            searchButton.layer.cornerRadius = 16
        }
        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)


        view.addSubview(headerView)
        view.addSubview(addFriendButton)
        view.addSubview(badgeLabel)
        view.addSubview(searchButton)
        view.addSubview(tableView)

        headerView.addSubview(titleLabel)

        if validLayout != nil {
            applyLayout(transition: .immediate)
        }

        applyTheme()
    }

    func updateLayout(size: CGSize, safeTop: CGFloat, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) {
        self.validLayout = (size, safeTop, bottomInset)
        applyLayout(transition: transition)
        if needsReloadOnLayout && tableView.frame.width > 0 {
            needsReloadOnLayout = false
            tableView.reloadData()
        }
    }

    private let headerTopPadding: CGFloat = 8.sh

    private func applyLayout(transition: ContainedViewLayoutTransition) {
        guard let (size, safeTop, bottomInset) = validLayout else {
            return
        }

        let topY = safeTop + headerTopPadding
        let sideInset: CGFloat = 18.sw

        let titleH: CGFloat = 44
        transition.updateFrame(view: headerView, frame: CGRect(x: 0, y: topY, width: size.width, height: titleH))
        transition.updateFrame(view: titleLabel, frame: CGRect(x: sideInset, y: 0, width: size.width - sideInset * 2, height: titleH))

        let actionY = topY + titleH + 10.sh
        let actionH: CGFloat = 32.sh
        let searchSize: CGFloat = 32.swh
        let addW = size.width - sideInset * 2 - searchSize - 10.sw
        let addFriendFrame = CGRect(x: sideInset, y: actionY, width: addW, height: actionH)
        transition.updateFrame(view: addFriendButton, frame: addFriendFrame)
        transition.updateFrame(view: searchButton, frame: CGRect(x: size.width - sideInset - searchSize, y: actionY, width: searchSize, height: searchSize))

        if !badgeLabel.isHidden {
            self.badgeLabel.sizeToFit()
            let badgeSize = self.badgeLabel.bounds.size
            let bw = max(20.sh, badgeSize.width + 10.sw)
            let bh: CGFloat = 20.sh
            let bx = addFriendFrame.maxX - bw - 10.sw
            let by = addFriendFrame.midY - bh / 2
            transition.updateFrame(view: badgeLabel, frame: CGRect(x: bx, y: by, width: bw, height: bh))
        }

        let tvTop = actionY + actionH + 8.sh
        let tvHeight = size.height - tvTop - bottomInset

        transition.updateFrame(view: tableView, frame: CGRect(x: 0, y: tvTop, width: size.width, height: tvHeight))


    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = t.primary
        if isNodeLoaded {
            view.backgroundColor = t.primary
        }
        titleLabel.textColor = t.textStrong

        guard isNodeLoaded else { return }

        if #available(iOS 15.0, *) {
            var addCfg = UIButton.Configuration.filled()
            addCfg.image = UIImage(systemName: "person.badge.plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.sf))
            addCfg.title = " \(L(L10n.DirectMessage.addFriend))"
            addCfg.baseForegroundColor = UIColor.theme.textStrong
            addCfg.baseBackgroundColor = UIColor.theme.primary
            addCfg.cornerStyle = .capsule
            addCfg.contentInsets = NSDirectionalEdgeInsets(top: 6.sh, leading: 10.sw, bottom: 6.sh, trailing: 10.sw)
            addCfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
                var a = a; a.font = .systemFont(ofSize: 12.sf, weight: .medium); return a
            }
            addFriendButton.configuration = addCfg
        } else {
            addFriendButton.setTitleColor(UIColor.theme.textStrong, for: .normal)
            addFriendButton.tintColor = UIColor.theme.textStrong
            addFriendButton.backgroundColor = UIColor.theme.primary
        }

        if #available(iOS 15.0, *) {
            var searchCfg = UIButton.Configuration.filled()
            searchCfg.image = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.sf))
            searchCfg.baseForegroundColor = UIColor.theme.textStrong
            searchCfg.baseBackgroundColor = UIColor.theme.primary
            searchCfg.cornerStyle = .capsule
            searchButton.configuration = searchCfg
        } else {
            searchButton.tintColor = UIColor.theme.textStrong
            searchButton.backgroundColor = UIColor.theme.primary
        }

        tableView.reloadData()
    }

    @objc private func addFriendTapped() { interaction.onAddFriendTapped() }
    @objc private func searchTapped() { interaction.onSearchTapped() }
    @objc private func handleRefresh() { interaction.onRefresh() }

    func endRefreshing() {
        refreshControl.endRefreshing()
    }
}

extension DirectMessagesContainerNode: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        state.directMessages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DmListItemCell.reuseId, for: indexPath) as! DmListItemCell
        cell.configure(channel: state.directMessages[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        interaction.onSelectDirectMessage(state.directMessages[indexPath.row])
    }
}
