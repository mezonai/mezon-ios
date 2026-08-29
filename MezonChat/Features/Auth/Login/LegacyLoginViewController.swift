import UIKit

final class LegacyLoginViewController: UIViewController {

    var onLoggedIn: (() -> Void)?

    private enum Step {
        case email
        case otp(reqId: String, email: String)
    }

    private var step: Step = .email
    private var lastEmail = ""

    // A MetaDisposable rather than a DisposableSet: starting a new request must
    // cancel the previous one, otherwise a late response can log the user in
    // after they have already navigated back.
    private let currentRequest = MetaDisposable()

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let inputField = UITextField()
    private let submitButton = UIButton(type: .system)
    private let resendButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .gray)
    private var centerYConstraint: NSLayoutConstraint?

    deinit {
        currentRequest.dispose()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        buildLayout()
        applyStep()
        observeKeyboard()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        inputField.becomeFirstResponder()
    }

    private func buildLayout() {
        titleLabel.text = "Mezon"
        titleLabel.font = UIFont.systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = .black
        titleLabel.textAlignment = .center

        subtitleLabel.font = UIFont.systemFont(ofSize: 15)
        subtitleLabel.textColor = UIColor(white: 0.35, alpha: 1.0)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        inputField.borderStyle = .roundedRect
        inputField.font = UIFont.systemFont(ofSize: 17)
        inputField.textColor = .black
        inputField.autocorrectionType = .no
        inputField.autocapitalizationType = .none
        inputField.clearButtonMode = .whileEditing
        inputField.addTarget(self, action: #selector(inputChanged), for: .editingChanged)

        submitButton.setTitleColor(.white, for: .normal)
        submitButton.setTitleColor(UIColor(white: 1.0, alpha: 0.6), for: .disabled)
        submitButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        submitButton.backgroundColor = UIColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1.0)
        submitButton.layer.cornerRadius = 10
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)

        resendButton.setTitle("Gửi lại mã", for: .normal)
        resendButton.titleLabel?.font = UIFont.systemFont(ofSize: 15)
        resendButton.addTarget(self, action: #selector(resendTapped), for: .touchUpInside)

        backButton.setTitle("Đổi email", for: .normal)
        backButton.titleLabel?.font = UIFont.systemFont(ofSize: 15)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.textColor = UIColor(red: 0.80, green: 0.20, blue: 0.20, alpha: 1.0)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        spinner.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, subtitleLabel, inputField, submitButton, resendButton, backButton, statusLabel, spinner
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.setCustomSpacing(24, after: subtitleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let centerY = stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        centerYConstraint = centerY
        NSLayoutConstraint.activate([
            centerY,
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            submitButton.heightAnchor.constraint(equalToConstant: 48),
            inputField.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func applyStep() {
        statusLabel.text = nil
        switch step {
        case .email:
            subtitleLabel.text = "Nhập email để nhận mã đăng nhập."
            inputField.placeholder = "email@example.com"
            inputField.keyboardType = .emailAddress
            inputField.text = lastEmail
            submitButton.setTitle("Gửi mã", for: .normal)
            resendButton.isHidden = true
            backButton.isHidden = true
        case .otp(_, let email):
            subtitleLabel.text = "Nhập mã gồm 6 chữ số đã gửi tới \(email)."
            inputField.placeholder = "000000"
            inputField.keyboardType = .numberPad
            inputField.text = ""
            submitButton.setTitle("Xác nhận", for: .normal)
            resendButton.isHidden = false
            backButton.isHidden = false
        }
        inputChanged()
        inputField.becomeFirstResponder()
    }

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let endFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            return
        }
        let keyboardTopY = view.convert(endFrame, from: nil).origin.y
        let overlap = max(0, view.bounds.height - keyboardTopY)
        applyKeyboardOffset(-overlap / 2, note: note)
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        applyKeyboardOffset(0, note: note)
    }

    private func applyKeyboardOffset(_ offset: CGFloat, note: Notification) {
        guard centerYConstraint?.constant != offset else { return }
        centerYConstraint?.constant = offset
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func backTapped() {
        currentRequest.set(nil)
        step = .email
        applyStep()
    }

    @objc private func inputChanged() {
        let value = (inputField.text ?? "").trimmingCharacters(in: .whitespaces)
        switch step {
        case .email:
            submitButton.isEnabled = value.contains("@") && value.count >= 5
        case .otp:
            submitButton.isEnabled = value.count >= 4
        }
        submitButton.alpha = submitButton.isEnabled ? 1.0 : 0.45
    }

    private func setBusy(_ busy: Bool) {
        inputField.isEnabled = !busy
        resendButton.isEnabled = !busy
        backButton.isEnabled = !busy
        if busy {
            submitButton.isEnabled = false
            submitButton.alpha = 0.45
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
            inputChanged()
        }
    }

    private func showError(_ error: MezonError) {
        statusLabel.text = error.technicalDescription
    }

    private func requestOTP(email: String) {
        statusLabel.text = nil
        setBusy(true)
        currentRequest.set((MezonHTTPClient.shared.signalAuthenticateEmailOTPRequest(email: email)
            |> deliverOnMainQueue).start(
                next: { [weak self] response in
                    guard let self = self else { return }
                    self.setBusy(false)
                    guard let reqId = response.reqId, !reqId.isEmpty else {
                        self.statusLabel.text = "Máy chủ không trả về mã yêu cầu."
                        return
                    }
                    self.lastEmail = email
                    self.step = .otp(reqId: reqId, email: email)
                    self.applyStep()
                },
                error: { [weak self] error in
                    self?.setBusy(false)
                    self?.showError(error)
                }
            ))
    }

    @objc private func resendTapped() {
        guard case .otp(_, let email) = step else { return }
        requestOTP(email: email)
    }

    @objc private func submitTapped() {
        let value = (inputField.text ?? "").trimmingCharacters(in: .whitespaces)
        view.endEditing(true)

        switch step {
        case .email:
            requestOTP(email: value)

        case .otp(let reqId, _):
            statusLabel.text = nil
            setBusy(true)
            currentRequest.set((MezonHTTPClient.shared.signalConfirmAuthenticateOTP(reqId: reqId, otp: value)
                |> deliverOnMainQueue).start(
                    next: { [weak self] session in
                        guard let self = self else { return }
                        self.setBusy(false)
                        LegacySessionManager.shared.store(session)
                        self.onLoggedIn?()
                    },
                    error: { [weak self] error in
                        self?.setBusy(false)
                        self?.showError(error)
                    }
                ))
        }
    }
}
