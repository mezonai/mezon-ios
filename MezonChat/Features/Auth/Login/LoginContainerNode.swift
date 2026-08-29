import AsyncDisplayKit
import UIKit

struct LoginInteraction {
    let onPhoneChanged: (String) -> Void
    let onEmailChanged: (String) -> Void
    let onPasswordChanged: (String) -> Void
    let onSubmitTapped: () -> Void
    let onCountryPrefixTapped: (UIView) -> Void
    let onShowPasswordToggled: () -> Void
    let onModeSelected: (LoginMode) -> Void
}

final class CheckboxComponent: Component {
    let title: String
    let isChecked: Bool
    let action: () -> Void

    init(title: String, isChecked: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isChecked = isChecked
        self.action = action
    }

    static func == (lhs: CheckboxComponent, rhs: CheckboxComponent) -> Bool {
        return lhs.title == rhs.title && lhs.isChecked == rhs.isChecked
    }

    final class View: UIControl {
        private let iconView = UIImageView()
        private let titleLabel = UILabel()
        private var action: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = .mezonTextMuted
            addSubview(iconView)

            titleLabel.font = .systemFont(ofSize: 14)
            titleLabel.textColor = .mezonTextStrong
            addSubview(titleLabel)

            addTarget(self, action: #selector(tapped), for: .touchUpInside)
        }

        required init?(coder: NSCoder) { fatalError() }

        func update(component: CheckboxComponent, availableSize: CGSize) -> CGSize {
            let attrs = AppTheme.light.attributes
            titleLabel.text = component.title
            titleLabel.textColor = attrs.textStrong
            titleLabel.sizeToFit()

            let iconName = component.isChecked ? "checkmark.square.fill" : "square"
            iconView.image = UIImage.mezonSystemImage(iconName)
            iconView.tintColor = component.isChecked ? UIColor(hex: 0x2e22ff) : attrs.textDisabled

            let iconSize: CGFloat = 24
            let spacing: CGFloat = 8

            iconView.frame = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
            titleLabel.frame = CGRect(
                x: iconSize + spacing, y: (iconSize - titleLabel.bounds.height) / 2,
                width: titleLabel.bounds.width, height: titleLabel.bounds.height)

            action = component.action
            let w = min(availableSize.width, iconSize + spacing + titleLabel.bounds.width)
            return CGSize(width: w, height: max(iconSize, titleLabel.bounds.height))
        }

        @objc private func tapped() { action?() }
    }

    func makeView() -> View { View(frame: .zero) }
    func update(
        view: View, availableSize: CGSize, state: EmptyComponentState,
        environment: Environment<Empty>, transition: ComponentTransition
    ) -> CGSize {
        view.update(component: self, availableSize: availableSize)
    }
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
            && lhs.state.isPasswordVisible == rhs.state.isPasswordVisible
    }

    static var body: Body {
        let title = Child(Text.self)
        let subtitle = Child(Text.self)
        let phoneField = Child(PhoneInputComponent.self)
        let emailField = Child(TextFieldComponent.self)
        let passwordField = Child(TextFieldComponent.self)
        let showPasswordCb = Child(CheckboxComponent.self)
        let submitButton = Child(SubmitButtonComponent.self)
        let cooldownText = Child(Text.self)
        let alternativeLinks = Child(VStack<Empty>.self)

        return { context in
            let component = context.component
            let st = component.state
            let interaction = component.interaction
            let sideInset: CGFloat = 0
            let contentWidth = context.availableSize.width - sideInset * 2
            var nextY: CGFloat = 10

            let titleStr: String
            switch st.mode {
            case .sms: titleStr = L(L10n.Login.enterPhone)
            case .emailOTP, .password: titleStr = L(L10n.Login.enterEmail)
            }

            let attrs = AppTheme.light.attributes
            let titleChild = title.update(
                component: Text(
                    text: titleStr, font: .systemFont(ofSize: 24, weight: .bold),
                    color: attrs.loginTitleColor),
                availableSize: CGSize(width: contentWidth, height: 100),
                transition: context.transition
            )
            context.add(
                titleChild.position(
                    CGPoint(x: contentWidth / 2, y: nextY + titleChild.size.height / 2)))
            nextY += titleChild.size.height + 10

            let subtitleChild = subtitle.update(
                component: Text(
                    text: L(L10n.Login.chooseAnotherOption), font: .systemFont(ofSize: 14),
                    color: attrs.loginSubtitleColor),
                availableSize: CGSize(width: contentWidth, height: 100),
                transition: context.transition
            )
            context.add(
                subtitleChild.position(
                    CGPoint(x: contentWidth / 2, y: nextY + subtitleChild.size.height / 2)))
            nextY += subtitleChild.size.height + 40

            switch st.mode {
            case .sms:
                let phoneChild = phoneField.update(
                    component: PhoneInputComponent(
                        prefix: st.countryPrefix, phone: st.phone,
                        onPrefixTapped: interaction.onCountryPrefixTapped,
                        onPhoneChanged: interaction.onPhoneChanged),
                    availableSize: CGSize(width: contentWidth, height: 100),
                    transition: context.transition
                )
                context.add(
                    phoneChild.position(
                        CGPoint(x: contentWidth / 2, y: nextY + phoneChild.size.height / 2)))
                nextY += phoneChild.size.height + 10

            case .emailOTP:
                let emailChild = emailField.update(
                    component: TextFieldComponent(
                        placeholder: L(L10n.Login.emailAddress), text: st.email,
                        textColor: attrs.loginInputTextColor,
                        placeholderColor: attrs.loginPlaceholder,
                        backgroundColor: attrs.loginInputBg,
                        borderColor: attrs.loginInputBorder,
                        keyboardType: .emailAddress, leftIcon: "envelope",
                        onTextChanged: interaction.onEmailChanged),
                    availableSize: CGSize(width: contentWidth, height: 100),
                    transition: context.transition
                )
                context.add(
                    emailChild.position(
                        CGPoint(x: contentWidth / 2, y: nextY + emailChild.size.height / 2)))
                nextY += emailChild.size.height + 10

            case .password:
                let emailChild = emailField.update(
                    component: TextFieldComponent(
                        placeholder: L(L10n.Login.emailAddress), text: st.email,
                        textColor: attrs.loginInputTextColor,
                        placeholderColor: attrs.loginPlaceholder,
                        backgroundColor: attrs.loginInputBg,
                        borderColor: attrs.loginInputBorder,
                        keyboardType: .emailAddress, leftIcon: "envelope",
                        onTextChanged: interaction.onEmailChanged),
                    availableSize: CGSize(width: contentWidth, height: 100),
                    transition: context.transition
                )
                context.add(
                    emailChild.position(
                        CGPoint(x: contentWidth / 2, y: nextY + emailChild.size.height / 2)))
                nextY += emailChild.size.height + 24

                let pwChild = passwordField.update(
                    component: TextFieldComponent(
                        placeholder: L(L10n.Login.password), text: st.password,
                        textColor: attrs.loginInputTextColor,
                        placeholderColor: attrs.loginPlaceholder,
                        backgroundColor: attrs.loginInputBg,
                        borderColor: attrs.loginInputBorder,
                        isSecureTextEntry: !st.isPasswordVisible, leftIcon: "lock.fill",
                        onTextChanged: interaction.onPasswordChanged),
                    availableSize: CGSize(width: contentWidth, height: 100),
                    transition: context.transition
                )
                context.add(
                    pwChild.position(
                        CGPoint(x: contentWidth / 2, y: nextY + pwChild.size.height / 2)))
                nextY += pwChild.size.height + 12

                let cbChild = showPasswordCb.update(
                    component: CheckboxComponent(
                        title: L(L10n.Login.showPassword),
                        isChecked: st.isPasswordVisible,
                        action: interaction.onShowPasswordToggled),
                    availableSize: CGSize(width: contentWidth, height: 100),
                    transition: context.transition
                )
                context.add(
                    cbChild.position(
                        CGPoint(
                            x: contentWidth / 2 - (contentWidth - cbChild.size.width) / 2,
                            y: nextY + cbChild.size.height / 2)))
                nextY += cbChild.size.height
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
                    component: Text(
                        text: String(format: L(L10n.Login.resendInSeconds), st.otpCooldown),
                        font: .systemFont(ofSize: 13), color: attrs.loginAlternativeText),
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

    let attrs = AppTheme.light.attributes
    var items: [AnyComponentWithIdentity<Empty>] = []
    items.append(
        AnyComponentWithIdentity(
            id: "hint",
            component: AnyComponent(
                Text(text: hint, font: .systemFont(ofSize: 14), color: attrs.loginAlternativeText)))
    )
    for (title, targetMode) in links {
        let btn = Button(
            content: AnyComponent(
                Text(text: title, font: .systemFont(ofSize: 14), color: attrs.loginButtonBg)),
            action: { interaction.onModeSelected(targetMode) })
        items.append(
            AnyComponentWithIdentity(
                id: "link_\(targetMode.rawValue)", component: AnyComponent(btn)))
    }
    return items
}

final class PhoneInputComponent: Component {
    let prefix: String
    let phone: String
    let onPrefixTapped: (UIView) -> Void
    let onPhoneChanged: (String) -> Void

    init(prefix: String, phone: String, onPrefixTapped: @escaping (UIView) -> Void, onPhoneChanged: @escaping (String) -> Void) {
        self.prefix = prefix
        self.phone = phone
        self.onPrefixTapped = onPrefixTapped
        self.onPhoneChanged = onPhoneChanged
    }

    static func == (lhs: PhoneInputComponent, rhs: PhoneInputComponent) -> Bool {
        return lhs.prefix == rhs.prefix && lhs.phone == rhs.phone
    }

    final class View: UIView {
        private static let prefixTextColor = UIColor(hex: 0x1c1c1e)

        private let container = UIView()
        private let prefixButton = UIButton(type: .system)
        private let separator = UIView()
        private let textField = UITextField()
        private var onPrefixTapped: ((UIView) -> Void)?
        private var onPhoneChanged: ((String) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            container.layer.cornerRadius = 12
            container.layer.borderWidth = 1
            addSubview(container)

            if #available(iOS 15.0, *) {
                var cfg = UIButton.Configuration.plain()
                cfg.baseForegroundColor = Self.prefixTextColor
                cfg.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 4)
                prefixButton.configuration = cfg
            } else {
                prefixButton.setTitleColor(Self.prefixTextColor, for: .normal)
                prefixButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 4)
            }
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

            let attrs = AppTheme.light.attributes
            container.backgroundColor = attrs.loginInputBg
            container.layer.borderColor = attrs.loginInputBorder.cgColor
            textField.textColor = attrs.loginInputTextColor
            textField.attributedPlaceholder = NSAttributedString(
                string: L(L10n.Login.phone), attributes: [.foregroundColor: attrs.loginPlaceholder])

            let prefixTitle =
                component.prefix == "+84"
                ? "🇻🇳 +84"
                : (component.prefix == "+81"
                    ? "🇯🇵 +81" : (component.prefix == "+1" ? "🇺🇸 +1" : component.prefix))
            if #available(iOS 15.0, *) {
                prefixButton.configuration?.title = "\(prefixTitle)   "
                prefixButton.configuration?.baseForegroundColor = Self.prefixTextColor
            } else {
                prefixButton.setTitle("\(prefixTitle)   ", for: .normal)
                prefixButton.setTitleColor(Self.prefixTextColor, for: .normal)
            }
            prefixButton.frame = CGRect(x: 0, y: 0, width: 100, height: size.height)
            separator.frame = CGRect(x: 84, y: 8, width: 1, height: size.height - 16)
            if textField.text != component.phone { textField.text = component.phone }
            textField.frame = CGRect(x: 102, y: 0, width: size.width - 108, height: size.height)

            onPrefixTapped = component.onPrefixTapped
            onPhoneChanged = component.onPhoneChanged
            return size
        }

        @objc private func prefixTap() { onPrefixTapped?(prefixButton) }
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
        private let button = UIButton(type: .custom)
        private let spinner = UIActivityIndicatorView.mezonMedium()
        private var action: (() -> Void)?

        private let gradientLayer: CAGradientLayer = {
            let layer = CAGradientLayer()
            layer.colors = [UIColor(hex: 0x501794).cgColor, UIColor(hex: 0x3E70A1).cgColor]
            layer.startPoint = CGPoint(x: 0, y: 0)
            layer.endPoint = CGPoint(x: 1, y: 0)
            layer.cornerRadius = 8
            return layer
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)

            button.layer.insertSublayer(gradientLayer, at: 0)

            button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            button.setTitleColor(.white, for: .normal)
            button.setTitleColor(UIColor.white.withAlphaComponent(0.8), for: .disabled)
            button.layer.cornerRadius = 8
            button.layer.masksToBounds = true
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
            gradientLayer.frame = button.bounds

            button.setTitle(component.title, for: .normal)
            button.isEnabled = component.isEnabled

            if component.isEnabled {
                button.backgroundColor = .clear
                gradientLayer.isHidden = false
            } else {
                button.backgroundColor = AppTheme.light.attributes.loginButtonBgDisabled
                gradientLayer.isHidden = true
            }

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
        let attrs = AppTheme.light.attributes
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
