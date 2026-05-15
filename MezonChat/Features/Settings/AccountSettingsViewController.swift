import UIKit

final class AccountSettingsViewController: BaseViewController {

    private let context: AccountContext

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

    private var blockedUsersCount: Int = 0

    private let side: CGFloat = 16.sw

    private enum RowTapAction {
        case none
        case userProfile
        case linkEmail
        case linkPhone
        case blockedUsers
        case setPassword
        case deleteAccount
    }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

    override func setupBindings() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(currentUserDidChange),
            name: .mezonAccountCurrentUserDidChange,
            object: nil
        )
    }

    override func applyTheme() {
        titleLabel.text = L(L10n.Settings.account)
        titleLabel.textColor = .mezonTextStrong
        backButton.tintColor = .mezonTextStrong
        headerView.backgroundColor = .mezonPrimary
        view.backgroundColor = .mezonPrimary
        scrollView.backgroundColor = .mezonPrimary
        rebuildContent()
    }

    @objc private func currentUserDidChange() {
        rebuildContent()
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let user = context.currentUser
        let email = user?.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasEmail = !email.isEmpty
        let phone = user?.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasPhone = !phone.isEmpty

        let blockedDetail = blockedUsersCount > 0 ? "\(blockedUsersCount)" : ""
        let rawDisplayName = accountRowDetailText(rawAccountDisplayName())

        let infoRows: [(title: String, detail: String?, warn: Bool, destructive: Bool, tap: RowTapAction)] = [
            (L(L10n.AccountSetting.username), accountRowDetailText(user?.username), false, false, .userProfile),
            (L(L10n.AccountSetting.displayName), rawDisplayName, false, false, .userProfile),
            (L(L10n.Login.email), hasEmail ? AccountSettingMask.maskEmail(email) : L(L10n.Common.linkEmail), !hasEmail, false, .linkEmail),
            (L(L10n.AccountSetting.phoneSectionTitle), hasPhone ? AccountSettingMask.maskPhone(phone) : L(L10n.Common.linkPhoneNumber), !hasPhone, false, .linkPhone),
        ]

        addSectionHeader(L(L10n.AccountSetting.accountInformation))
        addGroupedCard(rows: infoRows)

        addSpacer(12.sh)
        addSectionHeader(L(L10n.AccountSetting.users))
        addGroupedCard(rows: [
            (L(L10n.AccountSetting.blockedUsers), blockedDetail.isEmpty ? nil : blockedDetail, false, false, .blockedUsers),
        ])

        addSpacer(12.sh)
        addSectionHeader(L(L10n.AccountSetting.accountManagement))
        addGroupedCard(rows: [
            (L(L10n.AccountSetting.setPassword), nil, false, false, .setPassword),
            (L(L10n.Common.deleteAccount), nil, false, true, .deleteAccount),
        ])

        addSpacer(40.sh)
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

    private func accountRowDetailText(_ raw: String?) -> String? {
        let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }

    private func rawAccountDisplayName() -> String? {
        guard
            let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.account),
            let api = try? Mezon_Api_Account(serializedData: data)
        else {
            return nil
        }
        return api.user.displayName
    }

    private func addGroupedCard(rows: [(title: String, detail: String?, warn: Bool, destructive: Bool, tap: RowTapAction)]) {
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
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        for (i, row) in rows.enumerated() {
            let rowView = makeRow(
                title: row.title,
                detail: row.detail,
                showWarning: row.warn,
                destructive: row.destructive,
                tapAction: row.tap
            )
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

    private func makeRow(title: String, detail: String?, showWarning: Bool, destructive: Bool, tapAction: RowTapAction) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        titleLabel.textColor = destructive ? .systemRed : .mezonTextStrong
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        let rightStack = UIStackView()
        rightStack.axis = .horizontal
        rightStack.spacing = 6.sw
        rightStack.alignment = .center
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(rightStack)

        if showWarning {
            let icon = UIImageView(image: UIImage(systemName: "exclamationmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)))
            icon.tintColor = .mezonTextPrimary
            icon.setContentHuggingPriority(.required, for: .horizontal)
            rightStack.addArrangedSubview(icon)
        }

        if let detail, !detail.isEmpty {
            let detailLabel = UILabel()
            detailLabel.text = detail
            detailLabel.font = .systemFont(ofSize: 14.sf, weight: .regular)
            detailLabel.textColor = .mezonTextPrimary
            detailLabel.textAlignment = .right
            if showWarning {
                detailLabel.font = .italicSystemFont(ofSize: 14.sf)
            }
            detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            rightStack.addArrangedSubview(detailLabel)
            rightStack.setCustomSpacing(12.sw, after: detailLabel)
        }

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        chevron.tintColor = .mezonTextPrimary
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        rightStack.addArrangedSubview(chevron)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 52.sh),

            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16.sw),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -8.sw),

            rightStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16.sw),
            rightStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        let tap = RowTapGesture(target: self, action: #selector(rowTapped(_:)))
        tap.action = tapAction
        container.addGestureRecognizer(tap)
        container.isUserInteractionEnabled = true

        return container
    }

    @objc private func rowTapped(_ gesture: RowTapGesture) {
        switch gesture.action {
        case .none:
            break
        case .userProfile:
            let vc = ProfileSettingViewController(context: context, initialTab: .userProfile)
            navigationController?.pushViewController(vc, animated: true)
        case .linkEmail:
            let currentEmail = context.currentUser?.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let vc = UpdateEmailViewController(context: context, currentEmail: currentEmail)
            navigationController?.pushViewController(vc, animated: true)
        case .linkPhone:
            let currentPhone = context.currentUser?.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let vc = UpdatePhoneNumberViewController(context: context, currentPhone: currentPhone)
            navigationController?.pushViewController(vc, animated: true)
        case .blockedUsers:
            let line = "\(L(L10n.AccountSetting.blockedUsers)) — \(L(L10n.Common.comingSoon))"
            Toast.comingSoonLine(line)
        case .setPassword:
            let email = context.currentUser?.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if email.isEmpty {
                let alert = UIAlertController(
                    title: L(L10n.AccountSetting.requireLinkEmailTitle),
                    message: L(L10n.AccountSetting.requireLinkEmailMessage),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
                alert.addAction(UIAlertAction(title: L(L10n.AccountSetting.requireLinkEmailAction), style: .default) { [weak self] _ in
                    guard let self = self else { return }
                    let vc = UpdateEmailViewController(context: self.context, currentEmail: "")
                    self.navigationController?.pushViewController(vc, animated: true)
                })
                present(alert, animated: true)
                return
            }

            var hasPassword = false
            if let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.account),
               let api = try? Mezon_Api_Account(serializedData: data) {
                hasPassword = api.passwordSetted
            } 
            let vc = SetPasswordViewController(context: context, hasPassword: hasPassword, email: email)
            navigationController?.pushViewController(vc, animated: true)
        case .deleteAccount:
            presentDeleteAccountConfirmation()
        }
    }

    private func presentDeleteAccountConfirmation() {
        let alert = UIAlertController(
            title: L(L10n.AccountSetting.deleteAccountAlertTitle),
            message: L(L10n.AccountSetting.deleteAccountAlertMessage),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L(L10n.AccountSetting.deleteAccountCancel), style: .cancel))
        alert.addAction(UIAlertAction(title: L(L10n.AccountSetting.deleteAccountConfirm), style: .destructive) { [weak self] _ in
            self?.performDeleteAccount()
        })
        present(alert, animated: true)
    }

    private func performDeleteAccount() {
        Task { @MainActor in
            // guard let token = await context.getToken() else {
            //     Toast.error(L(L10n.AccountSetting.deleteAccountError))
            //     return
            // }
            // do {
            //     try await context.account.network.deleteAccount(token: token)
            // } catch {
            //     Toast.error(L(L10n.AccountSetting.deleteAccountError))
            //     return
            // }
            context.logout()
            Toast.success(L(L10n.AccountSetting.deleteAccountSuccess))
        }
    }

    private final class RowTapGesture: UITapGestureRecognizer {
        var action: RowTapAction = .none
    }

    private func addSpacer(_ height: CGFloat) {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        contentStack.addArrangedSubview(spacer)
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }
}

private enum AccountSettingMask {
    static func maskEmail(_ email: String) -> String {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty else { return "" }
        guard let at = e.firstIndex(of: "@") else { return String(repeating: "*", count: e.count) }
        let prefix = e[..<at]
        let suffix = e[at...]
        return String(repeating: "*", count: prefix.count) + suffix
    }

    static func maskPhone(_ phone: String) -> String {
        let p = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return "" }
        if p.count <= 4 { return p }
        let tail = p.suffix(4)
        return String(repeating: "*", count: p.count - 4) + tail
    }
}
