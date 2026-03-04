import UIKit
import Combine

final class VerifyOTPViewController: BaseViewController {

    private let viewModel: VerifyOTPViewModel


    private lazy var backButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        btn.setTitle(" Quay lại", for: .normal)
        btn.tintColor = .systemIndigo
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 26.sf, weight: .bold)
        l.textColor = .label
        l.textAlignment = .center
        l.text = "Nhập mã OTP"
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var subtitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private var digitFields: [UITextField] = []
    private lazy var otpStack: UIStackView = {
        let fields = (0..<6).map { _ in makeDigitField() }
        digitFields = fields
        let sv = UIStackView(arrangedSubviews: fields)
        sv.axis = .horizontal
        sv.spacing = 10.sw
        sv.distribution = .fillEqually
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var submitButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Xác nhận", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        btn.setTitleColor(.white, for: .normal)
        btn.setTitleColor(UIColor.white.withAlphaComponent(0.5), for: .disabled)
        btn.backgroundColor = .systemIndigo
        btn.layer.cornerRadius = 14.sw
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var resendButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Gửi lại mã", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15.sf)
        btn.setTitleColor(.systemIndigo, for: .normal)
        btn.setTitleColor(.secondaryLabel, for: .disabled)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var errorLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13.sf)
        l.textColor = .systemRed
        l.textAlignment = .center
        l.numberOfLines = 0
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()


    init(viewModel: VerifyOTPViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }


    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
        digitFields.first?.becomeFirstResponder()
    }


    override func setupUI() {
        view.backgroundColor = .systemBackground
        navigationController?.setNavigationBarHidden(true, animated: false)

        let ctx = viewModel.otpContext
        let medium = ctx.type == .email ? "email" : "số điện thoại"
        subtitleLabel.text = "Mã OTP đã được gửi đến \(medium)\n\(ctx.target)"

        let contentStack = UIStackView(arrangedSubviews: [
            titleLabel, subtitleLabel,
            otpStack,
            submitButton, resendButton, errorLabel,
        ])
        contentStack.axis = .vertical
        contentStack.spacing = 16.sh
        contentStack.setCustomSpacing(8.sh, after: titleLabel)
        contentStack.setCustomSpacing(28.sh, after: subtitleLabel)
        contentStack.setCustomSpacing(28.sh, after: otpStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(backButton)
        view.addSubview(contentStack)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8.sh),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),

            contentStack.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 32.sh),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24.sw),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24.sw),

            otpStack.heightAnchor.constraint(equalToConstant: 56.sh),
            submitButton.heightAnchor.constraint(equalToConstant: 52.sh),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }


    override func setupBindings() {
        backButton.tapPublisher
            .sink { [weak self] in self?.navigationController?.popViewController(animated: true) }
            .store(in: &cancellables)

        submitButton.tapPublisher
            .sink { [weak self] in self?.viewModel.submitTrigger.send() }
            .store(in: &cancellables)

        resendButton.tapPublisher
            .sink { [weak self] in self?.viewModel.resendTrigger.send() }
            .store(in: &cancellables)

        viewModel.$isSubmitEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.submitButton.isEnabled = enabled
                UIView.animate(withDuration: 0.2) { self?.submitButton.alpha = enabled ? 1 : 0.5 }
            }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                if loading { self?.loadingIndicator.startAnimating() } else { self?.loadingIndicator.stopAnimating() }
                self?.submitButton.isUserInteractionEnabled = !loading
                self?.resendButton.isUserInteractionEnabled = !loading
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                self?.errorLabel.text = msg
                self?.errorLabel.isHidden = msg == nil
                if msg != nil { self?.shakeOTPFields() }
            }
            .store(in: &cancellables)

        viewModel.$resendCooldown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in
                if seconds > 0 {
                    self?.resendButton.setTitle("Gửi lại sau \(seconds)s", for: .normal)
                    self?.resendButton.isEnabled = false
                } else {
                    self?.resendButton.setTitle("Gửi lại mã", for: .normal)
                    self?.resendButton.isEnabled = true
                }
            }
            .store(in: &cancellables)

        for field in digitFields {
            field.addTarget(self, action: #selector(digitFieldChanged(_:)), for: .editingChanged)
        }
    }


    @objc private func digitFieldChanged(_ field: UITextField) {
        let text = field.text ?? ""

        if text.count == 6 && text.allSatisfy({ $0.isNumber }) {
            for (i, char) in text.enumerated() where i < digitFields.count {
                digitFields[i].text = String(char)
            }
            updateOTPCode()
            digitFields.last?.becomeFirstResponder()
            return
        }

        if text.count > 1 {
            field.text = String(text.last!)
        }
        updateOTPCode()

        if let idx = digitFields.firstIndex(of: field), field.text?.isEmpty == false {
            if idx + 1 < digitFields.count {
                digitFields[idx + 1].becomeFirstResponder()
            } else {
                field.resignFirstResponder()
            }
        }
    }

    private func updateOTPCode() {
        let code = digitFields.compactMap { $0.text }.joined()
        viewModel.otpCode = code
    }

    private func makeDigitField() -> UITextField {
        let tf = OTPDigitTextField()
        tf.keyboardType = .numberPad
        tf.textAlignment = .center
        tf.font = .systemFont(ofSize: 22.sf, weight: .semibold)
        tf.layer.cornerRadius = 12.sw
        tf.layer.borderWidth = 1.5
        tf.layer.borderColor = UIColor.separator.cgColor
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.delegate = self
        return tf
    }

    private func shakeOTPFields() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.5
        animation.values = [-10, 10, -8, 8, -5, 5, 0]
        otpStack.layer.add(animation, forKey: "shake")
    }
}


extension VerifyOTPViewController: UITextFieldDelegate {
    func textField(_ tf: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string.isEmpty && (tf.text?.isEmpty == true) {
            if let idx = digitFields.firstIndex(of: tf), idx > 0 {
                digitFields[idx - 1].text = ""
                digitFields[idx - 1].becomeFirstResponder()
                updateOTPCode()
            }
            return false
        }
        return string.allSatisfy { $0.isNumber }
    }
}


private final class OTPDigitTextField: UITextField {
    override func deleteBackward() {
        super.deleteBackward()
        sendActions(for: .editingChanged)
    }
}
