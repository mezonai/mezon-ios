import UIKit

final class JoinClanSheetViewController: UIViewController {

    private let context: AccountContext

    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let fieldContainer = UIView()
    private let textField = UITextField()
    private let primaryButton = UIButton(type: .system)
    private let activity = UIActivityIndicatorView.mezonMedium()

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSheet()
        applyTheme()
        titleLabel.text = L(L10n.Clan.joinClanTitle)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let xImg = UIImage.mezonSystemImage("xmark", withConfiguration: MezonSymbolConfiguration(pointSize: 15, weight: .semibold))
        closeButton.setImage(xImg, for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        fieldContainer.layer.cornerRadius = 12.swh
        fieldContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fieldContainer)

        textField.font = .systemFont(ofSize: 15.sf)
        textField.borderStyle = .none
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.returnKeyType = .join
        textField.clearButtonMode = .whileEditing
        textField.placeholder = L(L10n.Clan.inviteInputPlaceholder)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.addTarget(self, action: #selector(primaryTapped), for: .editingDidEndOnExit)
        fieldContainer.addSubview(textField)

        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.layer.cornerRadius = 12.swh
        primaryButton.titleLabel?.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        primaryButton.setTitle(L(L10n.Clan.joinAction), for: .normal)
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        view.addSubview(primaryButton)

        activity.hidesWhenStopped = true
        activity.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activity)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 56),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -56),

            fieldContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            fieldContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            fieldContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            fieldContainer.heightAnchor.constraint(equalToConstant: 48),

            textField.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor, constant: 12),
            textField.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor, constant: -12),
            textField.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor),

            primaryButton.topAnchor.constraint(equalTo: fieldContainer.bottomAnchor, constant: 16),
            primaryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            primaryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            primaryButton.heightAnchor.constraint(equalToConstant: 50),

            activity.centerXAnchor.constraint(equalTo: primaryButton.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: primaryButton.centerYAnchor),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(themeDidChange), name: ThemeManager.didChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func themeDidChange() {
        applyTheme()
    }

    private func configureSheet() {
        guard #available(iOS 15.0, *) else { return }
        guard let sheet = sheetPresentationController else { return }
        sheet.prefersGrabberVisible = true
        sheet.preferredCornerRadius = 16
        sheet.detents = [.medium()]
        sheet.prefersEdgeAttachedInCompactHeight = true
    }

    private func applyTheme() {
        view.backgroundColor = .mezonPrimary
        titleLabel.textColor = .mezonTextStrong
        closeButton.tintColor = .mezonTextStrong
        fieldContainer.backgroundColor = .mezonSecondary
        textField.textColor = .mezonTextStrong
        textField.tintColor = .mezonTextStrong
        let placeholder = L(L10n.Clan.inviteInputPlaceholder)
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )
        primaryButton.backgroundColor = UIColor(red: 0.44, green: 0.42, blue: 0.95, alpha: 1)
        primaryButton.setTitleColor(.white, for: .normal)
        primaryButton.setTitleColor(.white.withAlphaComponent(0.5), for: .disabled)
        activity.color = .white
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private static func normalizedInviteCode(from raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if let c = ClanInviteLinkParser.firstInviteCode(in: t) { return c }
        let digits = t.filter(\.isNumber)
        return digits.isEmpty ? nil : String(digits)
    }

    @objc private func primaryTapped() {
        if #available(iOS 13.0, *) {
            guard !activity.isAnimating else { return }
            guard let code = Self.normalizedInviteCode(from: textField.text ?? "") else {
                Toast.error(L(L10n.Clan.inviteInvalid))
                return
            }
            Task { @MainActor in
                guard let token = await context.getToken(), !token.isEmpty else {
                    Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                    return
                }
                primaryButton.isEnabled = false
                textField.isEnabled = false
                activity.startAnimating()
                do {
                    if let info = try? await context.engine.clanData.getInviteInfo(code: code, token: token),
                       let cid = info.clan_id.flatMap(Int64.init), cid != 0 {
                        await ClanChannelDescsGate.ensureFetchedBeforeJoin(context: context, clanId: cid, force: true)
                    }
                    let res = try await context.engine.clanData.joinClanWithInvite(code: code, token: token)
                    dismiss(animated: true) {
                        NotificationCenter.default.post(
                            name: .mezonQRSelectClan,
                            object: nil,
                            userInfo: ["clanId": "\(res.clanID)"]
                        )
                    }
                } catch {
                    Toast.error(error.localizedDescription)
                    primaryButton.isEnabled = true
                    textField.isEnabled = true
                    activity.stopAnimating()
                }
            }
        }
    }
}
