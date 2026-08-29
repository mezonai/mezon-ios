import UIKit

final class UpdatePhoneNumberViewController: BaseViewController {

    private let context: AccountContext
    private let currentPhone: String

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

    private let newPhoneLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14.sf, weight: .regular)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let prefixContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 8.swh
        v.layer.borderWidth = 1
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let flagLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 20)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let prefixLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf, weight: .medium)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let dropdownIcon: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage.mezonSystemImage("chevron.down",
                           withConfiguration: MezonSymbolConfiguration(pointSize: 12, weight: .semibold))
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let phoneContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 8.swh
        v.layer.borderWidth = 1
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let phoneTextField: UITextField = {
        let tf = UITextField()
        tf.keyboardType = .phonePad
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

    private struct Country {
        let flag: String
        let name: String
        let prefix: String
    }

    private let countries: [Country] = [
        Country(flag: "🇻🇳", name: "Vietnam", prefix: "+84"),
        Country(flag: "🇯🇵", name: "Japan",   prefix: "+81"),
        Country(flag: "🇺🇸", name: "USA",     prefix: "+1"),
    ]
    private var selectedCountry: Country!


    private static let otpCooldownSeconds = 60
    private static let otpCacheKey = "mezon_otp_cooldown_cache_phone"
    private var cooldownTimer: Foundation.Timer?
    private var remainingTime: Int = 0
    private var activeCooldownPhone: String?

    init(context: AccountContext, currentPhone: String = "") {
        self.context = context
        self.currentPhone = currentPhone
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
        selectedCountry = countries[0]

        if !currentPhone.isEmpty {
            for c in countries {
                if currentPhone.hasPrefix(c.prefix) {
                    selectedCountry = c
                    let remaining = String(currentPhone.dropFirst(c.prefix.count))
                    phoneTextField.text = remaining
                    break
                }
            }
        }

        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        headerView.addSubview(backButton)
        headerView.addSubview(titleLabel)

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        view.addSubview(newPhoneLabel)

        let inputRow = UIStackView()
        inputRow.axis = .horizontal
        inputRow.spacing = 8.sw
        inputRow.alignment = .fill
        inputRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputRow)

        prefixContainer.addSubview(flagLabel)
        prefixContainer.addSubview(prefixLabel)
        prefixContainer.addSubview(dropdownIcon)

        let prefixTap = UITapGestureRecognizer(target: self, action: #selector(showCountryPicker))
        prefixContainer.addGestureRecognizer(prefixTap)
        prefixContainer.isUserInteractionEnabled = true

        NSLayoutConstraint.activate([
            flagLabel.leadingAnchor.constraint(equalTo: prefixContainer.leadingAnchor, constant: 10.sw),
            flagLabel.centerYAnchor.constraint(equalTo: prefixContainer.centerYAnchor),

            prefixLabel.leadingAnchor.constraint(equalTo: flagLabel.trailingAnchor, constant: 6.sw),
            prefixLabel.centerYAnchor.constraint(equalTo: prefixContainer.centerYAnchor),

            dropdownIcon.leadingAnchor.constraint(equalTo: prefixLabel.trailingAnchor, constant: 4.sw),
            dropdownIcon.trailingAnchor.constraint(equalTo: prefixContainer.trailingAnchor, constant: -10.sw),
            dropdownIcon.centerYAnchor.constraint(equalTo: prefixContainer.centerYAnchor),
            dropdownIcon.widthAnchor.constraint(equalToConstant: 14),
        ])

        inputRow.addArrangedSubview(prefixContainer)
        prefixContainer.setContentHuggingPriority(.required, for: .horizontal)
        prefixContainer.setContentCompressionResistancePriority(.required, for: .horizontal)
        prefixContainer.widthAnchor.constraint(equalToConstant: 110.sw).isActive = true

        phoneContainer.addSubview(phoneTextField)
        NSLayoutConstraint.activate([
            phoneTextField.leadingAnchor.constraint(equalTo: phoneContainer.leadingAnchor, constant: 12.sw),
            phoneTextField.trailingAnchor.constraint(equalTo: phoneContainer.trailingAnchor, constant: -12.sw),
            phoneTextField.topAnchor.constraint(equalTo: phoneContainer.topAnchor),
            phoneTextField.bottomAnchor.constraint(equalTo: phoneContainer.bottomAnchor),
        ])
        inputRow.addArrangedSubview(phoneContainer)
        phoneContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        phoneContainer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        view.addSubview(errorLabel)
        view.addSubview(nextButton)
        view.addSubview(loadingIndicator)

        phoneTextField.addTarget(self, action: #selector(phoneTextChanged), for: .editingChanged)
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

            newPhoneLabel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 24.sh),
            newPhoneLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            newPhoneLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),

            inputRow.topAnchor.constraint(equalTo: newPhoneLabel.bottomAnchor, constant: 8.sh),
            inputRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            inputRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            inputRow.heightAnchor.constraint(equalToConstant: 48.sh),

            errorLabel.topAnchor.constraint(equalTo: inputRow.bottomAnchor, constant: 6.sh),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),

            nextButton.topAnchor.constraint(equalTo: inputRow.bottomAnchor, constant: 40.sh),
            nextButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            nextButton.heightAnchor.constraint(equalToConstant: 48.sh),

            loadingIndicator.centerXAnchor.constraint(equalTo: nextButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor),
        ])

        phoneTextField.becomeFirstResponder()
        updateCountryUI()
        updateNextButtonState()
        loadCooldownCache()
    }

    override func applyTheme() {
        titleLabel.text = L(L10n.PhoneSetting.updatePhoneTitle)
        titleLabel.textColor = .mezonTextStrong
        backButton.tintColor = .mezonTextStrong
        headerView.backgroundColor = .mezonPrimary
        view.backgroundColor = .mezonPrimary

        newPhoneLabel.text = L(L10n.PhoneSetting.newPhoneNumber)
        newPhoneLabel.textColor = .mezonTextPrimary

        prefixContainer.backgroundColor = .mezonSecondaryBackground
        prefixContainer.layer.borderColor = UIColor.mezonSeparator.cgColor
        prefixLabel.textColor = .mezonTextStrong
        dropdownIcon.tintColor = .mezonTextPrimary

        phoneContainer.backgroundColor = .mezonSecondaryBackground
        phoneContainer.layer.borderColor = UIColor.mezonSeparator.cgColor
        phoneTextField.textColor = .mezonTextStrong
        phoneTextField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.PhoneSetting.phonePlaceholder),
            attributes: [.foregroundColor: UIColor.mezonTextPrimary.withAlphaComponent(0.5)]
        )

        errorLabel.text = L(L10n.PhoneSetting.invalidPhoneNumber)

        nextButton.setTitle(L(L10n.PhoneSetting.nextButton), for: .normal)
        nextButton.setTitleColor(.white, for: .normal)
        updateNextButtonState()
    }

    private func updateCountryUI() {
        flagLabel.text = selectedCountry.flag
        prefixLabel.text = selectedCountry.prefix
    }

    @objc private func showCountryPicker() {
        let sheet = UIAlertController(title: L(L10n.Login.selectCountry), message: nil, preferredStyle: .actionSheet)
        for country in countries {
            let title = "\(country.flag) \(country.name) (\(country.prefix))"
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self else { return }
                self.selectedCountry = country
                self.updateCountryUI()
                self.validateAndUpdateUI()
            })
        }
        sheet.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = prefixContainer
        }
        present(sheet, animated: true)
    }

    private func isValidPhone(_ phone: String, prefix: String) -> Bool {
        let cleaned = phone.trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { return false }
        if prefix == "+84" {
            let p = cleaned.hasPrefix("0") ? String(cleaned.dropFirst()) : cleaned
            return p.count == 9 && p.allSatisfy { $0.isNumber }
        }
        return cleaned.count >= 7 && cleaned.allSatisfy { $0.isNumber }
    }

    private var isFormValid: Bool {
        let phone = (phoneTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidPhone(phone, prefix: selectedCountry.prefix)
    }

    private func validateAndUpdateUI() {
        let phone = (phoneTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = phone.isEmpty || isValidPhone(phone, prefix: selectedCountry.prefix)
        errorLabel.isHidden = valid || phone.isEmpty
        updateNextButtonState()

        let full = buildFullPhone()
        if let cachedTime = getCooldownTime(for: full) {
            let elapsed = Int(Date().timeIntervalSince1970 - cachedTime)
            let remaining = Self.otpCooldownSeconds - elapsed
            if remaining > 0 {
                startCooldownTimerUI(for: full, initialRemaining: remaining)
            } else {
                remainingTime = 0
                removeCooldown(for: full)
            }
        } else {
            remainingTime = 0
            cooldownTimer?.invalidate()
            activeCooldownPhone = nil
        }
    }

    private func updateNextButtonState() {
        let valid = isFormValid
        nextButton.isEnabled = valid
        nextButton.backgroundColor = valid ? UIColor.theme.bgViolet : UIColor.theme.textDisabled
        nextButton.alpha = 1.0
        nextButton.setTitleColor(UIColor.white.withAlphaComponent(valid ? 1.0 : 0.8), for: .normal)
    }

    private func buildFullPhone() -> String {
        var p = (phoneTextField.text ?? "").trimmingCharacters(in: .whitespaces)
        if selectedCountry.prefix == "+84" && p.hasPrefix("0") { p = String(p.dropFirst()) }
        return "\(selectedCountry.prefix)\(p)"
    }

    @objc private func phoneTextChanged() {
        validateAndUpdateUI()
    }

    @objc private func nextTapped() {
        if #available(iOS 13.0, *) {
            let phone = (phoneTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phone.isEmpty, isValidPhone(phone, prefix: selectedCountry.prefix) else { return }

            let fullPhone = buildFullPhone()

            if let cachedTime = getCooldownTime(for: fullPhone) {
                let elapsed = Int(Date().timeIntervalSince1970 - cachedTime)
                let remaining = Self.otpCooldownSeconds - elapsed
                if remaining > 0 {
                    Toast.error(String(format: L(L10n.PhoneSetting.tooFast), remaining))
                    return
                }
            }

            if fullPhone == currentPhone, !currentPhone.isEmpty {
                Toast.error(L(L10n.PhoneSetting.phoneAlreadyLinked))
                return
            }

            callLinkPhoneAPI(phone: fullPhone)
        }
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @available(iOS 13.0, *)
    private func callLinkPhoneAPI(phone: String) {
        setLoading(true)

        Task { @MainActor in
            do {
                guard let token = await context.getToken() else {
                    setLoading(false)
                    showUpdateFailedToast()
                    return
                }

                let response = try await context.account.network.linkSMS(
                    phoneNumber: phone,
                    token: token
                )

                setLoading(false)

                guard let reqId = response.reqId, !reqId.isEmpty else {
                    showUpdateFailedToast()
                    return
                }

                setCooldownTime(for: phone)
                startCooldownTimerUI(for: phone, initialRemaining: Self.otpCooldownSeconds)

                let verifyVC = VerifyPhoneOTPViewController(
                    context: context,
                    phoneNumber: phone,
                    requestId: reqId
                )
                navigationController?.pushViewController(verifyVC, animated: true)

            } catch {
                setLoading(false)
                Toast.error(L(L10n.PhoneSetting.updateFailed))
            }
        }
    }

    private func showUpdateFailedToast(_ detailMessage: String = "") {
        let title = L(L10n.PhoneSetting.updateFailed)
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
            nextButton.setTitle(L(L10n.PhoneSetting.nextButton), for: .normal)
            updateNextButtonState()
        }
        phoneTextField.isEnabled = !loading
    }

    private func getCooldownTime(for phone: String) -> TimeInterval? {
        let cache = UserDefaults.standard.dictionary(forKey: Self.otpCacheKey) as? [String: Double] ?? [:]
        return cache[phone]
    }

    private func setCooldownTime(for phone: String) {
        var cache = UserDefaults.standard.dictionary(forKey: Self.otpCacheKey) as? [String: Double] ?? [:]
        cache[phone] = Date().timeIntervalSince1970
        UserDefaults.standard.set(cache, forKey: Self.otpCacheKey)
    }

    private func removeCooldown(for phone: String) {
        var cache = UserDefaults.standard.dictionary(forKey: Self.otpCacheKey) as? [String: Double] ?? [:]
        cache.removeValue(forKey: phone)
        UserDefaults.standard.set(cache, forKey: Self.otpCacheKey)
    }

    private func saveCooldownCache() {
        var cache = UserDefaults.standard.dictionary(forKey: Self.otpCacheKey) as? [String: Double] ?? [:]
        let now = Date().timeIntervalSince1970
        cache = cache.filter { now - $0.value < Double(Self.otpCooldownSeconds) }
        UserDefaults.standard.set(cache, forKey: Self.otpCacheKey)
    }

    private func loadCooldownCache() {
        let phone = buildFullPhone()
        guard !phone.isEmpty, let cachedTime = getCooldownTime(for: phone) else { return }
        let elapsed = Int(Date().timeIntervalSince1970 - cachedTime)
        let remaining = Self.otpCooldownSeconds - elapsed
        if remaining > 0 {
            startCooldownTimerUI(for: phone, initialRemaining: remaining)
        } else {
            removeCooldown(for: phone)
        }
    }

    private func startCooldownTimerUI(for phone: String, initialRemaining: Int) {
        activeCooldownPhone = phone
        remainingTime = max(0, initialRemaining)
        cooldownTimer?.invalidate()
        cooldownTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] (_: Foundation.Timer) in
            guard let self else { return }
            guard let trackedPhone = self.activeCooldownPhone else {
                self.cooldownTimer?.invalidate()
                self.cooldownTimer = nil
                self.remainingTime = 0
                return
            }

            guard let cachedTime = self.getCooldownTime(for: trackedPhone) else {
                self.cooldownTimer?.invalidate()
                self.cooldownTimer = nil
                self.remainingTime = 0
                self.activeCooldownPhone = nil
                return
            }

            let elapsed = Int(Date().timeIntervalSince1970 - cachedTime)
            let remaining = Self.otpCooldownSeconds - elapsed
            self.remainingTime = max(0, remaining)
            if remaining <= 0 {
                self.cooldownTimer?.invalidate()
                self.cooldownTimer = nil
                self.removeCooldown(for: trackedPhone)
                self.activeCooldownPhone = nil
            }
        }
    }
}
