import UIKit

final class VerifyEmailOTPViewController: BaseViewController {

    private let context: AccountContext
    private let email: String
    private let requestId: String

    private let headerView = UIView()
    private let backButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(
            systemName: "chevron.left",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
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

    private let descriptionLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14.sf, weight: .regular)
        l.numberOfLines = 0
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private var otpFields: [UITextField] = []
    private let otpStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 10.sw
        sv.distribution = .fillEqually
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let verifyButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        btn.layer.cornerRadius = 8.swh
        btn.clipsToBounds = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private var isError: Bool = false {
        didSet { updateOTPFieldBorders() }
    }

    init(context: AccountContext, email: String, requestId: String) {
        self.context = context
        self.email = email
        self.requestId = requestId
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

        view.addSubview(descriptionLabel)
        view.addSubview(otpStackView)
        view.addSubview(verifyButton)
        view.addSubview(loadingIndicator)

        verifyButton.addTarget(self, action: #selector(verifyTapped), for: .touchUpInside)

        for i in 0..<6 {
            let field = createOTPField(tag: i)
            otpFields.append(field)
            otpStackView.addArrangedSubview(field)
        }

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

            descriptionLabel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 24.sh),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),

            otpStackView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 24.sh),
            otpStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            otpStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            otpStackView.heightAnchor.constraint(equalToConstant: 52.sh),

            verifyButton.topAnchor.constraint(equalTo: otpStackView.bottomAnchor, constant: 32.sh),
            verifyButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            verifyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            verifyButton.heightAnchor.constraint(equalToConstant: 48.sh),

            loadingIndicator.centerXAnchor.constraint(equalTo: verifyButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: verifyButton.centerYAnchor),
        ])

        otpFields.first?.becomeFirstResponder()
        updateVerifyButtonState()
    }

    override func applyTheme() {
        titleLabel.text = L(L10n.EmailSetting.verifyEmailTitle)
        titleLabel.textColor = .mezonTextStrong
        backButton.tintColor = .mezonTextStrong
        headerView.backgroundColor = .mezonPrimary
        view.backgroundColor = .mezonPrimary

        descriptionLabel.text = "\(L(L10n.EmailSetting.verifyDescription)) \(email)"
        descriptionLabel.textColor = .mezonTextPrimary

        verifyButton.setTitle(L(L10n.EmailSetting.verifyButton), for: .normal)
        verifyButton.setTitleColor(.white, for: .normal)

        for field in otpFields {
            field.textColor = .mezonTextStrong
            field.backgroundColor = .mezonSecondaryBackground
        }
        updateOTPFieldBorders()
        updateVerifyButtonState()
    }

    private func createOTPField(tag: Int) -> UITextField {
        let field = UITextField()
        field.tag = tag
        field.font = .systemFont(ofSize: 22.sf, weight: .bold)
        field.textAlignment = .center
        field.keyboardType = .numberPad
        field.layer.cornerRadius = 8.swh
        field.layer.borderWidth = 2
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        field.addTarget(self, action: #selector(otpFieldChanged(_:)), for: .editingChanged)
        return field
    }

    private func updateOTPFieldBorders() {
        let borderColor: UIColor = isError ? .systemRed : UIColor.theme.bgViolet
        for field in otpFields {
            let hasText = !(field.text ?? "").isEmpty
            field.layer.borderColor = hasText ? borderColor.cgColor : UIColor.mezonSeparator.cgColor
        }
    }

    private var otpCode: String {
        otpFields.compactMap { $0.text }.joined()
    }

    private var isValidOTP: Bool {
        let code = otpCode
        return code.count == 6 && code.allSatisfy(\.isNumber)
    }

    private func updateVerifyButtonState() {
        let valid = isValidOTP
        verifyButton.isEnabled = valid
        verifyButton.backgroundColor = valid ? UIColor.theme.bgViolet : UIColor.theme.textDisabled
        verifyButton.alpha = 1.0
        verifyButton.setTitleColor(UIColor.white.withAlphaComponent(valid ? 1.0 : 0.8), for: .normal)
    }

    @objc private func otpFieldChanged(_ field: UITextField) {
        if isError { isError = false }

        let text = field.text ?? ""
        if text.count > 1 {
            field.text = String(text.prefix(1))
        }

        updateOTPFieldBorders()
        updateVerifyButtonState()

        if !text.isEmpty, field.tag < 5 {
            otpFields[field.tag + 1].becomeFirstResponder()
        }

        if isValidOTP {
            handleVerify(otpCode)
        }
    }

    @objc private func verifyTapped() {
        guard isValidOTP else { return }
        handleVerify(otpCode)
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    private func handleVerify(_ otp: String) {
        setLoading(true)

        Task { @MainActor in
            do {
                guard let token = await context.getToken() else {
                    setLoading(false)
                    isError = true
                    return
                }

                try await context.account.network.confirmLinkEmailOTP(
                    reqId: requestId,
                    otpCode: otp,
                    token: token
                )

                if var user = context.currentUser {
                    user.email = email
                    context.applyCurrentUser(user)
                }

                setLoading(false)
                showSuccessAndPop()

            } catch {
                setLoading(false)
                isError = true
                showVerifyFailedToast()
            }
        }
    }

    private func setLoading(_ loading: Bool) {
        if loading {
            loadingIndicator.startAnimating()
            verifyButton.setTitle("", for: .normal)
            verifyButton.isEnabled = false
        } else {
            loadingIndicator.stopAnimating()
            verifyButton.setTitle(L(L10n.EmailSetting.verifyButton), for: .normal)
            updateVerifyButtonState()
        }
        otpFields.forEach { $0.isEnabled = !loading }
    }

    private func showSuccessAndPop() {
        Toast.success(L(L10n.EmailSetting.verifySuccess))
        if let accountSettingsVC = navigationController?.viewControllers.first(where: { $0 is AccountSettingsViewController }) {
            navigationController?.popToViewController(accountSettingsVC, animated: true)
        } else {
            navigationController?.popToRootViewController(animated: true)
        }
    }

    private func showVerifyFailedToast() {
        Toast.error(L(L10n.EmailSetting.updateFailed), title: "Error")
    }
}

extension VerifyEmailOTPViewController: UITextFieldDelegate {

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string.count == 6, string.allSatisfy(\.isNumber) {
            for (i, char) in string.enumerated() {
                otpFields[i].text = String(char)
            }
            otpFields.last?.becomeFirstResponder()
            if isError { isError = false }
            updateOTPFieldBorders()
            updateVerifyButtonState()
            if isValidOTP {
                handleVerify(otpCode)
            }
            return false
        }

        if !string.isEmpty && !string.allSatisfy(\.isNumber) {
            return false
        }

        if string.isEmpty && (textField.text ?? "").isEmpty && textField.tag > 0 {
            otpFields[textField.tag - 1].text = ""
            otpFields[textField.tag - 1].becomeFirstResponder()
            updateOTPFieldBorders()
            updateVerifyButtonState()
            return false
        }

        let currentText = textField.text ?? ""
        let newLength = currentText.count + string.count - range.length
        return newLength <= 1
    }
}
