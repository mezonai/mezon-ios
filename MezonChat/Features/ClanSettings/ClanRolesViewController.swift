import UIKit
import AsyncDisplayKit

final class ClanRolesViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64

    private var resolvedClanId: Int64 {
        clanId != 0 ? clanId : context.currentClanId
    }

    private lazy var tableView: UITableView = {
        let t = UITableView(frame: .zero, style: .insetGrouped)
        t.backgroundColor = .mezonSecondary
        t.dataSource = self
        t.separatorStyle = .singleLine
        return t
    }()

    init(context: AccountContext, clanId: Int64) {
        self.context = context
        self.clanId = clanId
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setupUI() {
        title = L(L10n.ClanSetting.roles)
        displayNode.view.addSubview(tableView)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = layout.safeInsets.top
        tableView.frame = CGRect(
            x: 0, y: top, width: layout.size.width, height: layout.size.height - top
        )
    }

    override func applyTheme() {
        tableView.backgroundColor = .mezonSecondary
    }
}

extension ClanRolesViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard resolvedClanId != 0 else { return 0 }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        UITableViewCell()
    }
}
