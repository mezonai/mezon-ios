import UIKit
import Combine

final class LoginViewController: BaseViewController {

    private let viewModel: LoginViewModel


    private lazy var logoImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.image = UIImage(systemName: "bubble.left.and.bubble.right.fill")
        iv.tintColor = .systemIndigo
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private lazy var titleLabel: UILabel = {
        let l = UILabel()
        l.text = "Mezon"
        l.font = .systemFont(ofSize: 32.sf, weight: .bold)
        l.textColor = .label
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var subtitleLabel: UILabel = {
        let l = UILabel()
        l.text = "Đăng nhập để bắt đầu"
        l.font = .systemFont(ofSize: 15.sf)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var modeSegment: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["SMS", "Email OTP", "Mật khẩu"])
        sc.selectedSegmentIndex = 0
        sc.translatesAutoresizingMaskIntoConstraints = false
        return sc
    }()

    private lazy var phonePrefixButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "+84  ▾"
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12.sw, bottom: 0, trailing: 12.sw)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = .systemFont(ofSize: 16.sf)
            return a
        }
        let btn = UIButton(configuration: config)
        btn.layer.cornerRadius = 12.sw
        btn.layer.borderWidth = 1.5
        btn.layer.borderColor = UIColor.separator.cgColor
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var phoneTextField: UITextField = {
        let tf = makeTextField(placeholder: "Số điện thoại", keyboard: .phonePad)
        return tf
    }()

    private lazy var phoneRow: UIStackView = {
        let sv = UIStackView(arrangedSubviews: [phonePrefixButton, phoneTextField])
        sv.axis = .horizontal
        sv.spacing = 8.sw
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var emailTextField: UITextField = {
        makeTextField(placeholder: "Email", keyboard: .emailAddress)
    }()

    private lazy var passwordTextField: UITextField = {
        let tf = makeTextField(placeholder: "Mật khẩu", keyboard: .default)
        tf.isSecureTextEntry = true
        tf.textContentType = .password
        return tf
    }()

    private lazy var submitButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Tiếp tục", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        btn.setTitleColor(.white, for: .normal)
        btn.setTitleColor(UIColor.white.withAlphaComponent(0.6), for: .disabled)
        btn.backgroundColor = .systemIndigo
        btn.layer.cornerRadius = 14.sw
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var cooldownLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13.sf)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
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


    init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }


    override func viewDidLoad() {
        super.viewDidLoad()
    }


    override func setupUI() {
        view.backgroundColor = .systemBackground
        navigationController?.setNavigationBarHidden(true, animated: false)

        let contentStack = UIStackView(arrangedSubviews: [
            logoImageView,
            titleLabel,
            subtitleLabel,
            spacer(8.sh),
            modeSegment,
            spacer(4.sh),
            phoneRow,
            emailTextField,
            passwordTextField,
            spacer(4.sh),
            submitButton,
            cooldownLabel,
            errorLabel,
        ])
        contentStack.axis = .vertical
        contentStack.spacing = 12.sh
        contentStack.setCustomSpacing(4.sh, after: logoImageView)
        contentStack.setCustomSpacing(2.sh, after: titleLabel)
        contentStack.setCustomSpacing(20.sh, after: subtitleLabel)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .onDrag
        view.addSubview(scroll)
        scroll.addSubview(contentStack)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            contentStack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 40.sh),
            contentStack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 24.sw),
            contentStack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -24.sw),
            contentStack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -40.sh),
            contentStack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -48.sw),

            logoImageView.heightAnchor.constraint(equalToConstant: 72.sh),
            submitButton.heightAnchor.constraint(equalToConstant: 52.sh),
            phonePrefixButton.widthAnchor.constraint(equalToConstant: 90.sw),
            phoneTextField.heightAnchor.constraint(equalToConstant: 52.sh),
            emailTextField.heightAnchor.constraint(equalToConstant: 52.sh),
            passwordTextField.heightAnchor.constraint(equalToConstant: 52.sh),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }


    override func setupBindings() {
        modeSegment.publisher(for: .valueChanged)
            .map { [weak self] _ in LoginMode(rawValue: self?.modeSegment.selectedSegmentIndex ?? 0) ?? .sms }
            .sink { [weak self] mode in
                self?.viewModel.mode = mode
                self?.updateVisibleFields(mode: mode)
            }
            .store(in: &cancellables)

        phoneTextField.textPublisher
            .assign(to: &viewModel.$phone)

        emailTextField.textPublisher
            .assign(to: &viewModel.$email)

        passwordTextField.textPublisher
            .assign(to: &viewModel.$password)

        submitButton.tapPublisher
            .sink { [weak self] in self?.viewModel.submitTrigger.send() }
            .store(in: &cancellables)

        phonePrefixButton.tapPublisher
            .sink { [weak self] in self?.showCountryPicker() }
            .store(in: &cancellables)

        viewModel.$isSubmitEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.submitButton.isEnabled = enabled
                UIView.animate(withDuration: 0.2) {
                    self?.submitButton.alpha = enabled ? 1.0 : 0.5
                }
            }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                if loading { self?.loadingIndicator.startAnimating() } else { self?.loadingIndicator.stopAnimating() }
                self?.submitButton.isUserInteractionEnabled = !loading
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                self?.errorLabel.text = msg
                self?.errorLabel.isHidden = msg == nil
            }
            .store(in: &cancellables)

        viewModel.$otpCooldown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in
                if seconds > 0 {
                    self?.cooldownLabel.text = "Gửi lại sau \(seconds)s"
                    self?.cooldownLabel.isHidden = false
                } else {
                    self?.cooldownLabel.isHidden = true
                }
            }
            .store(in: &cancellables)

        viewModel.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in self?.updateSubmitTitle(mode: mode) }
            .store(in: &cancellables)

        updateVisibleFields(mode: .sms)
        updateSubmitTitle(mode: .sms)
    }


    private func updateVisibleFields(mode: LoginMode) {
        UIView.animate(withDuration: 0.2) {
            switch mode {
            case .sms:
                self.phoneRow.isHidden = false
                self.emailTextField.isHidden = true
                self.passwordTextField.isHidden = true
            case .emailOTP:
                self.phoneRow.isHidden = true
                self.emailTextField.isHidden = false
                self.passwordTextField.isHidden = true
            case .password:
                self.phoneRow.isHidden = true
                self.emailTextField.isHidden = false
                self.passwordTextField.isHidden = false
            }
        }
    }

    private func updateSubmitTitle(mode: LoginMode) {
        let title: String
        switch mode {
        case .sms, .emailOTP: title = "Gửi mã OTP"
        case .password:        title = "Đăng nhập"
        }
        submitButton.setTitle(title, for: .normal)
    }

    private func showCountryPicker() {
        let sheet = UIAlertController(title: "Chọn mã vùng", message: nil, preferredStyle: .actionSheet)
        let countries = [("+84", "🇻🇳 Việt Nam"), ("+1", "🇺🇸 USA"), ("+44", "🇬🇧 UK"),
                         ("+81", "🇯🇵 Japan"), ("+82", "🇰🇷 Korea"), ("+65", "🇸🇬 Singapore")]
        for (prefix, name) in countries {
            sheet.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                self?.viewModel.countryPrefix = prefix
                self?.phonePrefixButton.configuration?.title = "\(prefix)  ▾"
            })
        }
        sheet.addAction(UIAlertAction(title: "Huỷ", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = phonePrefixButton
        }
        present(sheet, animated: true)
    }

    private func makeTextField(placeholder: String, keyboard: UIKeyboardType) -> UITextField {
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.keyboardType = keyboard
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.borderStyle = .none
        tf.layer.cornerRadius = 12.sw
        tf.layer.borderWidth = 1.5
        tf.layer.borderColor = UIColor.separator.cgColor
        tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16.sw, height: 1))
        tf.leftViewMode = .always
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }

    private func spacer(_ height: CGFloat) -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }
}


#if DEBUG
import SwiftUI

struct LoginViewController_Previews: PreviewProvider {
    static var previews: some View {
        UIViewControllerPreview {
            UINavigationController(
                rootViewController: LoginViewController(
                    viewModel: LoginViewModel(context: .preview)
                )
            )
        }
        .ignoresSafeArea()
        .previewDisplayName("Login")
    }
}
#endif
