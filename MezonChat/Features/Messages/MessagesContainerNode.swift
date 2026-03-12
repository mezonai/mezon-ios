import UIKit
import AsyncDisplayKit

struct MessagesInteraction {
    let onSelectDirectMessage: (Mezon_Api_ChannelDescription) -> Void
    let onAddFriendTapped: () -> Void
    let onSearchTapped: () -> Void
    let onBackTapped: () -> Void
}

final class MessagesContainerNode: ASDisplayNode {

    private let headerView      = UIView()
    private let titleLabel      = UILabel()
    private let backButton      = UIButton(type: .system)
    private let addFriendButton = UIButton(type: .system)
    private let searchButton    = UIButton(type: .system)
    private let tableView: UITableView
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let emptyLabel      = UILabel()

    private var state: MessagesState = .empty
    private let interaction: MessagesInteraction
    private let disposables = DisposableSet()
    private let context: AccountContext

    init(signal: Signal<MessagesState, NoError>, interaction: MessagesInteraction, context: AccountContext) {
        tableView = UITableView(frame: .zero, style: .plain)
        self.interaction = interaction
        self.context = context
        super.init()

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                self.state = newState
                self.tableView.reloadData()

                let showEmpty = newState.isEmpty && !newState.isLoading
                self.emptyLabel.isHidden = !showEmpty

                if newState.isLoading { self.loadingIndicator.startAnimating() }
                else { self.loadingIndicator.stopAnimating() }
            })
        )
    }

    deinit { disposables.dispose() }

    override func didLoad() {
        super.didLoad()

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = 72.sh
        tableView.register(DmListItemCell.self, forCellReuseIdentifier: DmListItemCell.reuseId)
        tableView.dataSource = self
        tableView.delegate   = self

        titleLabel.font = .systemFont(ofSize: 28.sf, weight: .bold)
        titleLabel.textColor = .mezonTextPrimary
        titleLabel.text = L(L10n.Tab.messages)

        var backCfg = UIButton.Configuration.plain()
        backCfg.image = UIImage(systemName: "chevron.left")
        backButton.configuration = backCfg
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        var addCfg = UIButton.Configuration.plain()
        addCfg.image = UIImage(systemName: "person.badge.plus")
        addCfg.title = " • \(L(L10n.DirectMessage.addFriend))"
        addFriendButton.configuration = addCfg
        addFriendButton.addTarget(self, action: #selector(addFriendTapped), for: .touchUpInside)

        var searchCfg = UIButton.Configuration.plain()
        searchCfg.image = UIImage(systemName: "magnifyingglass")
        searchButton.configuration = searchCfg
        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)

        loadingIndicator.hidesWhenStopped = true
        emptyLabel.font = .systemFont(ofSize: 15.sf)
        emptyLabel.textColor = .mezonTextSecondary
        emptyLabel.textAlignment = .center
        emptyLabel.text = L(L10n.ChannelMessages.emptyMessages)
        emptyLabel.isHidden = true

        for v in [headerView, tableView, loadingIndicator, emptyLabel] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        for v in [backButton, titleLabel, addFriendButton, searchButton] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview(v)
        }
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        let headerH: CGFloat = 56.sh
        let headerFrame = CGRect(x: 0, y: layout.safeInsets.top, width: layout.size.width, height: headerH)
        transition.updateFrame(view: headerView, frame: headerFrame)

        let tvFrame = CGRect(
            x: 0, y: headerFrame.maxY + 8.sh,
            width: layout.size.width,
            height: layout.size.height - headerFrame.maxY - 8.sh - layout.intrinsicInsets.bottom
        )
        transition.updateFrame(view: tableView, frame: tvFrame)

        let liS: CGFloat = 24.swh
        let liFrame = CGRect(x: (layout.size.width - liS) / 2, y: (layout.size.height - liS) / 2, width: liS, height: liS)
        transition.updateFrame(view: loadingIndicator, frame: liFrame)

        let elH: CGFloat = 44.sh
        transition.updateFrame(view: emptyLabel, frame: CGRect(x: 0, y: (layout.size.height - elH) / 2, width: layout.size.width, height: elH))

        let btnH: CGFloat = 44.swh
        let addW: CGFloat = 140.sw
        transition.updateFrame(view: backButton,      frame: CGRect(x: 4.sw, y: 0, width: btnH, height: headerH))
        transition.updateFrame(view: titleLabel,      frame: CGRect(x: 4.sw + btnH + 4.sw, y: 0, width: layout.size.width - 200.sw, height: headerH))
        transition.updateFrame(view: searchButton,    frame: CGRect(x: layout.size.width - 16.sw - btnH, y: 0, width: btnH, height: headerH))
        transition.updateFrame(view: addFriendButton, frame: CGRect(x: layout.size.width - 16.sw - btnH - 8.sw - addW, y: 0, width: addW, height: headerH))
    }

    @objc private func backTapped()      { interaction.onBackTapped() }
    @objc private func addFriendTapped() { interaction.onAddFriendTapped() }
    @objc private func searchTapped()    { interaction.onSearchTapped() }
}

extension MessagesContainerNode: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        state.directMessages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DmListItemCell.reuseId, for: indexPath) as! DmListItemCell
        cell.configure(channel: state.directMessages[indexPath.row], currentUserId: context.currentUser?.id)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        interaction.onSelectDirectMessage(state.directMessages[indexPath.row])
    }
}
