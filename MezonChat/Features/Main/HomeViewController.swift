import UIKit
import Combine

final class HomeViewController: UIViewController {

    private let clanListVC: ClanListViewController
    private let channelListVC: ChannelListViewController

    private let clanVM: ClanListViewModel
    private let channelVM: ChannelListViewModel

    private let clanSidebarWidth: CGFloat = Constants.Layout.clanSidebarWidth
    private var cancellables = Set<AnyCancellable>()

    init(clanVM: ClanListViewModel, channelVM: ChannelListViewModel) {
        self.clanVM        = clanVM
        self.channelVM     = channelVM
        self.clanListVC    = ClanListViewController(viewModel: clanVM)
        self.channelListVC = ChannelListViewController(viewModel: channelVM)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        embedChildren()
        bindClanSelection()
        bindThemeButton()
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

    private func bindThemeButton() {
        clanListVC.onThemeTapped = { [weak self] in
            self?.presentSheet(AppThemeViewController())
        }
        clanListVC.onLanguageTapped = { [weak self] in
            self?.presentSheet(LanguageSettingsViewController())
        }
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
        clanVM.$selectedClanId
            .compactMap { [weak self] clanId -> (Int64, String)? in
                guard let clanId, let self else { return nil }
                let name = self.clanVM.clans.first(where: { $0.clanID == clanId })?.clanName ?? ""
                return (clanId, name)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] clanId, clanName in
                self?.channelListVC.configure(clanId: clanId, clanName: clanName)
            }
            .store(in: &cancellables)
    }
}
