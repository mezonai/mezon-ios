import UIKit

final class SetPasswordViewController: BaseViewController {

    private let context: AccountContext
    private let hasPassword: Bool
    private let userEmail: String

    private let headerView = UIView()
    private let backButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "chevron.left",
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
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
    private let saveButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        sv.keyboardDismissMode = .interactive
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

    private let emailField = PasswordFormField(isPassword: false)
    private let currentPasswordField = PasswordFormField(isPassword: true)
    private let newPasswordField = PasswordFormField(isPassword: true)
    private let confirmPasswordField = PasswordFormField(isPassword: true)
    private let descriptionLabel: UILabel = {
        let l = UILabel()
        l.numberOfLines = 0
        l.font = .systemFont(ofSize: 13.sf)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private let side: CGFloat = 16.sw

    init(context: AccountContext, hasPassword: Bool, email: String) {
        self.context = context
        self.hasPassword = hasPassword
        self.userEmail = email
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
        headerView.addSubview(saveButton)

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        view.addSubview(loadingIndicator)

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

            saveButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16.sw),
            saveButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 8.sh),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        buildFormFields()
        registerKeyboardNotifications()
        updateSaveButtonState()
    }

    override func applyTheme() {
        view.backgroundColor = .mezonPrimary
        headerView.backgroundColor = .mezonPrimary
        scrollView.backgroundColor = .mezonPrimary

        titleLabel.text = L(L10n.SetPassword.title)
        titleLabel.textColor = .mezonTextStrong
        backButton.tintColor = .mezonTextStrong

        saveButton.setTitle(L(L10n.SetPassword.save), for: .normal)
        saveButton.setTitleColor(UIColor.theme.bgViolet, for: .normal)

        emailField.configure(
            label: L(L10n.SetPassword.email),
            placeholder: "",
            isRequired: false
        )
        emailField.setText(userEmail)
        emailField.setEditable(false)

        if hasPassword {
            currentPasswordField.configure(
                label: L(L10n.SetPassword.currentPassword),
                placeholder: L(L10n.SetPassword.currentPasswordPlaceholder),
                isRequired: true
            )
        }

        newPasswordField.configure(
            label: L(L10n.SetPassword.password),
            placeholder: L(L10n.SetPassword.passwordPlaceholder),
            isRequired: true
        )

        confirmPasswordField.configure(
            label: L(L10n.SetPassword.confirmPassword),
            placeholder: L(L10n.SetPassword.confirmPasswordPlaceholder),
            isRequired: true
        )

        descriptionLabel.text = L(L10n.SetPassword.description)
        descriptionLabel.textColor = .mezonTextPrimary

        loadingIndicator.color = .mezonTextPrimary
    }

    private func buildFormFields() {
        addFieldSection(emailField)

        if hasPassword {
            addFieldSection(currentPasswordField)
            currentPasswordField.onTextChanged = { [weak self] _ in
                self?.validateCurrentPasswordVsNew()
                self?.updateSaveButtonState()
            }
        }

        addFieldSection(newPasswordField)
        newPasswordField.onTextChanged = { [weak self] text in
            self?.validateNewPassword(text)
            self?.updateSaveButtonState()
        }

        let descContainer = UIView()
        descContainer.translatesAutoresizingMaskIntoConstraints = false
        descContainer.addSubview(descriptionLabel)
        NSLayoutConstraint.activate([
            descriptionLabel.topAnchor.constraint(equalTo: descContainer.topAnchor, constant: 6.sh),
            descriptionLabel.leadingAnchor.constraint(equalTo: descContainer.leadingAnchor, constant: side),
            descriptionLabel.trailingAnchor.constraint(equalTo: descContainer.trailingAnchor, constant: -side),
            descriptionLabel.bottomAnchor.constraint(equalTo: descContainer.bottomAnchor, constant: -8.sh),
        ])
        contentStack.addArrangedSubview(descContainer)

        addFieldSection(confirmPasswordField)
        confirmPasswordField.onTextChanged = { [weak self] text in
            self?.validateConfirmPassword(text)
            self?.updateSaveButtonState()
        }

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 40.sh).isActive = true
        contentStack.addArrangedSubview(spacer)
    }

    private func addFieldSection(_ field: PasswordFormField) {
        field.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(field)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: container.topAnchor, constant: 8.sh),
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: side),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -side),
            field.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4.sh),
        ])
        contentStack.addArrangedSubview(container)
    }

    private func updateSaveButtonState() {
        let currentPw = currentPasswordField.getText()
        let newPw = newPasswordField.getText()
        let confirmPw = confirmPasswordField.getText()

        var isValid = true

        if hasPassword && currentPw.isEmpty {
            isValid = false
        }
        if newPw.isEmpty || confirmPw.isEmpty {
            isValid = false
        }

        if isValid {
            if validatePassword(newPw) != nil {
                isValid = false
            } else if newPw != confirmPw {
                isValid = false
            } else if hasPassword && currentPw == newPw {
                isValid = false
            }
        }

        saveButton.isEnabled = isValid
        saveButton.alpha = isValid ? 1.0 : 0.5
    }

    private func validatePassword(_ value: String) -> String? {
        if value.count < 8 {
            return L(L10n.SetPassword.errorCharacters)
        }
        if value.range(of: "[A-Z]", options: .regularExpression) == nil {
            return L(L10n.SetPassword.errorUppercase)
        }
        if value.range(of: "[a-z]", options: .regularExpression) == nil {
            return L(L10n.SetPassword.errorLowercase)
        }
        if value.range(of: "[0-9]", options: .regularExpression) == nil {
            return L(L10n.SetPassword.errorNumber)
        }
        if value.range(of: "[^A-Za-z0-9]", options: .regularExpression) == nil {
            return L(L10n.SetPassword.errorSymbol)
        }
        return nil
    }

    private func validateNewPassword(_ text: String) {
        guard !text.isEmpty else {
            newPasswordField.setError(nil)
            return
        }
        let currentPw = currentPasswordField.getText()
        if hasPassword && !currentPw.isEmpty && currentPw == text {
            newPasswordField.setError(L(L10n.SetPassword.errorSamePass))
        } else {
            newPasswordField.setError(validatePassword(text))
        }
        let confirm = confirmPasswordField.getText()
        if !confirm.isEmpty && confirm != text {
            confirmPasswordField.setError(L(L10n.SetPassword.errorNotEqual))
        } else {
            confirmPasswordField.setError(nil)
        }
    }

    private func validateCurrentPasswordVsNew() {
        let currentPw = currentPasswordField.getText()
        let newPw = newPasswordField.getText()
        guard !newPw.isEmpty else { return }
        if !currentPw.isEmpty && currentPw == newPw {
            newPasswordField.setError(L(L10n.SetPassword.errorSamePass))
        } else {
            newPasswordField.setError(validatePassword(newPw))
        }
    }

    private func validateConfirmPassword(_ text: String) {
        let newPw = newPasswordField.getText()
        if !text.isEmpty && text != newPw {
            confirmPasswordField.setError(L(L10n.SetPassword.errorNotEqual))
        } else {
            confirmPasswordField.setError(nil)
        }
    }

    @objc private func saveTapped() {
        view.endEditing(true)

        let currentPw = currentPasswordField.getText()
        let newPw = newPasswordField.getText()
        let confirmPw = confirmPasswordField.getText()

        let passwordError = validatePassword(newPw)
        let confirmError = (newPw != confirmPw) ? L(L10n.SetPassword.errorNotEqual) : nil
        let samePass = hasPassword && !currentPw.isEmpty && !newPw.isEmpty && currentPw == newPw

        if passwordError != nil || confirmError != nil || samePass {
            newPasswordField.setError(samePass ? L(L10n.SetPassword.errorSamePass) : passwordError)
            confirmPasswordField.setError(confirmError)
            return
        }

        if newPw.isEmpty {
            newPasswordField.setError(validatePassword(newPw))
            return
        }

        submitPassword(email: userEmail, newPassword: newPw, oldPassword: hasPassword ? currentPw : nil)
    }

    private func submitPassword(email: String, newPassword: String, oldPassword: String?) {
        setLoading(true)

        Task { @MainActor in
            do {
                guard let token = await context.getToken() else {
                    setLoading(false)
                    Toast.error(L(L10n.SetPassword.toastError))
                    return
                }

                try await context.account.network.registrationPassword(
                    email: email,
                    password: newPassword,
                    oldPassword: oldPassword ?? "",
                    token: token
                )

                await context.refreshAccountProfile()

                if let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.account),
                   let api = try? Mezon_Api_Account(serializedData: data) {
                }

                setLoading(false)
                Toast.success(L(L10n.SetPassword.toastSuccess))
                navigationController?.popViewController(animated: true)

            } catch let error as MezonError {
                setLoading(false)
                switch error {
                case .httpError(let statusCode, let message):
                    if statusCode == 400 || message.lowercased().contains("invalid") {
                        let errorMsg = oldPassword != nil && !oldPassword!.isEmpty
                            ? L(L10n.SetPassword.errorIncorrectCurrent)
                            : L(L10n.SetPassword.errorCreateFail)
                        Toast.error(errorMsg)
                    } else {
                        let errorMsg = oldPassword != nil && !oldPassword!.isEmpty
                            ? L(L10n.SetPassword.errorUpdateFail)
                            : L(L10n.SetPassword.errorCreateFail)
                        Toast.error(errorMsg)
                    }
                default:
                    Toast.error(L(L10n.SetPassword.toastError))
                }
            } catch {
                setLoading(false)
                let errorMsg = oldPassword != nil && !oldPassword!.isEmpty
                    ? L(L10n.SetPassword.errorUpdateFail)
                    : L(L10n.SetPassword.errorCreateFail)
                Toast.error(errorMsg)
            }
        }
    }

    private func setLoading(_ loading: Bool) {
        if loading {
            loadingIndicator.startAnimating()
            saveButton.isEnabled = false
            saveButton.alpha = 0.5
        } else {
            loadingIndicator.stopAnimating()
            updateSaveButtonState()
        }
        scrollView.isUserInteractionEnabled = !loading
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    private func registerKeyboardNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillShow(_ note: Notification) {
        guard let info = note.userInfo,
              let frame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let inset = frame.height - view.safeAreaInsets.bottom
        scrollView.contentInset.bottom = inset
        scrollView.verticalScrollIndicatorInsets.bottom = inset
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

private final class PasswordFormField: UIView {

    var onTextChanged: ((String) -> Void)?
    private let isPassword: Bool

    private let labelView: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let requiredMark: UILabel = {
        let l = UILabel()
        l.text = " *"
        l.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        l.textColor = .systemRed
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

    private let textField: UITextField = {
        let tf = UITextField()
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.font = .systemFont(ofSize: 15.sf)
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private let toggleButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let errorLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12.sf)
        l.textColor = .systemRed
        l.numberOfLines = 0
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private var isSecure = true

    init(isPassword: Bool) {
        self.isPassword = isPassword
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        addSubview(labelView)
        addSubview(requiredMark)
        addSubview(inputContainer)
        addSubview(errorLabel)

        inputContainer.addSubview(textField)
        textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)

        if isPassword {
            inputContainer.addSubview(toggleButton)
            textField.isSecureTextEntry = true
            updateToggleIcon()
            toggleButton.addTarget(self, action: #selector(toggleVisibility), for: .touchUpInside)

            NSLayoutConstraint.activate([
                toggleButton.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -12.sw),
                toggleButton.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
                toggleButton.widthAnchor.constraint(equalToConstant: 28.sw),
                toggleButton.heightAnchor.constraint(equalToConstant: 28.sh),
                textField.trailingAnchor.constraint(equalTo: toggleButton.leadingAnchor, constant: -4.sw),
            ])
        } else {
            NSLayoutConstraint.activate([
                textField.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -12.sw),
            ])
        }

        NSLayoutConstraint.activate([
            labelView.topAnchor.constraint(equalTo: topAnchor),
            labelView.leadingAnchor.constraint(equalTo: leadingAnchor),

            requiredMark.leadingAnchor.constraint(equalTo: labelView.trailingAnchor),
            requiredMark.topAnchor.constraint(equalTo: labelView.topAnchor),

            inputContainer.topAnchor.constraint(equalTo: labelView.bottomAnchor, constant: 8.sh),
            inputContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputContainer.heightAnchor.constraint(equalToConstant: 48.sh),

            textField.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 12.sw),
            textField.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            textField.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor),

            errorLabel.topAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: 4.sh),
            errorLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            errorLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        applyFieldTheme()
    }

    private func applyFieldTheme() {
        labelView.textColor = .mezonTextStrong
        inputContainer.backgroundColor = .mezonSecondaryBackground
        inputContainer.layer.borderColor = UIColor.mezonSeparator.cgColor
        textField.textColor = .mezonTextStrong
        toggleButton.tintColor = .mezonTextPrimary
    }

    func configure(label: String, placeholder: String, isRequired: Bool) {
        labelView.text = label
        requiredMark.isHidden = !isRequired
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.mezonTextPrimary.withAlphaComponent(0.5)]
        )
        applyFieldTheme()
    }

    func setText(_ text: String) {
        textField.text = text
    }

    func getText() -> String {
        return (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setEditable(_ editable: Bool) {
        textField.isEnabled = editable
        textField.alpha = editable ? 1.0 : 0.7
    }

    func setError(_ error: String?) {
        if let error, !error.isEmpty {
            errorLabel.text = error
            errorLabel.isHidden = false
            inputContainer.layer.borderColor = UIColor.systemRed.cgColor
        } else {
            errorLabel.text = nil
            errorLabel.isHidden = true
            inputContainer.layer.borderColor = UIColor.mezonSeparator.cgColor
        }
    }

    @objc private func textDidChange() {
        onTextChanged?(getText())
    }

    @objc private func toggleVisibility() {
        isSecure.toggle()
        textField.isSecureTextEntry = isSecure
        updateToggleIcon()
    }

    private func updateToggleIcon() {
        let name = isSecure ? "eye.slash" : "eye"
        let img = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular))
        toggleButton.setImage(img, for: .normal)
    }
}
