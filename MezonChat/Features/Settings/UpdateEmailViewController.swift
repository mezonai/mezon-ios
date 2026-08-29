import UIKit

final class UpdateEmailViewController: BaseViewController {

    private let context: AccountContext
    private let currentEmail: String

    private let headerView = UIView()
    private let backButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage.mezonSystemImage(
            "chevron.left",
            withConfiguration: MezonSymbolConfiguration(pointSize: 18, weight: .medium)
        )
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

    private let newEmailLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14.sf, weight: .regular)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let inputContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 8.swh
        v.layer.borderWidth = 1
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let emailIcon: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage.mezonSystemImage("envelope",
                           withConfiguration: MezonSymbolConfiguration(pointSize: 18, weight: .regular))
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let emailTextField: UITextField = {
        let tf = UITextField()
        tf.keyboardType = .emailAddress
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.font = .systemFont(ofSize: 15.sf)
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private let errorLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12.sf)
        l.textColor = .systemRed
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let nextButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        btn.layer.cornerRadius = 8.swh
        btn.clipsToBounds = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView.mezonMedium()
        ai.hidesWhenStopped = true
        ai.color = .white
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private static let otpCooldownSeconds = 60
    private static let otpCacheKey = "mezon_otp_cooldown_cache_email"
    private var cooldownTimer: Foundation.Timer?
    private var remainingTime: Int = 0
    private var activeCooldownEmail: String?

    init(context: AccountContext, currentEmail: String = "") {
        self.context = context
        self.currentEmail = currentEmail
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cooldownTimer?.invalidate()
        saveCooldownCache()
    }

    override func setupUI() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        headerView.addSubview(backButton)
        headerView.addSubview(titleLabel)

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        view.addSubview(newEmailLabel)
        view.addSubview(inputContainer)
        inputContainer.addSubview(emailIcon)
        inputContainer.addSubview(emailTextField)
        view.addSubview(errorLabel)
        view.addSubview(nextButton)
        view.addSubview(loadingIndicator)

        emailTextField.addTarget(self, action: #selector(emailTextChanged), for: .editingChanged)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

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

            newEmailLabel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 24.sh),
            newEmailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            newEmailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),

            inputContainer.topAnchor.constraint(equalTo: newEmailLabel.bottomAnchor, constant: 8.sh),
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            inputContainer.heightAnchor.constraint(equalToConstant: 48.sh),

            emailIcon.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 12.sw),
            emailIcon.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            emailIcon.widthAnchor.constraint(equalToConstant: 24.sw),
            emailIcon.heightAnchor.constraint(equalToConstant: 24.sh),

            emailTextField.leadingAnchor.constraint(equalTo: emailIcon.trailingAnchor, constant: 10.sw),
            emailTextField.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -12.sw),
            emailTextField.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            emailTextField.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor),

            errorLabel.topAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: 6.sh),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),

            nextButton.topAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: 40.sh),
            nextButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            nextButton.heightAnchor.constraint(equalToConstant: 48.sh),

            loadingIndicator.centerXAnchor.constraint(equalTo: nextButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor),
        ])

        if !currentEmail.isEmpty {
            emailTextField.text = currentEmail
        }
        emailTextField.becomeFirstResponder()
        updateNextButtonState()
        loadCooldownCache()
    }

    override func applyTheme() {
        titleLabel.text = L(L10n.EmailSetting.updateEmailTitle)
        titleLabel.textColor = .mezonTextStrong
        backButton.tintColor = .mezonTextStrong
        headerView.backgroundColor = .mezonPrimary
        view.backgroundColor = .mezonPrimary

        newEmailLabel.text = L(L10n.EmailSetting.newEmail)
        newEmailLabel.textColor = .mezonTextPrimary

        inputContainer.backgroundColor = .mezonSecondaryBackground
        inputContainer.layer.borderColor = UIColor.mezonSeparator.cgColor
        emailIcon.tintColor = .mezonTextPrimary
        emailTextField.textColor = .mezonTextStrong
        emailTextField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.EmailSetting.newEmail),
            attributes: [.foregroundColor: UIColor.mezonTextPrimary.withAlphaComponent(0.5)]
        )

        errorLabel.text = L(L10n.EmailSetting.invalidEmail)

        nextButton.setTitle(L(L10n.EmailSetting.nextButton), for: .normal)
        nextButton.setTitleColor(.white, for: .normal)
        updateNextButtonState()
    }

    private func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let regex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: trimmed)
    }

    private var isFormValid: Bool {
        let trimmed = (emailTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && isValidEmail(trimmed)
    }

    private func updateNextButtonState() {
        let valid = isFormValid
        nextButton.isEnabled = valid
        nextButton.backgroundColor = valid ? UIColor.theme.bgViolet : UIColor.theme.textDisabled
        nextButton.alpha = 1.0
        nextButton.setTitleColor(UIColor.white.withAlphaComponent(valid ? 1.0 : 0.8), for: .normal)
    }

    @objc private func emailTextChanged() {
        let email = emailTextField.text ?? ""
        let valid = isValidEmail(email)
        errorLabel.isHidden = valid || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        updateNextButtonState()

        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cachedTime = getCooldownTime(for: trimmed) {
            let elapsed = Int(Date().timeIntervalSince1970 - cachedTime)
            let remaining = Self.otpCooldownSeconds - elapsed
            if remaining > 0 {
                startCooldownTimerUI(for: trimmed, initialRemaining: remaining)
            } else {
                remainingTime = 0
                removeCooldown(for: trimmed)
            }
        } else {
            remainingTime = 0
            cooldownTimer?.invalidate()
            activeCooldownEmail = nil
        }
    }

    @objc private func nextTapped() {
        if #available(iOS 13.0, *) {
            let email = (emailTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !email.isEmpty, isValidEmail(email) else { return }

            if let cachedTime = getCooldownTime(for: email) {
                let elapsed = Int(Date().timeIntervalSince1970 - cachedTime)
                let remaining = Self.otpCooldownSeconds - elapsed
                if remaining > 0 {
                    Toast.error(String(format: L(L10n.EmailSetting.tooFast), remaining))
                    return
                }
            }

            if email.lowercased() == currentEmail.lowercased(), !currentEmail.isEmpty {
                Toast.error(L(L10n.EmailSetting.emailAlreadyLinked))
                return
            }

            callLinkEmailAPI(email: email)
        }
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @available(iOS 13.0, *)
    private func callLinkEmailAPI(email: String) {
        setLoading(true)

        Task { @MainActor in
            do {
                guard let token = await context.getToken() else {
                    setLoading(false)
                    showUpdateFailedToast()
                    return
                }

                let response = try await context.account.network.linkEmail(
                    email: email,
                    token: token
                )

                setLoading(false)

                guard let reqId = response.reqId, !reqId.isEmpty else {
                    showUpdateFailedToast()
                    return
                }

                setCooldownTime(for: email)
                startCooldownTimerUI(for: email, initialRemaining: Self.otpCooldownSeconds)

                let verifyVC = VerifyEmailOTPViewController(
                    context: context,
                    email: email,
                    requestId: reqId
                )
                navigationController?.pushViewController(verifyVC, animated: true)

            } catch {
                setLoading(false)
                Toast.error(L(L10n.EmailSetting.updateFailed))
            }
        }
    }

    private func showUpdateFailedToast(_ detailMessage: String = "") {
        let title = L(L10n.EmailSetting.updateFailed)
        let detail = detailMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            Toast.error(title)
        } else {
            Toast.error(detail, title: title)
        }
    }

    private func setLoading(_ loading: Bool) {
        if loading {
            loadingIndicator.startAnimating()
            nextButton.setTitle("", for: .normal)
            nextButton.isEnabled = false
        } else {
            loadingIndicator.stopAnimating()
            nextButton.setTitle(L(L10n.EmailSetting.nextButton), for: .normal)
            updateNextButtonState()
        }
        emailTextField.isEnabled = !loading
    }

    private func getCooldownTime(for email: String) -> TimeInterval? {
        let cache = UserDefaults.standard.dictionary(forKey: Self.otpCacheKey) as? [String: Double] ?? [:]
        return cache[email]
    }

    private func setCooldownTime(for email: String) {
        var cache = UserDefaults.standard.dictionary(forKey: Self.otpCacheKey) as? [String: Double] ?? [:]
        cache[email] = Date().timeIntervalSince1970
        UserDefaults.standard.set(cache, forKey: Self.otpCacheKey)
    }

    private func removeCooldown(for email: String) {
        var cache = UserDefaults.standard.dictionary(forKey: Self.otpCacheKey) as? [String: Double] ?? [:]
        cache.removeValue(forKey: email)
        UserDefaults.standard.set(cache, forKey: Self.otpCacheKey)
    }

    private func saveCooldownCache() {
        var cache = UserDefaults.standard.dictionary(forKey: Self.otpCacheKey) as? [String: Double] ?? [:]
        let now = Date().timeIntervalSince1970
        cache = cache.filter { now - $0.value < Double(Self.otpCooldownSeconds) }
        UserDefaults.standard.set(cache, forKey: Self.otpCacheKey)
    }

    private func loadCooldownCache() {
        let email = (emailTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, let cachedTime = getCooldownTime(for: email) else { return }
        let elapsed = Int(Date().timeIntervalSince1970 - cachedTime)
        let remaining = Self.otpCooldownSeconds - elapsed
        if remaining > 0 {
            startCooldownTimerUI(for: email, initialRemaining: remaining)
        } else {
            removeCooldown(for: email)
        }
    }

    private func startCooldownTimerUI(for email: String, initialRemaining: Int) {
        activeCooldownEmail = email
        remainingTime = max(0, initialRemaining)
        cooldownTimer?.invalidate()
        cooldownTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] (_: Foundation.Timer) in
            guard let self else { return }
            guard let trackedEmail = self.activeCooldownEmail else {
                self.cooldownTimer?.invalidate()
                self.cooldownTimer = nil
                self.remainingTime = 0
                return
            }

            guard let cachedTime = self.getCooldownTime(for: trackedEmail) else {
                self.cooldownTimer?.invalidate()
                self.cooldownTimer = nil
                self.remainingTime = 0
                self.activeCooldownEmail = nil
                return
            }

            let elapsed = Int(Date().timeIntervalSince1970 - cachedTime)
            let remaining = Self.otpCooldownSeconds - elapsed
            self.remainingTime = max(0, remaining)
            if remaining <= 0 {
                self.cooldownTimer?.invalidate()
                self.cooldownTimer = nil
                self.removeCooldown(for: trackedEmail)
                self.activeCooldownEmail = nil
            }
        }
    }

}
