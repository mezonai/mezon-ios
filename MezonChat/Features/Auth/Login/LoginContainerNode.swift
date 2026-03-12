import UIKit
import AsyncDisplayKit

struct LoginInteraction {
    let onPhoneChanged: (String) -> Void
    let onEmailChanged: (String) -> Void
    let onPasswordChanged: (String) -> Void
    let onSubmitTapped: () -> Void
    let onCountryPrefixTapped: () -> Void
    let onShowPasswordToggled: () -> Void
    let onModeSelected: (LoginMode) -> Void
}

final class LoginFormComponent: CombinedComponent {
    let state: LoginState
    let interaction: LoginInteraction

    init(state: LoginState, interaction: LoginInteraction) {
        self.state = state
        self.interaction = interaction
    }

    static func == (lhs: LoginFormComponent, rhs: LoginFormComponent) -> Bool {
        return lhs.state.mode == rhs.state.mode
            && lhs.state.email == rhs.state.email
            && lhs.state.phone == rhs.state.phone
            && lhs.state.countryPrefix == rhs.state.countryPrefix
            && lhs.state.password == rhs.state.password
            && lhs.state.isSubmitEnabled == rhs.state.isSubmitEnabled
            && lhs.state.otpCooldown == rhs.state.otpCooldown
            && lhs.state.isLoading == rhs.state.isLoading
            && lhs.state.errorMessage == rhs.state.errorMessage
    }

    static var body: Body {
        let title = Child(Text.self)
        let subtitle = Child(Text.self)
        let phoneField = Child(PhoneInputComponent.self)
        let emailField = Child(TextFieldComponent.self)
        let passwordField = Child(TextFieldComponent.self)
        let submitButton = Child(SubmitButtonComponent.self)
        let cooldownText = Child(Text.self)
        let alternativeLinks = Child(VStack<Empty>.self)

        return { context in
            let component = context.component
            let st = component.state
            let interaction = component.interaction
            let sideInset: CGFloat = 0
            let contentWidth = context.availableSize.width - sideInset * 2
            var nextY: CGFloat = 0

            let titleStr: String
            switch st.mode {
            case .sms: titleStr = L(L10n.Login.enterPhone)
            case .emailOTP, .password: titleStr = L(L10n.Login.enterEmail)
            }

            let titleChild = title.update(
                component: Text(text: titleStr, font: .systemFont(ofSize: 24, weight: .bold), color: .loginTitleColor),
                availableSize: CGSize(width: contentWidth, height: 100),
                transition: context.transition
            )
            context.add(titleChild.position(CGPoint(x: contentWidth / 2, y: nextY + titleChild.size.height / 2)))
            nextY += titleChild.size.height + 10

            let subtitleChild = subtitle.update(
                component: Text(text: L(L10n.Login.chooseAnotherOption), font: .systemFont(ofSize: 14), color: .loginSubtitleColor),
                availableSize: CGSize(width: contentWidth, height: 100),
                transition: context.transition
            )
            context.add(subtitleChild.position(CGPoint(x: contentWidth / 2, y: nextY + subtitleChild.size.height / 2)))
            nextY += subtitleChild.size.height + 40

            switch st.mode {
            case .sms:
                let phoneChild = phoneField.update(
                    component: PhoneInputComponent(prefix: st.countryPrefix, phone: st.phone, onPrefixTapped: interaction.onCountryPrefixTapped, onPhoneChanged: interaction.onPhoneChanged),
                    availableSize: CGSize(width: contentWidth, height: 100),
                    transition: context.transition
                )
                context.add(phoneChild.position(CGPoint(x: contentWidth / 2, y: nextY + phoneChild.size.height / 2)))
                nextY += phoneChild.size.height

            case .emailOTP:
                let emailChild = emailField.update(
                    component: TextFieldComponent(placeholder: L(L10n.Login.emailAddress), text: st.email, keyboardType: .emailAddress, leftIcon: "envelope", onTextChanged: interaction.onEmailChanged),
                    availableSize: CGSize(width: contentWidth, height: 100),
                    transition: context.transition
                )
                context.add(emailChild.position(CGPoint(x: contentWidth / 2, y: nextY + emailChild.size.height / 2)))
                nextY += emailChild.size.height

            case .password:
                let emailChild = emailField.update(
                    component: TextFieldComponent(placeholder: L(L10n.Login.emailAddress), text: st.email, keyboardType: .emailAddress, leftIcon: "envelope", onTextChanged: interaction.onEmailChanged),
                    availableSize: CGSize(width: contentWidth, height: 100),
                    transition: context.transition
                )
                context.add(emailChild.position(CGPoint(x: contentWidth / 2, y: nextY + emailChild.size.height / 2)))
                nextY += emailChild.size.height + 12

                let pwChild = passwordField.update(
                    component: TextFieldComponent(placeholder: L(L10n.Login.password), text: st.password, isSecureTextEntry: true, leftIcon: "lock.fill", onTextChanged: interaction.onPasswordChanged),
                    availableSize: CGSize(width: contentWidth, height: 100),
                    transition: context.transition
                )
                context.add(pwChild.position(CGPoint(x: contentWidth / 2, y: nextY + pwChild.size.height / 2)))
                nextY += pwChild.size.height
            }

            nextY += 24

            let submitTitle: String
            switch st.mode {
            case .sms, .emailOTP: submitTitle = L(L10n.Login.send)
            case .password: submitTitle = L(L10n.Login.logIn)
            }

            let submitChild = submitButton.update(
                component: SubmitButtonComponent(title: submitTitle, isEnabled: st.isSubmitEnabled, isLoading: st.isLoading, action: interaction.onSubmitTapped),
                availableSize: CGSize(width: contentWidth, height: 100),
                transition: context.transition
            )
            context.add(submitChild.position(CGPoint(x: contentWidth / 2, y: nextY + submitChild.size.height / 2)))
            nextY += submitChild.size.height + 30

            let altItems = buildAlternativeItems(mode: st.mode, interaction: interaction)
            if !altItems.isEmpty {
                let altChild = alternativeLinks.update(
                    component: VStack<Empty>(altItems, alignment: .center, spacing: 6),
                    availableSize: CGSize(width: contentWidth, height: 1000),
                    transition: context.transition
                )
                context.add(altChild.position(CGPoint(x: contentWidth / 2, y: nextY + altChild.size.height / 2)))
                nextY += altChild.size.height + 12
            }

            if st.otpCooldown > 0 {
                let cdChild = cooldownText.update(
                    component: Text(text: String(format: L(L10n.Login.resendInSeconds), st.otpCooldown), font: .systemFont(ofSize: 13), color: .loginAlternativeText),
                    availableSize: CGSize(width: contentWidth, height: 100),
                    transition: context.transition
                )
                context.add(cdChild.position(CGPoint(x: contentWidth / 2, y: nextY + cdChild.size.height / 2)))
                nextY += cdChild.size.height + 12
            }

            return CGSize(width: context.availableSize.width, height: nextY)
        }
    }
}

private func buildAlternativeItems(mode: LoginMode, interaction: LoginInteraction) -> [AnyComponentWithIdentity<Empty>] {
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

    var items: [AnyComponentWithIdentity<Empty>] = []
    items.append(AnyComponentWithIdentity(id: "hint", component: AnyComponent(Text(text: hint, font: .systemFont(ofSize: 14), color: .loginAlternativeText))))
    for (title, targetMode) in links {
        let btn = Button(content: AnyComponent(Text(text: title, font: .systemFont(ofSize: 14), color: .mezonLink)), action: { interaction.onModeSelected(targetMode) })
        items.append(AnyComponentWithIdentity(id: "link_\(targetMode.rawValue)", component: AnyComponent(btn)))
    }
    return items
}

final class PhoneInputComponent: Component {
    let prefix: String
    let phone: String
    let onPrefixTapped: () -> Void
    let onPhoneChanged: (String) -> Void

    init(prefix: String, phone: String, onPrefixTapped: @escaping () -> Void, onPhoneChanged: @escaping (String) -> Void) {
        self.prefix = prefix
        self.phone = phone
        self.onPrefixTapped = onPrefixTapped
        self.onPhoneChanged = onPhoneChanged
    }

    static func == (lhs: PhoneInputComponent, rhs: PhoneInputComponent) -> Bool {
        return lhs.prefix == rhs.prefix && lhs.phone == rhs.phone
    }

    final class View: UIView {
        private let container = UIView()
        private let prefixButton = UIButton(type: .system)
        private let separator = UIView()
        private let textField = UITextField()
        private var onPrefixTapped: (() -> Void)?
        private var onPhoneChanged: ((String) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            container.layer.cornerRadius = 12
            container.layer.borderWidth = 1
            addSubview(container)

            var cfg = UIButton.Configuration.plain()
            cfg.baseForegroundColor = .mezonTextStrong
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 4)
            prefixButton.configuration = cfg
            prefixButton.addTarget(self, action: #selector(prefixTap), for: .touchUpInside)
            container.addSubview(prefixButton)

            separator.backgroundColor = UIColor.loginAlternativeText.withAlphaComponent(0.4)
            container.addSubview(separator)

            textField.keyboardType = .phonePad
            textField.autocapitalizationType = .none
            textField.borderStyle = .none
            textField.font = .systemFont(ofSize: 16)
            textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
            container.addSubview(textField)
        }

        required init?(coder: NSCoder) { fatalError() }

        func update(component: PhoneInputComponent, availableSize: CGSize) -> CGSize {
            let size = CGSize(width: availableSize.width, height: 50)
            container.frame = CGRect(origin: .zero, size: size)

            let attrs = ThemeManager.shared.attributes
            container.backgroundColor = attrs.loginInputBg
            container.layer.borderColor = attrs.loginInputBorder.cgColor
            textField.textColor = attrs.loginInputTextColor
            textField.attributedPlaceholder = NSAttributedString(string: L(L10n.Login.phone), attributes: [.foregroundColor: attrs.loginPlaceholder])

            prefixButton.configuration?.title = "\(component.prefix)  ▾"
            prefixButton.frame = CGRect(x: 0, y: 0, width: 64, height: size.height)
            separator.frame = CGRect(x: 64, y: 8, width: 1, height: size.height - 16)

            if textField.text != component.phone { textField.text = component.phone }
            textField.frame = CGRect(x: 72, y: 0, width: size.width - 88, height: size.height)

            onPrefixTapped = component.onPrefixTapped
            onPhoneChanged = component.onPhoneChanged
            return size
        }

        @objc private func prefixTap() { onPrefixTapped?() }
        @objc private func textChanged() { onPhoneChanged?(textField.text ?? "") }
    }

    func makeView() -> View { View(frame: .zero) }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        view.update(component: self, availableSize: availableSize)
    }
}

final class SubmitButtonComponent: Component {
    let title: String
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void

    init(title: String, isEnabled: Bool, isLoading: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
    }

    static func == (lhs: SubmitButtonComponent, rhs: SubmitButtonComponent) -> Bool {
        return lhs.title == rhs.title && lhs.isEnabled == rhs.isEnabled && lhs.isLoading == rhs.isLoading
    }

    final class View: UIView {
        private let button = UIButton(type: .system)
        private let spinner = UIActivityIndicatorView(style: .medium)
        private var action: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            button.setTitleColor(.white, for: .normal)
            button.setTitleColor(UIColor.white.withAlphaComponent(0.6), for: .disabled)
            button.layer.cornerRadius = 12
            button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
            addSubview(button)
            spinner.hidesWhenStopped = true
            spinner.color = .white
            addSubview(spinner)
        }

        required init?(coder: NSCoder) { fatalError() }

        func update(component: SubmitButtonComponent, availableSize: CGSize) -> CGSize {
            let size = CGSize(width: availableSize.width, height: 50)
            button.frame = CGRect(origin: .zero, size: size)
            button.setTitle(component.title, for: .normal)
            button.isEnabled = component.isEnabled
            button.backgroundColor = component.isEnabled ? .loginButtonBg : .loginButtonBgDisabled
            button.isUserInteractionEnabled = !component.isLoading

            if component.isLoading { spinner.startAnimating() } else { spinner.stopAnimating() }
            spinner.center = CGPoint(x: size.width / 2, y: size.height / 2)

            action = component.action
            return size
        }

        @objc private func tapped() { action?() }
    }

    func makeView() -> View { View(frame: .zero) }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        view.update(component: self, availableSize: availableSize)
    }
}

final class LoginContainerNode: ASDisplayNode {
    let phonePrefixButton = UIButton(type: .system)
    private let componentHostView = ComponentHostView<Empty>()
    private let gradientLayer = CAGradientLayer()
    private var scrollView: UIScrollView!

    private var state: LoginState = .empty
    private let interaction: LoginInteraction
    private let disposables = DisposableSet()

    init(signal: Signal<LoginState, NoError>, interaction: LoginInteraction) {
        self.interaction = interaction
        super.init()

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                let prev = self.state
                self.state = newState

                if let msg = newState.errorMessage, msg != prev.errorMessage {
                    Toast.error(msg)
                }

                self.updateComponentContent()
            })
        )
    }

    deinit { disposables.dispose() }

    override func didLoad() {
        super.didLoad()

        gradientLayer.locations = [0, 0.5, 1]
        view.layer.insertSublayer(gradientLayer, at: 0)

        scrollView = UIScrollView()
        scrollView.keyboardDismissMode = .onDrag
        view.addSubview(scrollView)
        scrollView.addSubview(componentHostView)

        applyTheme()
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        scrollView.frame = CGRect(origin: .zero, size: layout.size)
        updateComponentContent()
    }

    func refreshLocalizedStrings() {
        updateComponentContent()
    }

    private func applyTheme() {
        let attrs = ThemeManager.shared.attributes
        gradientLayer.colors = attrs.loginGradientColors.map { $0.cgColor }
    }

    private func updateComponentContent() {
        guard scrollView != nil, scrollView.bounds.width > 0 else { return }

        let component = LoginFormComponent(state: state, interaction: interaction)
        let contentWidth = scrollView.bounds.width - 32
        let size = componentHostView.update(
            transition: .immediate,
            component: AnyComponent(component),
            environment: {},
            containerSize: CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
        )
        componentHostView.frame = CGRect(x: 16, y: 100, width: contentWidth, height: size.height)
        scrollView.contentSize = CGSize(width: scrollView.bounds.width, height: size.height + 140)
    }
}
