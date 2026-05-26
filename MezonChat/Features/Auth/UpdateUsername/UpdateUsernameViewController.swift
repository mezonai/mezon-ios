import UIKit

final class UpdateUsernameViewController: BaseViewController, AuthScreenStatusBarStyle {

    private let pendingSession: MezonSession
    private let context: AccountContext
    private let otpContext: OTPContext

    private lazy var gradientLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.locations = [0, 0.5, 1]
        return layer
    }()

    private lazy var titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 24.sf, weight: .bold)
        l.textColor = .loginTitleColor
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var subtitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14.sf)
        l.textColor = .loginSubtitleColor
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var nameField: UITextField = {
        let tf = UITextField()
        tf.font = .systemFont(ofSize: 16.sf)
        tf.textColor = AppTheme.light.attributes.loginInputTextColor
        tf.backgroundColor = AppTheme.light.attributes.loginInputBg
        tf.layer.cornerRadius = 8.sw
        tf.layer.borderWidth = 1
        tf.layer.borderColor = AppTheme.light.attributes.loginInputBorder.cgColor
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.returnKeyType = .done
        tf.delegate = self
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.heightAnchor.constraint(equalToConstant: 48.sh).isActive = true
        let pad: CGFloat = 14.sw
        tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: pad, height: 1))
        tf.leftViewMode = .always
        tf.rightView = UIView(frame: CGRect(x: 0, y: 0, width: pad, height: 1))
        tf.rightViewMode = .always
        return tf
    }()

    private lazy var previewLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14.sf, weight: .medium)
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var actionButton: GradientButton = {
        let btn = GradientButton(type: .custom)
        btn.titleLabel?.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        btn.setTitleColor(.white, for: .normal)
        btn.setTitleColor(UIColor.white.withAlphaComponent(0.8), for: .disabled)
        btn.layer.cornerRadius = 8.sw
        btn.layer.masksToBounds = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.color = .white
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private lazy var skipQuestionLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14.sf)
        l.textColor = AppTheme.light.attributes.loginAlternativeText
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var skipLink: UIButton = {
        let b = UIButton(type: .system)
        b.titleLabel?.font = .systemFont(ofSize: 14.sf)
        b.setTitleColor(UIColor(hex: 0x2e22ff), for: .normal)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let submitPipe = ValuePipe<Void>()
    private var isLoading = false
    private weak var navigationControllerWherePopWasDisabled: UINavigationController?
    private var savedInteractivePopGestureEnabled: Bool = true

    init(pendingSession: MezonSession, context: AccountContext, otpContext: OTPContext) {
        self.pendingSession = pendingSession
        self.context = context
        self.otpContext = otpContext
        super.init(navigationBarPresentationData: nil)
        self.setStatusBarStyle(.Black, animated: false)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.setStatusBarStyle(.Black, animated: false)
        navigationItem.hidesBackButton = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if navigationControllerWherePopWasDisabled == nil, let nav = navigationController, let pop = nav.interactivePopGestureRecognizer {
            navigationControllerWherePopWasDisabled = nav
            savedInteractivePopGestureEnabled = pop.isEnabled
            pop.isEnabled = false
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        view.disablesInteractiveTransitionGestureRecognizer = false
        view.disablesInteractiveTransitionGestureRecognizerNow = nil
        if let nav = navigationControllerWherePopWasDisabled {
            nav.interactivePopGestureRecognizer?.isEnabled = savedInteractivePopGestureEnabled
            navigationControllerWherePopWasDisabled = nil
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.disablesInteractiveTransitionGestureRecognizer = true
        view.disablesInteractiveTransitionGestureRecognizerNow = { true }
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageChange), name: LanguageManager.didChangeNotification, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }

    override func setupUI() {
        view.layer.insertSublayer(gradientLayer, at: 0)
        navigationController?.setNavigationBarHidden(true, animated: false)

        let altStack = UIStackView(arrangedSubviews: [skipQuestionLabel, skipLink])
        altStack.axis = .vertical
        altStack.spacing = 8.sh
        altStack.alignment = .center

        let contentStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, nameField, previewLabel, actionButton, altStack])
        contentStack.axis = .vertical
        contentStack.spacing = 12.sh
        contentStack.setCustomSpacing(18.sh, after: titleLabel)
        contentStack.setCustomSpacing(20.sh, after: subtitleLabel)
        contentStack.setCustomSpacing(8.sh, after: nameField)
        contentStack.setCustomSpacing(24.sh, after: actionButton)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        view.addSubview(scroll)
        scroll.addSubview(contentStack)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 40.sh),
            contentStack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 22.sw),
            contentStack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -22.sw),
            contentStack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -40.sh),
            contentStack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -44.sw),
            actionButton.heightAnchor.constraint(equalToConstant: 50.sh),
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        skipLink.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        applyTheme()
        refreshLocalizedStrings()
        updateActionButtonEnabled()
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
    }

    override func setupBindings() {
        disposables.add(actionButton.tapSignal().start(next: { [weak self] in
            self?.submitPipe.putNext(())
        }))
        let filtered = submitPipe.signal() |> filter { [weak self] in
            guard let self else { return false }
            return !self.isLoading && !Self.sanitizeUsername(self.nameField.text ?? "").isEmpty
        }
        disposables.add((filtered |> deliverOnMainQueue).start(next: { [weak self] in
            Task { await self?.submitUsername() }
        }))
    }

    override func applyTheme() {
        let attrs = AppTheme.light.attributes
        gradientLayer.colors = attrs.loginGradientColors.map { $0.cgColor }
        titleLabel.textColor = attrs.loginTitleColor
        subtitleLabel.textColor = attrs.loginSubtitleColor
        nameField.backgroundColor = attrs.loginInputBg
        nameField.layer.borderColor = attrs.loginInputBorder.cgColor
        nameField.textColor = attrs.loginInputTextColor
        previewLabel.textColor = attrs.loginTitleColor
        skipQuestionLabel.textColor = attrs.loginAlternativeText
    }

    @objc private func handleLanguageChange() {
        refreshLocalizedStrings()
    }

    private func refreshLocalizedStrings() {
        titleLabel.text = L(L10n.UpdateUsername.enterUsername)
        subtitleLabel.text = L(L10n.UpdateUsername.usernamePlaceholder)
        nameField.placeholder = L(L10n.UpdateUsername.yourName)
        actionButton.setTitle(L(L10n.UpdateUsername.update), for: .normal)
        skipQuestionLabel.text = L(L10n.UpdateUsername.skipUpdateQuestion)
        skipLink.setTitle(L(L10n.UpdateUsername.skipUpdateBack), for: .normal)
        updatePreview()
    }

    @objc private func nameChanged() {
        updatePreview()
        updateActionButtonEnabled()
    }

    private func updatePreview() {
        let s = Self.sanitizeUsername(nameField.text ?? "")
        if s.isEmpty {
            previewLabel.text = nil
        } else {
            previewLabel.text = String(format: L(L10n.UpdateUsername.usernamePreview), s)
        }
    }

    private func updateActionButtonEnabled() {
        let ok = !Self.sanitizeUsername(nameField.text ?? "").isEmpty
        UIView.performWithoutAnimation {
            actionButton.isEnabled = ok && !isLoading
            if actionButton.isEnabled {
                actionButton.backgroundColor = .clear
                actionButton.setGradientHidden(false)
            } else {
                actionButton.backgroundColor = AppTheme.light.attributes.loginButtonBgDisabled
                actionButton.setGradientHidden(true)
            }
            actionButton.layoutIfNeeded()
        }
    }

    @objc private func skipTapped() {
        view.endEditing(true)
        if let nav = navigationController, let login = nav.viewControllers.first(where: { $0 is LoginViewController }) {
            SessionStore.clear()
            MandatoryUsernamePendingStore.clearPending()
            context.account.network.resetProtoBaseURLToDefault()
            nav.popToViewController(login, animated: true)
            return
        }
        let ctx = context
        dismiss(animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Task { @MainActor in
                ctx.account.network.resetProtoBaseURLToDefault()
                ctx.logout()
            }
        }
    }

    @MainActor private func submitUsername() async {
        let sanitized = Self.sanitizeUsername(nameField.text ?? "")
        guard !sanitized.isEmpty else { return }
        isLoading = true
        updateActionButtonEnabled()
        loadingIndicator.startAnimating()
        actionButton.isUserInteractionEnabled = false
        do {
            let authSession = context.session ?? pendingSession
            let proto = try await context.account.network.updateUsername(username: sanitized, token: authSession.token)
            guard !proto.token.isEmpty else {
                Toast.error(L(L10n.UpdateUsername.errorDuplicate))
                finishLoading()
                return
            }
            let merged = authSession.mergedWithUsernameResponse(proto, chosenUsername: sanitized)
            let mergedIds = merged.mergedPreservingIdToken(from: authSession)
            SessionStore.save(mergedIds)
            MandatoryUsernamePendingStore.clearPending()
            context.account.network.updateBaseURL(from: mergedIds)
            let uid = mergedIds.userId ?? UUID().uuidString
            let user = User(id: uid, username: sanitized, displayName: sanitized, avatarURL: nil, status: .online, bio: nil)
            context.login(user: user, session: mergedIds)
            MmnWalletPreloader.fetchAndPersistAfterLogin(session: mergedIds)
            if let nav = navigationController as? NavigationController,
               nav.viewControllers.contains(where: { $0 is TabBarController }) {
                nav.filterController(self, animated: true)
            }
        } catch {
            Toast.error(Self.toastMessage(for: error))
        }
        finishLoading()
    }

    private func finishLoading() {
        isLoading = false
        loadingIndicator.stopAnimating()
        actionButton.isUserInteractionEnabled = true
        updateActionButtonEnabled()
    }

    private static func sanitizeUsername(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = trimmed.folding(options: .diacriticInsensitive, locale: .current)
        var out = ""
        out.reserveCapacity(folded.count)
        for scalar in folded.unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            out.unicodeScalars.append(scalar)
        }
        return out
    }

    private static func toastMessage(for error: Error) -> String {
        if case let MezonError.httpError(_, message) = error {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? L(L10n.UpdateUsername.errorDuplicate) : message
    }
}

extension UpdateUsernameViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        let s = Self.sanitizeUsername(textField.text ?? "")
        if !s.isEmpty { submitPipe.putNext(()) }
        return true
    }
}

private final class GradientButton: UIButton {
    private let gradientLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [UIColor(hex: 0x501794).cgColor, UIColor(hex: 0x3E70A1).cgColor]
        layer.startPoint = CGPoint(x: 0, y: 0)
        layer.endPoint = CGPoint(x: 1, y: 0)
        return layer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.insertSublayer(gradientLayer, at: 0)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = layer.cornerRadius
    }

    func setGradientHidden(_ hidden: Bool) {
        gradientLayer.isHidden = hidden
    }
}
