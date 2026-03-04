import UIKit
import Combine

final class LoginViewController: BaseViewController {

    private let viewModel: LoginViewModel

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
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var subtitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14.sf)
        l.textColor = .loginSubtitleColor
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var phonePrefixButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = .mezonTextStrong
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8.sw, bottom: 0, trailing: 4.sw)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = .systemFont(ofSize: 14.sf)
            return a
        }
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var phoneTextField: UITextField = {
        makeTextField(placeholderKey: L10n.Login.phone, keyboard: .phonePad)
    }()

    private lazy var phoneStack: UIStackView = {
        phonePrefixButton.setContentHuggingPriority(.required, for: .horizontal)
        phoneTextField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let sv = UIStackView(arrangedSubviews: [phonePrefixButton, separatorView(), phoneTextField])
        sv.axis = .horizontal
        sv.spacing = 0
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var phoneInputContainer: UIView = {
        wrapInput(phoneStack)
    }()

    private lazy var emailTextField: UITextField = {
        let tf = makeTextField(placeholderKey: L10n.Login.emailAddress, keyboard: .emailAddress)
        tf.leftView = iconView(systemName: "envelope")
        tf.leftViewMode = .always
        return tf
    }()

    private lazy var emailInputContainer: UIView = {
        wrapInput(emailTextField)
    }()

    private lazy var passwordTextField: UITextField = {
        let tf = makeTextField(placeholderKey: L10n.Login.password, keyboard: .default)
        tf.isSecureTextEntry = true
        tf.textContentType = .password
        tf.leftView = iconView(systemName: "lock.fill")
        tf.leftViewMode = .always
        return tf
    }()

    private lazy var passwordInputContainer: UIView = {
        wrapInput(passwordTextField)
    }()

    private lazy var showPasswordButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = .loginTitleColor
        config.image = UIImage(systemName: "square")
        config.imagePlacement = .leading
        config.imagePadding = 8.sw
        config.contentInsets = .zero
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = .systemFont(ofSize: 14.sf)
            return a
        }
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var submitButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        btn.setTitleColor(.white, for: .normal)
        btn.setTitleColor(UIColor.white.withAlphaComponent(0.6), for: .disabled)
        btn.layer.cornerRadius = 12.sw
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var alternativeHintLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14.sf)
        l.textColor = .loginAlternativeText
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var alternativeStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 6.sh
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var cooldownLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13.sf)
        l.textColor = .loginAlternativeText
        l.textAlignment = .center
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.color = .white
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private var alternativeLinkButtons: [UIButton] = []
    private var inputSectionStack: UIStackView!


    init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }


    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: LanguageManager.didChangeNotification,
            object: nil
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }


    override func setupUI() {
        view.layer.insertSublayer(gradientLayer, at: 0)
        navigationController?.setNavigationBarHidden(true, animated: false)

        inputSectionStack = UIStackView()
        inputSectionStack.axis = .vertical
        inputSectionStack.spacing = 0
        inputSectionStack.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = UIStackView(arrangedSubviews: [
            titleLabel,
            subtitleLabel,
            spacer(40.sh),
            inputSectionStack,
            spacer(24.sh),
            submitButton,
            spacer(30.sh),
            alternativeHintLabel,
            alternativeStack,
            spacer(12.sh),
            cooldownLabel,
        ])
        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.setCustomSpacing(10.sh, after: titleLabel)
        contentStack.setCustomSpacing(40.sh, after: subtitleLabel)
        contentStack.setCustomSpacing(6.sh, after: alternativeHintLabel)
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

            contentStack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 100.sh),
            contentStack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16.sw),
            contentStack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16.sw),
            contentStack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -40.sh),
            contentStack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32.sw),

            submitButton.heightAnchor.constraint(equalToConstant: 50.sh),
            phonePrefixButton.widthAnchor.constraint(equalToConstant: 64.sw),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        applyTheme()
        refreshLocalizedStrings()
        updateVisibleFields(mode: viewModel.mode)
        updateAlternativeLinks(mode: viewModel.mode)
    }


    override func setupBindings() {
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

        showPasswordButton.tapPublisher
            .sink { [weak self] in
                guard let self else { return }
                let next = !self.passwordTextField.isSecureTextEntry
                self.passwordTextField.isSecureTextEntry = next
                self.showPasswordButton.configuration?.image = UIImage(systemName: next ? "square" : "checkmark.square.fill")
            }
            .store(in: &cancellables)

        viewModel.$isSubmitEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.submitButton.isEnabled = enabled
                self?.submitButton.backgroundColor = enabled ? .loginButtonBg : .loginButtonBgDisabled
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
            .sink { msg in
                guard let msg else { return }
                Toast.error(msg)
            }
            .store(in: &cancellables)

        viewModel.$otpCooldown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in
                guard let self else { return }
                if seconds > 0 {
                    self.cooldownLabel.text = String(format: L(L10n.Login.resendInSeconds), seconds)
                    self.cooldownLabel.isHidden = false
                } else {
                    self.cooldownLabel.isHidden = true
                }
            }
            .store(in: &cancellables)

        viewModel.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.updateVisibleFields(mode: mode)
                self?.updateAlternativeLinks(mode: mode)
                self?.updateSubmitTitle(mode: mode)
                self?.refreshLocalizedStrings()
            }
            .store(in: &cancellables)

        viewModel.$countryPrefix
            .receive(on: DispatchQueue.main)
            .sink { [weak self] prefix in
                self?.phonePrefixButton.configuration?.title = "\(prefix)  ▾"
            }
            .store(in: &cancellables)

        updateSubmitTitle(mode: viewModel.mode)
    }


    override func applyTheme() {
        let attrs = ThemeManager.shared.attributes
        gradientLayer.colors = attrs.loginGradientColors.map { $0.cgColor }

        titleLabel.textColor = attrs.loginTitleColor
        subtitleLabel.textColor = attrs.loginSubtitleColor
        alternativeHintLabel.textColor = attrs.loginAlternativeText
        cooldownLabel.textColor = attrs.loginAlternativeText

        phoneInputContainer.backgroundColor = attrs.loginInputBg
        phoneInputContainer.layer.borderColor = attrs.loginInputBorder.cgColor
        emailInputContainer.backgroundColor = attrs.loginInputBg
        emailInputContainer.layer.borderColor = attrs.loginInputBorder.cgColor
        passwordInputContainer.backgroundColor = attrs.loginInputBg
        passwordInputContainer.layer.borderColor = attrs.loginInputBorder.cgColor

        phoneTextField.textColor = attrs.loginInputTextColor
        phoneTextField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.Login.phone),
            attributes: [.foregroundColor: attrs.loginPlaceholder]
        )
        emailTextField.textColor = attrs.loginInputTextColor
        emailTextField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.Login.emailAddress),
            attributes: [.foregroundColor: attrs.loginPlaceholder]
        )
        passwordTextField.textColor = attrs.loginInputTextColor
        passwordTextField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.Login.password),
            attributes: [.foregroundColor: attrs.loginPlaceholder]
        )

        phonePrefixButton.configuration?.baseForegroundColor = attrs.loginTitleColor
        showPasswordButton.configuration?.baseForegroundColor = attrs.loginTitleColor

        submitButton.backgroundColor = viewModel.isSubmitEnabled ? attrs.loginButtonBg : attrs.loginButtonBgDisabled

        alternativeLinkButtons.forEach { btn in
            btn.configuration?.baseForegroundColor = attrs.textLink
        }
    }


    @objc private func handleLanguageChange() {
        refreshLocalizedStrings()
    }


    private func refreshLocalizedStrings() {
        let mode = viewModel.mode
        switch mode {
        case .sms:
            titleLabel.text = L(L10n.Login.enterPhone)
        case .emailOTP, .password:
            titleLabel.text = L(L10n.Login.enterEmail)
        }
        subtitleLabel.text = L(L10n.Login.chooseAnotherOption)
        showPasswordButton.configuration?.title = L(L10n.Login.showPassword)
        updateAlternativeLinks(mode: mode)
        updateSubmitTitle(mode: mode)

        phoneTextField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.Login.phone),
            attributes: [.foregroundColor: ThemeManager.shared.attributes.loginPlaceholder]
        )
        emailTextField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.Login.emailAddress),
            attributes: [.foregroundColor: ThemeManager.shared.attributes.loginPlaceholder]
        )
        passwordTextField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.Login.password),
            attributes: [.foregroundColor: ThemeManager.shared.attributes.loginPlaceholder]
        )
    }


    private func updateVisibleFields(mode: LoginMode) {
        inputSectionStack?.arrangedSubviews.forEach { $0.removeFromSuperview() }

        switch mode {
        case .sms:
            inputSectionStack?.addArrangedSubview(phoneInputContainer)
        case .emailOTP:
            inputSectionStack?.addArrangedSubview(emailInputContainer)
        case .password:
            inputSectionStack?.addArrangedSubview(emailInputContainer)
            inputSectionStack?.setCustomSpacing(12.sh, after: emailInputContainer)
            inputSectionStack?.addArrangedSubview(passwordInputContainer)
            inputSectionStack?.setCustomSpacing(12.sh, after: passwordInputContainer)
            inputSectionStack?.addArrangedSubview(showPasswordButton)
        }

        view.layoutIfNeeded()
    }


    private func updateSubmitTitle(mode: LoginMode) {
        switch mode {
        case .sms, .emailOTP:
            submitButton.setTitle(L(L10n.Login.send), for: .normal)
        case .password:
            submitButton.setTitle(L(L10n.Login.logIn), for: .normal)
        }
    }


    private func updateAlternativeLinks(mode: LoginMode) {
        let hint: String
        let links: [(String, LoginMode)]

        switch mode {
        case .sms:
            hint = L(L10n.Login.cannotAccessYourPhone)
            links = [(L(L10n.Login.loginWithEmailOTP), .emailOTP), (L(L10n.Login.loginWithPassword), .password)]
        case .emailOTP:
            hint = L(L10n.Login.cannotAccessYourEmail)
            links = [(L(L10n.Login.loginWithSMS), .sms), (L(L10n.Login.loginWithPassword), .password)]
        case .password:
            hint = L(L10n.Login.passwordNotSet)
            links = [(L(L10n.Login.loginWithEmailOTP), .emailOTP), (L(L10n.Login.loginWithSMS), .sms)]
        }

        alternativeHintLabel.text = hint
        alternativeHintLabel.isHidden = hint.isEmpty

        alternativeStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        alternativeLinkButtons.removeAll()

        for (title, targetMode) in links {
            let btn = makeLinkButton(title: title) { [weak self] in
                self?.viewModel.mode = targetMode
            }
            alternativeLinkButtons.append(btn)
            alternativeStack.addArrangedSubview(btn)
        }
    }


    private func makeLinkButton(title: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = .mezonLink
        config.contentInsets = .zero
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = .systemFont(ofSize: 14.sf)
            return a
        }
        let btn = UIButton(configuration: config)
        btn.tapPublisher
            .sink { action() }
            .store(in: &cancellables)
        return btn
    }


    private func showCountryPicker() {
        let sheet = UIAlertController(title: L(L10n.Login.selectCountry), message: nil, preferredStyle: .actionSheet)
        let countries = [("+84", "🇻🇳 Việt Nam"), ("+81", "🇯🇵 Japan"), ("+1", "🇺🇸 USA")]
        for (prefix, name) in countries {
            sheet.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                self?.viewModel.countryPrefix = prefix
            })
        }
        sheet.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = phonePrefixButton
        }
        present(sheet, animated: true)
    }


    private func separatorView() -> UIView {
        let v = UIView()
        v.backgroundColor = .loginAlternativeText.withAlphaComponent(0.4)
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }


    private func iconView(systemName: String) -> UIView {
        let iv = UIImageView(image: UIImage(systemName: systemName))
        iv.tintColor = .loginPlaceholder
        iv.contentMode = .scaleAspectFit
        iv.frame = CGRect(x: 0, y: 0, width: 44.sw, height: 24.sh)
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 44.sw, height: 24.sh))
        container.addSubview(iv)
        iv.center = CGPoint(x: 22.sw, y: 12.sh)
        return container
    }


    private func makeTextField(placeholderKey: String, keyboard: UIKeyboardType) -> UITextField {
        let tf = UITextField()
        tf.placeholder = L(placeholderKey)
        tf.keyboardType = keyboard
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.borderStyle = .none
        tf.font = .systemFont(ofSize: 16.sf)
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }


    private func wrapInput(_ content: UIView) -> UIView {
        let container = UIView()
        container.layer.cornerRadius = 12.sw
        container.layer.borderWidth = 1
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16.sw),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16.sw),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 50.sh),
        ])
        return container
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
