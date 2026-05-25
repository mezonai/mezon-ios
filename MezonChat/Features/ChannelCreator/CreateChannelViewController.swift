import UIKit
import AsyncDisplayKit

final class CreateChannelViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let categoryId: Int64

    private var createNode: CreateChannelContainerNode { displayNode as! CreateChannelContainerNode }

    init(context: AccountContext, clanId: Int64, categoryId: Int64) {
        self.context = context
        self.clanId = clanId
        self.categoryId = categoryId
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        displayNode = CreateChannelContainerNode(
            onClose: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onCreate: { [weak self] name, type, isPrivate in
                self?.createChannel(name: name, type: type, isPrivate: isPrivate)
            }
        )
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        createNode.applyTheme()
    }

    private func createChannel(name: String, type: Int32, isPrivate: Bool) {
        Task {
            do {
                guard let token = await self.context.getToken() else {
                    await MainActor.run {
                        Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                    }
                    return
                }
                
                let finalPrivate: Int32
                if type != MezonConstants.ChannelType.channel.rawValue {
                    finalPrivate = 0
                } else {
                    finalPrivate = isPrivate ? 1 : 0
                }
                
                let newChannel = try await MezonHTTPClient.shared.createClanChannelDesc(
                    clanId: self.clanId,
                    categoryId: self.categoryId,
                    channelLabel: name,
                    type: type,
                    channelPrivate: finalPrivate,
                    token: token
                )
                
                await self.context.engine.clanData.applyLocallyCreatedChannel(newChannel)
                
                
                await MainActor.run {
                    self.navigationController?.popViewController(animated: true)
                }
            } catch {
                await MainActor.run {
                    Toast.error(error.localizedDescription)
                }
            }
        }
    }
}
