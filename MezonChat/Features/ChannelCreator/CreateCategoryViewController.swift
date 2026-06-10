import UIKit
import AsyncDisplayKit

final class CreateCategoryViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let existingCategories: [Mezon_Api_CategoryDesc]
    private let onCreated: (Mezon_Api_CategoryDesc) -> Void

    private var createNode: CreateCategoryContainerNode { displayNode as! CreateCategoryContainerNode }

    init(
        context: AccountContext,
        clanId: Int64,
        existingCategories: [Mezon_Api_CategoryDesc],
        onCreated: @escaping (Mezon_Api_CategoryDesc) -> Void
    ) {
        self.context = context
        self.clanId = clanId
        self.existingCategories = existingCategories
        self.onCreated = onCreated
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        displayNode = CreateCategoryContainerNode(
            onClose: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onCreate: { [weak self] name in
                self?.createCategory(name: name)
            }
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        createNode.applyTheme()
    }

    private func createCategory(name: String) {
        if existingCategories.contains(where: { $0.categoryName.lowercased() == name.lowercased() }) {
            Toast.error(L(L10n.CategoryCreator.duplicateName))
            return
        }

        createNode.setLoading(true)
        Task {
            guard let token = await context.getToken() else {
                await MainActor.run {
                    createNode.setLoading(false)
                    Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                }
                return
            }

            do {
                let newCategory = try await MezonHTTPClient.shared.createCategoryDesc(
                    clanId: clanId,
                    categoryName: name,
                    token: token
                )
                await MainActor.run {
                    createNode.setLoading(false)
                    onCreated(newCategory)
                    navigationController?.popViewController(animated: true)
                }
            } catch {
                await MainActor.run {
                    createNode.setLoading(false)
                    Toast.error(error.localizedDescription)
                }
            }
        }
    }
}
