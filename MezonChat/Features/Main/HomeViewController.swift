import UIKit
import AsyncDisplayKit

final class HomeViewController: BaseViewController {

    private let clanListVC: ClanListViewController
    private let channelListVC: ChannelListViewController
    private let context: AccountContext

    private let clanSidebarWidth: CGFloat = Constants.Layout.clanSidebarWidth

    init(context: AccountContext) {
        self.context = context
        self.clanListVC = ClanListViewController(context: context)
        self.channelListVC = ChannelListViewController(context: context)
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        embedChildren()
        bindClanSelection()
        bindChannelSelection()
        bindSidebarCallbacks()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        let clanLayout = layout.withUpdatedSize(CGSize(width: clanSidebarWidth, height: layout.size.height))
        clanListVC.containerLayoutUpdated(clanLayout, transition: transition)

        let channelWidth = max(0, layout.size.width - clanSidebarWidth)
        let channelLayout = layout.withUpdatedSize(CGSize(width: channelWidth, height: layout.size.height))
        channelListVC.containerLayoutUpdated(channelLayout, transition: transition)
    }

    private func embedChildren() {
        addChild(clanListVC)
        view.addSubview(clanListVC.view)
        clanListVC.view.translatesAutoresizingMaskIntoConstraints = false
        clanListVC.didMove(toParent: self)

        addChild(channelListVC)
        view.addSubview(channelListVC.view)
        channelListVC.view.translatesAutoresizingMaskIntoConstraints = false
        channelListVC.didMove(toParent: self)

        NSLayoutConstraint.activate([
            clanListVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            clanListVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            clanListVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            clanListVC.view.widthAnchor.constraint(equalToConstant: clanSidebarWidth),

            channelListVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            channelListVC.view.leadingAnchor.constraint(equalTo: clanListVC.view.trailingAnchor),
            channelListVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            channelListVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func bindSidebarCallbacks() {
        clanListVC.onThemeTapped = { [weak self] in self?.presentSheet(AppThemeViewController()) }
        clanListVC.onLanguageTapped = { [weak self] in self?.presentSheet(LanguageSettingsViewController()) }
        clanListVC.onMessagesTapped = { [weak self] in self?.pushMessages() }
        clanListVC.onProfileTapped = { [weak self] in self?.pushProfile() }
    }

    private func pushMessages() {
        let vc = MessagesViewController(context: context)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func pushProfile() {
        let vc = ProfileViewController(context: context)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func presentSheet(_ vc: UIViewController) {
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func bindClanSelection() {
        disposables.add(
            (clanListVC.selectedClanIdSignal |> deliverOnMainQueue)
                .start(next: { [weak self] clanId in
                    guard let clanId, let self else { return }
                    let name = self.clanListVC.clans.first(where: { $0.clanID == clanId })?.clanName ?? ""
                    self.channelListVC.configure(clanId: clanId, clanName: name)
                })
        )
    }

    private func bindChannelSelection() {
        disposables.add(
            (channelListVC.selectedChannelSignal |> deliverOnMainQueue)
                .start(next: { [weak self] channel in
                    guard let channel, let self else { return }
                    let chatVC = ChannelMessagesViewController(clanId: self.channelListVC.clanId, channel: channel, context: self.context)
                    self.navigationController?.pushViewController(chatVC, animated: true)
                })
        )
    }

    deinit { disposables.dispose() }
}
