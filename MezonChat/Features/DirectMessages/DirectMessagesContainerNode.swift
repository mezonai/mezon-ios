import UIKit
import AsyncDisplayKit

struct DirectMessagesInteraction {
    let onSelectDirectMessage: (Mezon_Api_ChannelDescription) -> Void
    let onAddFriendTapped: () -> Void
    let onSearchTapped: () -> Void
    let onBackTapped: () -> Void
}

final class DirectMessagesContainerNode: ASDisplayNode {

    private let headerView = UIView()
    private let logoImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 18.swh
        iv.image = UIImage(named: "MezonLogo")
        return iv
    }()
    private let titleLabel = UILabel()
    private let addFriendButton = UIButton(type: .system)
    private let searchButton = UIButton(type: .system)
    private let tableView: UITableView

    private let emptyLabel = UILabel()
    private lazy var gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.startPoint = CGPoint(x: 0.5, y: 0)
        gl.endPoint   = CGPoint(x: 0.5, y: 1)
        return gl
    }()

    private var state: DirectMessagesState = .empty
    private let interaction: DirectMessagesInteraction
    private let disposables = DisposableSet()
    private let context: AccountContext

    init(signal: Signal<DirectMessagesState, NoError>, interaction: DirectMessagesInteraction, context: AccountContext) {
        tableView = UITableView(frame: .zero, style: .plain)
        self.interaction = interaction
        self.context = context
        super.init()

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                self.state = newState
                self.tableView.reloadData()
                self.emptyLabel.isHidden = !(newState.isEmpty && !newState.isLoading)

            })
        )
    }

    deinit { disposables.dispose() }

    override func didLoad() {
        super.didLoad()

        let t = UIColor.theme
        gradientLayer.colors = [t.primary.cgColor, t.primaryGradient.cgColor]
        layer.addSublayer(gradientLayer)

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 62.sh
        tableView.register(DmListItemCell.self, forCellReuseIdentifier: DmListItemCell.reuseId)
        tableView.dataSource = self
        tableView.delegate = self

        titleLabel.text = L(L10n.Tab.messages)
        titleLabel.font = .systemFont(ofSize: 18.sf, weight: .bold)
        titleLabel.textColor = .mezonTextPrimary

        var addCfg = UIButton.Configuration.filled()
        addCfg.image = UIImage(systemName: "person.badge.plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.sf))
        addCfg.title = " \(L(L10n.DirectMessage.addFriend))"
        addCfg.baseForegroundColor = UIColor.theme.textStrong
        addCfg.baseBackgroundColor = UIColor.theme.secondary
        addCfg.cornerStyle = .capsule
        addCfg.contentInsets = NSDirectionalEdgeInsets(top: 6.sh, leading: 10.sw, bottom: 6.sh, trailing: 10.sw)
        addCfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var a = a; a.font = .systemFont(ofSize: 12.sf, weight: .medium); return a
        }
        addFriendButton.configuration = addCfg
        addFriendButton.addTarget(self, action: #selector(addFriendTapped), for: .touchUpInside)

        var searchCfg = UIButton.Configuration.filled()
        searchCfg.image = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.sf))
        searchCfg.baseForegroundColor = UIColor.theme.textDisabled
        searchCfg.baseBackgroundColor = UIColor.theme.secondary
        searchCfg.cornerStyle = .capsule
        searchButton.configuration = searchCfg
        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)



        emptyLabel.font = .systemFont(ofSize: 15.sf)
        emptyLabel.textColor = .mezonTextSecondary
        emptyLabel.textAlignment = .center
        emptyLabel.text = L(L10n.ChannelMessages.emptyMessages)
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        headerView.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerView)
        view.addSubview(addFriendButton)
        view.addSubview(searchButton)
        view.addSubview(tableView)

        view.addSubview(emptyLabel)

        headerView.addSubview(titleLabel)
    }

    private var lastLayout: ContainerViewLayout?

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        lastLayout = layout
        applyLayout(transition: transition)
    }

    private func applyLayout(transition: ContainedViewLayoutTransition) {
        guard let layout = lastLayout else { return }
        let realSafeTop = view.safeAreaInsets.top
        let safeTop = realSafeTop > 20 ? realSafeTop : max(layout.safeInsets.top, 54)
        let topY = safeTop + 10.sh
        let sideInset: CGFloat = 18.sw

        let titleH: CGFloat = 36.sh
        transition.updateFrame(view: headerView, frame: CGRect(x: 0, y: topY, width: layout.size.width, height: titleH))
        transition.updateFrame(view: titleLabel, frame: CGRect(x: sideInset, y: 0, width: layout.size.width - sideInset * 2, height: titleH))

        let actionY = topY + titleH + 10.sh
        let actionH: CGFloat = 32.sh
        let searchSize: CGFloat = 32.swh
        let addW = layout.size.width - sideInset * 2 - searchSize - 10.sw
        transition.updateFrame(view: addFriendButton, frame: CGRect(x: sideInset, y: actionY, width: addW, height: actionH))
        transition.updateFrame(view: searchButton, frame: CGRect(x: layout.size.width - sideInset - searchSize, y: actionY, width: searchSize, height: searchSize))

        let tvTop = actionY + actionH + 8.sh
        transition.updateFrame(view: tableView, frame: CGRect(x: 0, y: tvTop, width: layout.size.width, height: layout.size.height - tvTop - layout.intrinsicInsets.bottom))

        transition.updateFrame(view: emptyLabel, frame: CGRect(x: 0, y: (layout.size.height - 44.sh) / 2, width: layout.size.width, height: 44.sh))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = CGRect(origin: .zero, size: layout.size)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        applyLayout(transition: .immediate)
    }

    @objc private func addFriendTapped() { interaction.onAddFriendTapped() }
    @objc private func searchTapped() { interaction.onSearchTapped() }
}

extension DirectMessagesContainerNode: UITableViewDataSource, UITableViewDelegate {

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
