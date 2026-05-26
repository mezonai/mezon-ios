import UIKit
import AsyncDisplayKit

final class ChangeCategoryViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private let currentCategoryId: Int64
    private let currentCategoryName: String
    private let channelLabel: String
    private let channelTopic: String
    private var categories: [Mezon_Api_CategoryDesc] = []

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let headerLabel = UILabel()
    private var activityIndicator: UIActivityIndicatorView!
    private var emptyStateLabel: UILabel?

    init(
        context: AccountContext,
        clanId: Int64,
        channelId: Int64,
        currentCategoryId: Int64,
        currentCategoryName: String,
        channelLabel: String,
        channelTopic: String
    ) {
        self.context = context
        self.clanId = clanId
        self.channelId = channelId
        self.currentCategoryId = currentCategoryId
        self.currentCategoryName = currentCategoryName
        self.channelLabel = channelLabel
        self.channelTopic = channelTopic
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func setupUI() {
        displayNode.backgroundColor = UIColor.theme.primary

        let t = UIColor.theme

        let header = UIView()
        view.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44.sh),
        ])

        let backBtn = UIButton(type: .system)
        backBtn.setImage(
            UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        backBtn.tintColor = t.textStrong
        backBtn.addTarget(self, action: #selector(handleBack), for: .touchUpInside)
        header.addSubview(backBtn)
        backBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            backBtn.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16.sw),
            backBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backBtn.widthAnchor.constraint(equalToConstant: 24.swh),
            backBtn.heightAnchor.constraint(equalToConstant: 24.swh),
        ])

        let titleLabel = UILabel()
        titleLabel.text = L(L10n.ChannelSetting.changeCategory)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        titleLabel.textColor = t.textStrong
        header.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        stackView.axis = .vertical
        stackView.spacing = 0
        scrollView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16.sh),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16.sw),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16.sw),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16.sh),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32.sw),
        ])

        headerLabel.font = .systemFont(ofSize: 12.sf, weight: .semibold)
        headerLabel.textColor = t.textDisabled
        headerLabel.text = L(L10n.ChannelSetting.changeCategoryMoveFrom)
            .replacingOccurrences(of: "%@", with: currentCategoryName)
            .uppercased()
        headerLabel.numberOfLines = 0
        stackView.addArrangedSubview(headerLabel)
        stackView.setCustomSpacing(10.sh, after: headerLabel)

        activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.color = t.textDisabled
        activityIndicator.hidesWhenStopped = true
        stackView.addArrangedSubview(activityIndicator)
        activityIndicator.startAnimating()

        fetchCategories()
    }

    private func fetchCategories() {
        let postbox = context.account.postbox
        let key = PreferencesKeys.channelListMeta(clanId: clanId)
        if let data = postbox.getPreferenceData(key: key) {
            if let meta = ChannelListMetaCodec.decode(data)?.categoryDescs, !meta.isEmpty {
                categories = meta.filter { $0.categoryID != currentCategoryId }
                activityIndicator.stopAnimating()
                buildCategoryRows()
                return
            }
        }

        let channelListKey = PreferencesKeys.channelList(clanId: clanId)
        if let data = postbox.getPreferenceData(key: channelListKey) {
            let channels = ChannelPreferenceListCodec.decode(data)
            var seen = Set<Int64>()
            var result: [Mezon_Api_CategoryDesc] = []
            for ch in channels where ch.categoryID != 0 && !seen.contains(ch.categoryID) {
                seen.insert(ch.categoryID)
                var cat = Mezon_Api_CategoryDesc()
                cat.categoryID = ch.categoryID
                cat.categoryName = ch.categoryName
                cat.clanID = ch.clanID
                result.append(cat)
            }
            if !result.isEmpty {
                categories = result.filter { $0.categoryID != currentCategoryId }
                activityIndicator.stopAnimating()
                buildCategoryRows()
                return
            }
        }

        fetchCategoriesFromAPI()
    }

    private func fetchCategoriesFromAPI() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                self.activityIndicator.stopAnimating()
                self.showEmptyState()
                return
            }
            do {
                let allCategories = try await MezonHTTPClient.shared.listCategoryDescs(
                    clanId: self.clanId, token: token
                )
                self.categories = allCategories.filter { $0.categoryID != self.currentCategoryId }
                self.activityIndicator.stopAnimating()
                self.buildCategoryRows()
            } catch {
                self.activityIndicator.stopAnimating()
                self.showEmptyState()
            }
        }
    }

    private func showEmptyState() {
        if emptyStateLabel != nil { return }
        
        let label = UILabel()
        label.text = L(L10n.ChannelSetting.changeCategoryEmpty)
        label.font = .systemFont(ofSize: 14.sf)
        label.textColor = UIColor.theme.textDisabled
        label.textAlignment = .center
        label.numberOfLines = 0
        
        view.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32.sw),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32.sw)
        ])
        
        emptyStateLabel = label
    }



    private func buildCategoryRows() {
        let viewsToRemove = stackView.arrangedSubviews.filter { $0 !== headerLabel && $0 !== activityIndicator }
        viewsToRemove.forEach { $0.removeFromSuperview() }

        guard !categories.isEmpty else {
            showEmptyState()
            return
        }

        let container = UIView()
        container.backgroundColor = UIColor.theme.secondary
        container.layer.cornerRadius = 12
        container.clipsToBounds = true

        let innerStack = UIStackView()
        innerStack.axis = .vertical
        innerStack.spacing = 0
        container.addSubview(innerStack)
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: container.topAnchor),
            innerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            innerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            innerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        for (idx, category) in categories.enumerated() {
            let row = createCategoryRow(category: category)
            innerStack.addArrangedSubview(row)
            if idx < categories.count - 1 {
                let sep = UIView()
                sep.backgroundColor = UIColor.theme.border
                innerStack.addArrangedSubview(sep)
                sep.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
            }
        }

        stackView.addArrangedSubview(container)
    }

    private func createCategoryRow(category: Mezon_Api_CategoryDesc) -> UIView {
        let button = CategoryRowButton(type: .system)
        button.backgroundColor = .clear
        button.category = category
        button.addTarget(self, action: #selector(handleCategoryTap(_:)), for: .touchUpInside)

        let label = UILabel()
        label.text = category.categoryName
        label.font = .systemFont(ofSize: 15.sf, weight: .medium)
        label.textColor = UIColor.theme.textStrong
        label.isUserInteractionEnabled = false
        button.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 16.sw),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -16.sw),
        ])

        button.heightAnchor.constraint(equalToConstant: 52.sh).isActive = true
        return button
    }

    @objc private func handleBack() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func handleCategoryTap(_ sender: CategoryRowButton) {
        guard let category = sender.category else { return }
        showMoveConfirmation(category: category)
    }

    private func showMoveConfirmation(category: Mezon_Api_CategoryDesc) {
        let confirmTitle = L(L10n.ChannelSetting.changeCategory)
        let confirmMessage = L(L10n.ChannelSetting.changeCategoryConfirmContent)
            .replacingOccurrences(of: "%channel%", with: channelLabel)
            .replacingOccurrences(of: "%category%", with: category.categoryName)

        let alert = UIAlertController(
            title: confirmTitle,
            message: confirmMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        alert.addAction(UIAlertAction(
            title: L(L10n.Common.confirm),
            style: .default
        ) { [weak self] _ in
            self?.moveChannelToCategory(category)
        })
        present(alert, animated: true)
    }

    private func moveChannelToCategory(_ category: Mezon_Api_CategoryDesc) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { return }
            let clanId = self.clanId
            let channelId = self.channelId

            self.activityIndicator.startAnimating()
            self.view.isUserInteractionEnabled = false
            do {
                try await self.context.engine.channels.updateChannelDescription(
                    clanId: clanId,
                    channelId: channelId,
                    name: self.channelLabel,
                    topic: self.channelTopic,
                    categoryId: category.categoryID,
                    token: token
                )

                self.navigationController?.popViewController(animated: true)
            } catch {
                Toast.error(error.localizedDescription)
                self.activityIndicator.stopAnimating()
                self.view.isUserInteractionEnabled = true
            }
        }
    }

}

private final class CategoryRowButton: UIButton {
    var category: Mezon_Api_CategoryDesc?
}
