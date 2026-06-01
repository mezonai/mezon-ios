import UIKit
import AsyncDisplayKit

final class ClanSettingsViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let clanName: String
    private let avatarURL: String

    private var settingsNode: ClanSettingsContainerNode {
        displayNode as! ClanSettingsContainerNode
    }

    init(context: AccountContext, clanId: Int64, clanName: String, avatarURL: String) {
        self.context = context
        self.clanId = clanId
        self.clanName = clanName
        self.avatarURL = avatarURL
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        let node = ClanSettingsContainerNode(
            context: context,
            clanId: clanId,
            clanName: clanName,
            avatarURL: avatarURL,
            canShowRoles: canShowRolesSection(),
            canShowIntegrations: canShowIntegrationsSection()
        )
        node.onClose = { [weak self] in
            if let nav = self?.navigationController {
                nav.popViewController(animated: true)
            } else {
                self?.dismiss(animated: true)
            }
        }
        node.onSelectRoles = { [weak self] in
            guard let self else { return }
            guard self.canShowRolesSection() else { return }
            let vc = ClanRolesViewController(context: self.context, clanId: self.clanId)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        node.onSelectIntegrations = { [weak self] in
            guard let self else { return }
            let vc = IntegrationsViewController(context: self.context, clanId: self.clanId)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        node.onSelectStickers = { [weak self] in
            guard let self else { return }
            let vc = ClanStickersViewController(context: self.context, clanId: self.clanId)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        node.onSelectEmojis = { [weak self] in
            guard let self else { return }
            let vc = ClanEmojisViewController(context: self.context, clanId: self.clanId)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        displayNode = node
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func setupBindings() {
        disposables.add((context.engine.clanData.clanPermissionsUpdated.signal()
            |> deliverOnMainQueue).start(next: { [weak self] updatedClanId in
                guard let self, updatedClanId == self.clanId else { return }
                self.settingsNode.updateCanShowRoles(self.canShowRolesSection(), canShowIntegrations: self.canShowIntegrationsSection())
            }))
        disposables.add((context.engine.clanData.clanRolesUpdated.signal()
            |> deliverOnMainQueue).start(next: { [weak self] updatedClanId in
                guard let self, updatedClanId == self.clanId else { return }
                self.settingsNode.updateCanShowRoles(self.canShowRolesSection(), canShowIntegrations: self.canShowIntegrationsSection())
            }))
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        settingsNode.updateLayout(layout: layout, transition: transition)
    }

    private func canShowRolesSection() -> Bool {
        context.rolePermissions.canManageRoles(clanId: clanId)
    }

    private func canShowIntegrationsSection() -> Bool {
        context.rolePermissions.isClanOwner(clanId: clanId) ||
        context.rolePermissions.hasClanPermission(.administrator, clanId: clanId) ||
        context.rolePermissions.canManageClan(clanId: clanId)
    }
}
