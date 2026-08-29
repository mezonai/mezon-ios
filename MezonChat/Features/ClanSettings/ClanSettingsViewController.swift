import UIKit
import AsyncDisplayKit
import SwiftProtobuf

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
            canShowIntegrations: canShowIntegrationsSection(),
            canShowOverview: canShowOverviewSection(),
            canShowAuditLog: canShowAuditLogSection()
        )
        node.onClose = { [weak self] in
            if let nav = self?.navigationController {
                nav.popViewController(animated: true)
            } else {
                self?.dismiss(animated: true)
            }
        }
        node.onSelectOverview = { [weak self] in
            guard let self else { return }
            let vc = ClanOverviewViewController(context: self.context, clanId: self.clanId)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        node.onSelectAuditLog = { [weak self] in
            guard let self else { return }
            let vc = AuditLogViewController(context: self.context, clanId: self.clanId)
            self.navigationController?.pushViewController(vc, animated: true)
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
        node.onSelectInvites = { [weak self] in
            guard let self else { return }
            let vc = ClanInviteSheetViewController(context: self.context, clanId: self.clanId)
            vc.modalPresentationStyle = .pageSheet
            if #available(iOS 15.0, *) {
                if let sheet = vc.sheetPresentationController {
                    sheet.prefersGrabberVisible = true
                    sheet.detents = [.medium(), .large()]
                    sheet.selectedDetentIdentifier = .medium
                }
            }
            self.present(vc, animated: true)
        }
        node.onChangeAvatar = { [weak self] in
            if #available(iOS 13.0, *) {
                self?.pickAvatarTapped()
            }
        }
        node.onRemoveAvatar = { [weak self] in
            if #available(iOS 13.0, *) {
                self?.removeAvatarTapped()
            }
        }
        node.onSelectMembers = { [weak self] in
            guard let self else { return }
            let vc = ClanMembersViewController(context: self.context, clanId: self.clanId)
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
                self.settingsNode.updateCanShowRoles(self.canShowRolesSection(), canShowIntegrations: self.canShowIntegrationsSection(), canShowOverview: self.canShowOverviewSection(), canShowAuditLog: self.canShowAuditLogSection())
            }))
        disposables.add((context.engine.clanData.clanRolesUpdated.signal()
            |> deliverOnMainQueue).start(next: { [weak self] updatedClanId in
                guard let self, updatedClanId == self.clanId else { return }
                self.settingsNode.updateCanShowRoles(self.canShowRolesSection(), canShowIntegrations: self.canShowIntegrationsSection(), canShowOverview: self.canShowOverviewSection(), canShowAuditLog: self.canShowAuditLogSection())
            }))
        disposables.add((context.account.postbox.clanListView()
            |> deliverOnMainQueue).start(next: { [weak self] view in
                guard let self else { return }
                if let clan = view.clans.first(where: { $0.id == self.clanId }) {
                    if let desc = try? Mezon_Api_ClanDesc(serializedBytes: clan.data) {
                        self.settingsNode.updateClanDetails(name: desc.clanName, avatarURL: desc.logo)
                    }
                }
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

    private func canShowOverviewSection() -> Bool {
        context.rolePermissions.isClanOwner(clanId: clanId) ||
        context.rolePermissions.hasClanPermission(.administrator, clanId: clanId) ||
        context.rolePermissions.canManageClan(clanId: clanId)
    }

    private func canShowAuditLogSection() -> Bool {
        context.rolePermissions.isClanOwner(clanId: clanId) ||
        context.rolePermissions.hasClanPermission(.administrator, clanId: clanId) ||
        context.rolePermissions.canManageClan(clanId: clanId)
    }

    @objc private func pickAvatarTapped() {
        if #available(iOS 13.0, *) {
            guard canShowOverviewSection() else {
                return
            }
            guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else { return }
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.allowsEditing = true
            picker.delegate = self
            present(picker, animated: true)
        }
    }

    @available(iOS 13.0, *)
    @objc private func removeAvatarTapped() {
        guard canShowOverviewSection() else { return }
        let alert = UIAlertController(title: L(L10n.ClanSetting.Overview.removeAvatarTitle), message: L(L10n.ClanSetting.Overview.removeAvatarMessage), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        alert.addAction(UIAlertAction(title: L(L10n.Common.delete), style: .destructive, handler: { [weak self] _ in
            self?.performRemoveAvatar()
        }))
        present(alert, animated: true)
    }

    @available(iOS 13.0, *)
    private func performRemoveAvatar() {
        Task { [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { return }
            do {
                guard let clan = self.context.account.postbox.read({ tx in tx.getClan(id: self.clanId) }) else { return }
                
                var req = Mezon_Api_UpdateClanDescRequest()
                req.clanID = self.clanId
                req.clanName = clan.name
                req.preventAnonymous = clan.preventsAnonymousMessages
                req.logo = SwiftProtobuf.Google_Protobuf_StringValue("")
                
                if let d = try? Mezon_Api_ClanDesc(serializedBytes: clan.data) {
                    req.banner = SwiftProtobuf.Google_Protobuf_StringValue(d.banner)
                    req.status = d.status
                    req.isOnboarding = SwiftProtobuf.Google_Protobuf_BoolValue(d.isOnboarding)
                    req.welcomeChannelID = d.welcomeChannelID
                    req.onboardingBanner = SwiftProtobuf.Google_Protobuf_StringValue(d.onboardingBanner)
                    req.isCommunity = SwiftProtobuf.Google_Protobuf_BoolValue(d.isCommunity)
                    req.communityBanner = SwiftProtobuf.Google_Protobuf_StringValue(d.communityBanner)
                }
                
                try await self.context.account.network.updateClanDesc(request: req, token: token)
                
                if var d = try? Mezon_Api_ClanDesc(serializedBytes: clan.data) {
                    d.logo = ""
                    let updatedClan = ClanRecord(
                        id: clan.id,
                        name: clan.name,
                        icon: "",
                        ownerId: clan.ownerId,
                        data: try d.serializedData()
                    )
                    self.context.account.postbox.writeSync { tx in
                        tx.updateClans([updatedClan])
                    }
                }
                
                await MainActor.run {
                    self.settingsNode.updateClanDetails(name: clan.name, avatarURL: "")
                    Toast.success(L(L10n.ClanSetting.Overview.saveSuccess))
                }
            } catch {
                await MainActor.run { Toast.error(error.localizedDescription) }
            }
        }
    }
}

extension ClanSettingsViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if #available(iOS 13.0, *) {
            picker.dismiss(animated: true)
            guard let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage else { return }
            if let url = info[.imageURL] as? URL,
               let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileSize = attr[.size] as? NSNumber {
                let sizeInMB = Double(fileSize.intValue) / (1024 * 1024)
                if sizeInMB > 1.0 {
                    Toast.error(L(L10n.ClanSetting.Overview.uploadFileTooLarge1MB))
                    return
                }
            } else {
                if let checkData = image.jpegData(compressionQuality: 1.0) {
                    let sizeInMB = Double(checkData.count) / (1024 * 1024)
                    if sizeInMB > 1.0 {
                        Toast.error(L(L10n.ClanSetting.Overview.uploadFileTooLarge1MB))
                        return
                    }
                }
            }
        
            guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        
            Task { [weak self] in
                guard let self else { return }
                guard let token = await self.context.getToken() else { return }
                do {
                    let uploadInfo = try await self.context.account.network.uploadAttachmentFile(
                        filename: "avatar.jpg",
                        filetype: "image/jpeg",
                        size: data.count,
                        width: Int(image.size.width),
                        height: Int(image.size.height),
                        token: token
                    )
                    try await self.context.account.network.uploadToMinIO(
                        url: uploadInfo.url,
                        data: data,
                        contentType: "image/jpeg"
                    )
                    let avatarUrlToSave = "\(MezonConfig.baseImgURL)/\(uploadInfo.filename)"
                
                    guard let clan = self.context.account.postbox.read({ tx in tx.getClan(id: self.clanId) }) else { return }
                
                    var req = Mezon_Api_UpdateClanDescRequest()
                    req.clanID = self.clanId
                    req.clanName = clan.name
                    req.preventAnonymous = clan.preventsAnonymousMessages
                    req.logo = SwiftProtobuf.Google_Protobuf_StringValue(avatarUrlToSave)
                
                    if let d = try? Mezon_Api_ClanDesc(serializedBytes: clan.data) {
                        req.banner = SwiftProtobuf.Google_Protobuf_StringValue(d.banner)
                        req.status = d.status
                        req.isOnboarding = SwiftProtobuf.Google_Protobuf_BoolValue(d.isOnboarding)
                        req.welcomeChannelID = d.welcomeChannelID
                        req.onboardingBanner = SwiftProtobuf.Google_Protobuf_StringValue(d.onboardingBanner)
                        req.isCommunity = SwiftProtobuf.Google_Protobuf_BoolValue(d.isCommunity)
                        req.communityBanner = SwiftProtobuf.Google_Protobuf_StringValue(d.communityBanner)
                    }
                
                    try await self.context.account.network.updateClanDesc(request: req, token: token)
                
                    if var d = try? Mezon_Api_ClanDesc(serializedBytes: clan.data) {
                        d.logo = avatarUrlToSave
                        let updatedClan = ClanRecord(
                            id: clan.id,
                            name: clan.name,
                            icon: avatarUrlToSave,
                            ownerId: clan.ownerId,
                            data: try d.serializedData()
                        )
                        self.context.account.postbox.writeSync { tx in
                            tx.updateClans([updatedClan])
                        }
                    }
                
                    await MainActor.run {
                        self.settingsNode.updateClanDetails(name: clan.name, avatarURL: avatarUrlToSave)
                        Toast.success(L(L10n.ClanSetting.Overview.saveSuccess))
                    }
                } catch {
                    await MainActor.run { Toast.error(error.localizedDescription) }
                }
            }
        }
    }
}
