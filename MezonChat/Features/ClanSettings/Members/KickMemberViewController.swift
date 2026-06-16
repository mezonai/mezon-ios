import UIKit

final class KickMemberViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let member: ClanMemberRecord

    var onKickCompleted: (() -> Void)?

    private let headerView = UIView()
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let warningBanner = UIView()
    private let reasonTextView = UITextView()
    private let kickButton = UIButton(type: .system)

    private let padH: CGFloat = 16.sw
    private var isSubmitting = false

    init(context: AccountContext, clanId: Int64, member: ClanMemberRecord) {
        self.context = context
        self.clanId = clanId
        self.member = member
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var boxBackgroundColor: UIColor {
        let theme = ThemeManager.shared.current
        if theme == .light || theme == .sunrise {
            return UIColor.theme.secondary
        } else if theme == .system {
            return UIScreen.main.traitCollection.userInterfaceStyle == .light ? UIColor.theme.secondary : UIColor.theme.tertiary
        } else {
            return UIColor.theme.tertiary
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.theme.primary
        setupHeader()
        setupContent()
    }

    override func applyTheme() {
        super.applyTheme()
        let t = UIColor.theme
        view.backgroundColor = t.primary
        titleLabel.textColor = t.textStrong
        closeButton.tintColor = t.textStrong
        reasonTextView.backgroundColor = boxBackgroundColor
        reasonTextView.textColor = t.textStrong
        warningBanner.backgroundColor = boxBackgroundColor
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        closeButton.setImage(UIImage(systemName: "xmark")?.withRenderingMode(.alwaysTemplate), for: .normal)
        closeButton.tintColor = UIColor.theme.textStrong
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(closeButton)

        titleLabel.text = L(L10n.ClanSetting.Members.kickTitle)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 44.sh),

            closeButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16.sw),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24.swh),
            closeButton.heightAnchor.constraint(equalToConstant: 24.swh),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    private func setupContent() {
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 20.sh
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20.sh),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: padH),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -padH),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.bottomAnchor, constant: -20.sh),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * padH)
        ])

        let warningBanner = createWarningBanner()
        contentStack.addArrangedSubview(warningBanner)

        let displayName = member.clanNick.isEmpty ? member.displayName : member.clanNick
        let name = displayName.isEmpty ? member.username : displayName
        let confirmLabel = UILabel()
        confirmLabel.text = L(L10n.ClanSetting.Members.kickConfirmation, name)
        confirmLabel.font = .systemFont(ofSize: 14.sf, weight: .regular)
        confirmLabel.textColor = UIColor.theme.textDisabled
        confirmLabel.numberOfLines = 0
        contentStack.addArrangedSubview(confirmLabel)

        let reasonTitle = UILabel()
        reasonTitle.text = L(L10n.ClanSetting.Members.kickReason)
        reasonTitle.font = .systemFont(ofSize: 13.sf, weight: .regular)
        reasonTitle.textColor = UIColor.theme.textDisabled
        contentStack.addArrangedSubview(reasonTitle)

        reasonTextView.backgroundColor = boxBackgroundColor
        reasonTextView.font = .systemFont(ofSize: 14.sf, weight: .regular)
        reasonTextView.textColor = UIColor.theme.textStrong
        reasonTextView.layer.cornerRadius = 10.swh
        reasonTextView.clipsToBounds = true
        reasonTextView.textContainerInset = UIEdgeInsets(top: 12.sh, left: 10.sw, bottom: 12.sh, right: 10.sw)
        reasonTextView.isScrollEnabled = false
        reasonTextView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(reasonTextView)
        contentStack.setCustomSpacing(4.sh, after: reasonTitle)
        reasonTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100.sh).isActive = true

        kickButton.setTitle(L(L10n.ClanSetting.Members.kickButton), for: .normal)
        kickButton.titleLabel?.font = .systemFont(ofSize: 16.sf, weight: .bold)
        kickButton.backgroundColor = .systemRed
        kickButton.setTitleColor(.white, for: .normal)
        kickButton.setTitleColor(UIColor.white.withAlphaComponent(0.4), for: .disabled)
        kickButton.layer.cornerRadius = 10.swh
        kickButton.clipsToBounds = true
        kickButton.addTarget(self, action: #selector(kickConfirmed), for: .touchUpInside)
        kickButton.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(kickButton)
        kickButton.heightAnchor.constraint(equalToConstant: 46.sh).isActive = true
    }

    private func createWarningBanner() -> UIView {
        warningBanner.backgroundColor = boxBackgroundColor
        warningBanner.layer.cornerRadius = 12.swh
        warningBanner.clipsToBounds = true

        let displayName = member.clanNick.isEmpty ? member.displayName : member.clanNick
        let name = displayName.isEmpty ? member.username : displayName

        let clanRecord = context.account.postbox.read({ tx in tx.getClan(id: clanId) })
        let clanName = clanRecord?.name ?? ""

        let bannerText = UILabel()
        bannerText.numberOfLines = 0
        bannerText.textAlignment = .center
        bannerText.translatesAutoresizingMaskIntoConstraints = false

        let kickString = L(L10n.ClanSetting.Members.kickFromClan, name)
        let attrText = NSMutableAttributedString(
            string: kickString + "\n",
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .semibold),
                .foregroundColor: UIColor.systemRed
            ]
        )
        let clanNameAttr = NSAttributedString(
            string: clanName,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .semibold),
                .foregroundColor: UIColor.theme.textStrong
            ]
        )
        attrText.append(clanNameAttr)
        bannerText.attributedText = attrText

        warningBanner.addSubview(bannerText)

        NSLayoutConstraint.activate([
            bannerText.leadingAnchor.constraint(equalTo: warningBanner.leadingAnchor, constant: 14.sw),
            bannerText.trailingAnchor.constraint(equalTo: warningBanner.trailingAnchor, constant: -14.sw),
            bannerText.topAnchor.constraint(equalTo: warningBanner.topAnchor, constant: 14.sh),
            bannerText.bottomAnchor.constraint(equalTo: warningBanner.bottomAnchor, constant: -14.sh),
        ])

        return warningBanner
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func updateKickButton() {
        kickButton.isEnabled = !isSubmitting
        kickButton.backgroundColor = kickButton.isEnabled ? .systemRed : .systemRed.withAlphaComponent(0.5)
    }

    @objc private func kickConfirmed() {
        guard !isSubmitting else { return }
        isSubmitting = true
        updateKickButton()

        Task { [weak self] in
            guard let self else { return }
            do {
                guard let token = await self.context.getToken() else {
                    throw RolesRepositoryError.notAuthenticated
                }
                try await self.context.engine.account.network.removeClanUsers(
                    clanId: self.clanId,
                    userIds: [self.member.userId],
                    token: token
                )
                self.context.account.postbox.writeSync { tx in
                    let existingMembers = tx.getClanMembers(clanId: self.clanId)
                    let filtered = existingMembers.filter { $0.userId != self.member.userId }
                    tx.updateClanMembers(filtered, clanId: self.clanId)
                }
                self.context.engine.clanData.clanUsersUpdated.putNext(self.clanId)
                await MainActor.run {
                    Toast.success(L(L10n.ClanSetting.Members.kickSuccess))
                    self.onKickCompleted?()
                    self.dismiss(animated: true)
                }
            } catch {
                await MainActor.run {
                    self.isSubmitting = false
                    self.updateKickButton()
                    Toast.error(L(L10n.ClanSetting.Members.kickFailed))
                }
            }
        }
    }
}
