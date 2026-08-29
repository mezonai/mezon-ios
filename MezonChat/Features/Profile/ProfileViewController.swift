import UIKit

final class ProfileViewController: ViewController {

    private let context: AccountContext

    private var profileNode: ProfileContainerNode {
        displayNode as! ProfileContainerNode
    }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        let node = ProfileContainerNode(context: context)
        node.onBackTapped = { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
        node.onSettingsTapped = { [weak self] in
            guard let self else { return }
            let vc = SettingsViewController(context: self.context)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        node.onTransferFundsTapped = { [weak self] in
            guard let self else { return }
            let payload = TransferQRPayload(
                receiverUserId: nil,
                walletAddress: nil,
                suggestedAmount: nil,
                note: nil,
                extraAttribute: nil,
                receiverDisplayName: nil
            )
            let vc = WalletTransferViewController(context: self.context, payload: payload)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        node.onEditProfileTapped = { [weak self] in
            guard let self else { return }
            let vc = ProfileSettingViewController(context: self.context, initialTab: .userProfile)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        node.onAvatarTapped = { [weak self] in self?.presentOnlineStatusSheet() }
        node.onDisplayNameTapped = { [weak self] in self?.presentOnlineStatusSheet() }
        node.onAddStatusTapped = { [weak self] in self?.presentAddStatusModal() }
        node.onYourFriendsTapped = { [weak self] in
            guard let self else { return }
            let vc = FriendListViewController(context: self.context)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        node.onHistoryTransactionTapped = { [weak self] in
            guard let self else { return }
            let vc = HistoryTransactionViewController(context: self.context)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        displayNode = node
    }

    private func presentOnlineStatusSheet() {
        let sheet = ProfileOnlineStatusSheetController(context: context)
        let nav = UINavigationController(rootViewController: sheet)
        nav.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            if let sp = nav.sheetPresentationController {
                sp.detents = [.medium(), .large()]
                sp.prefersGrabberVisible = true
                sp.preferredCornerRadius = 16
            }
        }
        present(nav, animated: true)
    }

    private func presentAddStatusModal() {
        let vc = ProfileAddStatusViewController(context: context)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            if let sp = nav.sheetPresentationController {
                sp.detents = [.large()]
                sp.prefersGrabberVisible = true
            }
        }
        present(nav, animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        profileNode.updateContent()
        if #available(iOS 13.0, *) {
            Task {
                await context.refreshAccountProfile()
                await context.fetchCurrentUserStatus()
                if let token = await context.getTokenPreferringCachedSkipSessionReadyWait() {
                    await context.engine.friendsData.refreshFromNetwork(token: token)
                }
            }
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        profileNode.updateLayout(layout: layout, transition: transition)
    }
}
