import UIKit

final class SettingsViewController: BaseViewController {

    private let context: AccountContext

    private var searchQuery: String = ""
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.3

    private let headerView = UIView()
    private let backButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        btn.setImage(img, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var contentStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 0
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setupUI() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        headerView.addSubview(backButton)
        headerView.addSubview(titleLabel)

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        let headerHeight: CGFloat = 96

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: headerHeight),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16.sw),
            backButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -8.sh),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -16.sw),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    override func applyTheme() {
        titleLabel.text = L(L10n.Settings.title)
        titleLabel.textColor = .mezonTextStrong
        backButton.tintColor = .mezonTextStrong
        headerView.backgroundColor = .mezonPrimary
        view.backgroundColor = .mezonPrimary
        scrollView.backgroundColor = .mezonPrimary

        searchBgView.backgroundColor = .mezonSecondaryBackground
        searchIconView.tintColor = .mezonTextPrimary
        searchTextField.textColor = .mezonTextStrong
        searchTextField.tintColor = .mezonTextStrong
        searchTextField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.Common.search),
            attributes: [.foregroundColor: UIColor.mezonTextMuted]
        )
        rebuildContent()
    }

    private func rebuildContent() {
        searchQuery = searchTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasSearchBar = !contentStack.arrangedSubviews.isEmpty
        if hasSearchBar {
            contentStack.arrangedSubviews.dropFirst().forEach { $0.removeFromSuperview() }
            addFilteredContent(filter: searchQuery)
        } else {
            addSearchBar()
            addFilteredContent(filter: searchQuery)
        }
    }

    private let side: CGFloat = 16.sw
    private let rowIconTitleSpacing: CGFloat = 22.sw

    private func allSettingsSections() -> [(header: String, rows: [SettingsRow])] {
        [
            (L(L10n.Settings.accountSettings), [
                SettingsRow(icon: "Setting/AccountIcon", title: L(L10n.Settings.account), action: .navigate),
                SettingsRow(icon: "Setting/FriendRequestIcon", title: L(L10n.Settings.friendRequests), action: .navigate),
                SettingsRow(icon: "Setting/QRIcon", title: L(L10n.Settings.qrScan), action: .navigate),
                SettingsRow(icon: "Setting/DeviceIcon", title: L(L10n.Settings.devices), action: .navigate),
            ]),
            (L(L10n.Settings.appSettings), [
                SettingsRow(icon: "Setting/AppIcon", title: L(L10n.Settings.appVersion), action: .detail(appVersion)),
                SettingsRow(icon: "Setting/ThemeIcon", title: L(L10n.Settings.appearance), action: .navigate),
                SettingsRow(icon: "Setting/LanguageIcon", title: L(L10n.Settings.language), action: .detailNavigate(currentLanguageCode)),
            ]),
        ]
    }

    private func addFilteredContent(filter query: String = "") {
        let sections = allSettingsSections()
        let filteredSections: [(header: String, rows: [SettingsRow])]
        if query.isEmpty {
            filteredSections = sections
        } else {
            let q = query.lowercased()
            filteredSections = sections.compactMap { section in
                let headerMatches = section.header.lowercased().contains(q)
                let matchedRows = section.rows.filter { $0.title.lowercased().contains(q) }
                if headerMatches { return (section.header, section.rows) }
                if matchedRows.isEmpty { return nil }
                return (section.header, matchedRows)
            }
        }
        for (i, (header, rows)) in filteredSections.enumerated() {
            if i > 0 { addSpacer(12.sh) }
            addSectionHeader(header)
            addGroupedCard(rows: rows)
        }
        let shouldShowLogout = query.isEmpty || L(L10n.Settings.logout).lowercased().contains(query.lowercased())
        if shouldShowLogout {
            addSpacer(20.sh)
            addLogoutCard()
        }
        addSpacer(40.sh)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var currentLanguageCode: String {
        LanguageManager.shared.current.rawValue
    }

    private let searchBgView: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 10.swh
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let searchIconView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private lazy var searchTextField: UITextField = {
        let tf = UITextField()
        tf.placeholder = L(L10n.Common.search)
        tf.font = .systemFont(ofSize: 14.sf)
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.returnKeyType = .search
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.addTarget(self, action: #selector(searchTextDidChange), for: .editingChanged)
        return tf
    }()

    @objc private func searchTextDidChange() {
        debounceWorkItem?.cancel()
        let text = searchTextField.text ?? ""
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.searchQuery = text
            self.rebuildContent()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func addSearchBar() {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        searchBgView.backgroundColor = .mezonSecondaryBackground
        container.addSubview(searchBgView)

        searchIconView.tintColor = .mezonTextPrimary
        searchBgView.addSubview(searchIconView)

        searchTextField.textColor = .mezonTextStrong
        searchTextField.tintColor = .mezonTextStrong
        searchTextField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.Common.search),
            attributes: [.foregroundColor: UIColor.mezonTextMuted]
        )
        searchBgView.addSubview(searchTextField)

        NSLayoutConstraint.activate([
            searchBgView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12.sh),
            searchBgView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: side),
            searchBgView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -side),
            searchBgView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4.sh),
            searchBgView.heightAnchor.constraint(equalToConstant: 40.sh),

            searchIconView.leadingAnchor.constraint(equalTo: searchBgView.leadingAnchor, constant: 14.sw),
            searchIconView.centerYAnchor.constraint(equalTo: searchBgView.centerYAnchor),
            searchIconView.widthAnchor.constraint(equalToConstant: 20.swh),
            searchIconView.heightAnchor.constraint(equalToConstant: 20.swh),

            searchTextField.leadingAnchor.constraint(equalTo: searchIconView.trailingAnchor, constant: 10.sw),
            searchTextField.trailingAnchor.constraint(equalTo: searchBgView.trailingAnchor, constant: -14.sw),
            searchTextField.centerYAnchor.constraint(equalTo: searchBgView.centerYAnchor),
        ])

        contentStack.addArrangedSubview(container)
    }

    private func addSectionHeader(_ text: String) {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15.sf, weight: .bold)
        label.textColor = .mezonTextPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 16.sh),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: side),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -side),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8.sh),
        ])

        contentStack.addArrangedSubview(container)
    }

    private func addGroupedCard(rows: [SettingsRow]) {
        let card = UIView()
        card.backgroundColor = .mezonSecondaryBackground
        card.layer.cornerRadius = 10.swh
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(card)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: wrapper.topAnchor),
            card.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: side),
            card.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -side),
            card.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stack.isLayoutMarginsRelativeArrangement = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        for (i, row) in rows.enumerated() {
            let rowView = makeRowView(row: row)
            stack.addArrangedSubview(rowView)

            if i < rows.count - 1 {
                let sep = UIView()
                sep.backgroundColor = .mezonSeparator
                sep.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(sep)
                sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
            }
        }

        contentStack.addArrangedSubview(wrapper)
    }

    private func makeRowView(row: SettingsRow) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let iconView = UIImageView()
        iconView.contentMode = .scaleAspectFit
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = UIImage(named: row.icon, in: .main, compatibleWith: nil) {
            iconView.image = img.withRenderingMode(.alwaysOriginal)
        }
        container.addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.text = row.title
        titleLabel.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        titleLabel.textColor = .mezonTextPrimary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 52.sh),

            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16.sw),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20.swh),
            iconView.heightAnchor.constraint(equalToConstant: 20.swh),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: rowIconTitleSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        switch row.action {
        case .navigate:
            let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
            chevron.tintColor = .mezonTextPrimary
            chevron.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(chevron)
            NSLayoutConstraint.activate([
                chevron.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16.sw),
                chevron.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8.sw).isActive = true

        case .detail(let text):
            let detailLabel = UILabel()
            detailLabel.text = text
            detailLabel.font = .systemFont(ofSize: 14.sf)
            detailLabel.textColor = .mezonTextPrimary
            detailLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(detailLabel)
            NSLayoutConstraint.activate([
                detailLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16.sw),
                detailLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: detailLabel.leadingAnchor, constant: -8.sw).isActive = true

        case .detailNavigate(let text):
            let detailLabel = UILabel()
            detailLabel.text = text
            detailLabel.font = .systemFont(ofSize: 14.sf)
            detailLabel.textColor = .mezonTextPrimary
            detailLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(detailLabel)

            let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
            chevron.tintColor = .mezonTextPrimary
            chevron.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(chevron)

            NSLayoutConstraint.activate([
                chevron.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16.sw),
                chevron.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                detailLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -6.sw),
                detailLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: detailLabel.leadingAnchor, constant: -8.sw).isActive = true
        }

        let tap = SettingsRowTapGesture(target: self, action: #selector(rowTapped(_:)))
        tap.row = row
        container.addGestureRecognizer(tap)

        return container
    }

    private func addLogoutCard() {
        let card = UIView()
        card.backgroundColor = .mezonSecondaryBackground
        card.layer.cornerRadius = 10.swh
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(card)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: wrapper.topAnchor),
            card.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: side),
            card.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -side),
            card.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])

        let iconView = UIImageView()
        iconView.contentMode = .scaleAspectFit
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = UIImage(named: "Setting/LogoutIcon", in: .main, compatibleWith: nil) {
            iconView.image = img.withRenderingMode(.alwaysOriginal)
        }
        card.addSubview(iconView)

        let label = UILabel()
        label.text = L(L10n.Settings.logout)
        label.font = .systemFont(ofSize: 15.sf, weight: .medium)
        label.textColor = .systemRed
        label.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 52.sh),

            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16.sw),
            iconView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20.swh),
            iconView.heightAnchor.constraint(equalToConstant: 20.swh),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: rowIconTitleSpacing),
            label.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(logoutTapped))
        card.addGestureRecognizer(tap)

        contentStack.addArrangedSubview(wrapper)
    }

    private func addSpacer(_ height: CGFloat) {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        contentStack.addArrangedSubview(spacer)
    }

    @objc private func rowTapped(_ gesture: SettingsRowTapGesture) {
        guard let row = gesture.row else { return }

        switch row.title {
        case L(L10n.Settings.account):
            let vc = AccountSettingsViewController(context: context)
            navigationController?.pushViewController(vc, animated: true)
        case L(L10n.Settings.friendRequests):
            let vc = FriendRequestViewController(context: context)
            navigationController?.pushViewController(vc, animated: true)
        case L(L10n.Settings.appearance):
            let vc = AppThemeViewController()
            navigationController?.pushViewController(vc, animated: true)
        case L(L10n.Settings.language):
            let vc = LanguageSettingsViewController()
            navigationController?.pushViewController(vc, animated: true)
        case L(L10n.Settings.qrScan):
            let vc = QRScannerViewController(context: context)
            navigationController?.pushViewController(vc, animated: true)
        default:
            break
        }
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func logoutTapped() {
        let alert = UIAlertController(
            title: L(L10n.Settings.logout),
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        alert.addAction(UIAlertAction(title: L(L10n.Settings.logout), style: .destructive) { [weak self] _ in
            self?.context.logout()
        })
        present(alert, animated: true)
    }
}

private struct SettingsRow {
    let icon: String
    let title: String
    let action: SettingsRowAction
}

private enum SettingsRowAction {
    case navigate
    case detail(String)
    case detailNavigate(String)
}

private final class SettingsRowTapGesture: UITapGestureRecognizer {
    var row: SettingsRow?
}
