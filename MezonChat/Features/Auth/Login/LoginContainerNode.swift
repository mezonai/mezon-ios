import AsyncDisplayKit
import UIKit

enum LoginPalette {
    static let background = UIColor(hex: 0xDDD9E2)
    static let buttonStart = UIColor(hex: 0x383FB5)
    static let buttonEnd = UIColor(hex: 0x383FB5)
    static let buttonText = UIColor.white
    static let disabledButton = UIColor(hex: 0xA0A7ED)
    static let disabledButtonText = UIColor.white.withAlphaComponent(0.85)
    static let welcomeButton = UIColor(hex: 0x5058D2)
    static let cooldownText = UIColor(hex: 0xFFF7D6)
}

final class AuthBackgroundLayer: CAGradientLayer {
    private let curveMask = CAShapeLayer()
    private let accentLayer = CAShapeLayer()

    override init() {
        super.init()
        locations = [0, 0.22, 0.65, 1]
        colors = [
            UIColor(hex: 0x7857CC).cgColor,
            UIColor(hex: 0x7462DE).cgColor,
            UIColor(hex: 0x5560E8).cgColor,
            UIColor(hex: 0x4752E5).cgColor
        ]
        mask = curveMask
        accentLayer.fillColor = UIColor.white.withAlphaComponent(0.06).cgColor
        accentLayer.strokeColor = UIColor.white.withAlphaComponent(0.12).cgColor
        accentLayer.lineWidth = 1
        addSublayer(accentLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    @discardableResult
    func update(width: CGFloat, viewportHeight: CGFloat, contentBottom: CGFloat) -> CGFloat {
        let height = max(viewportHeight * 0.82, (contentBottom + 45) / 0.78)
        let path = UIBezierPath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width, y: height * 0.78))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: height * 0.94),
            controlPoint: CGPoint(x: width * 0.62, y: height * 1.04)
        )
        path.close()

        let accents = UIBezierPath(ovalIn: CGRect(x: -70, y: 25, width: 150, height: 150))
        accents.append(UIBezierPath(ovalIn: CGRect(x: width - 85, y: height * 0.60, width: 150, height: 150)))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        curveMask.frame = bounds
        curveMask.path = path.cgPath
        accentLayer.frame = bounds
        accentLayer.path = accents.cgPath
        CATransaction.commit()
        return height
    }
}

struct LoginInteraction {
    let onPhoneChanged: (String) -> Void
    let onEmailChanged: (String) -> Void
    let onPasswordChanged: (String) -> Void
    let onSubmitTapped: () -> Void
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
            titleLabel.text = component.title
            titleLabel.textColor = .white
            titleLabel.sizeToFit()

            let iconName = component.isChecked ? "checkmark.square.fill" : "square"
            iconView.image = UIImage(systemName: iconName)
            iconView.tintColor = .white

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
                    color: .white),
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
                    color: .white),
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
                        cornerRadius: 25,
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
                        cornerRadius: 25,
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
                        cornerRadius: 25,
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
                        font: .systemFont(ofSize: 14, weight: .semibold), color: LoginPalette.cooldownText),
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
    items.append(
        AnyComponentWithIdentity(
            id: "hint",
            component: AnyComponent(
                Text(text: hint, font: .systemFont(ofSize: 14), color: UIColor.white.withAlphaComponent(0.80))))
    )
    for (title, targetMode) in links {
        let btn = Button(
            content: AnyComponent(
                Text(text: title, font: .systemFont(ofSize: 14, weight: .semibold), color: UIColor.white.withAlphaComponent(0.84))),
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
    let onPhoneChanged: (String) -> Void

    init(prefix: String, phone: String, onPhoneChanged: @escaping (String) -> Void) {
        self.prefix = prefix
        self.phone = phone
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
        private var onPhoneChanged: ((String) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            container.layer.cornerRadius = 25
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
            prefixButton.isUserInteractionEnabled = false
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

            let prefixTitle = component.prefix == "+84" ? "🇻🇳 +84" : component.prefix
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

            onPhoneChanged = component.onPhoneChanged
            return size
        }

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
        private let spinner = UIActivityIndicatorView(style: .medium)
        private var action: (() -> Void)?

        private let gradientLayer: CAGradientLayer = {
            let layer = CAGradientLayer()
            layer.colors = [LoginPalette.buttonStart.cgColor, LoginPalette.buttonEnd.cgColor]
            layer.startPoint = CGPoint(x: 0, y: 0)
            layer.endPoint = CGPoint(x: 1, y: 0)
            layer.cornerRadius = 25
            return layer
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)

            button.layer.insertSublayer(gradientLayer, at: 0)

            button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            button.setTitleColor(LoginPalette.buttonText, for: .normal)
            button.setTitleColor(LoginPalette.disabledButtonText, for: .disabled)
            button.layer.cornerRadius = 25
            button.layer.masksToBounds = true
            button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
            addSubview(button)
            spinner.hidesWhenStopped = true
            spinner.color = LoginPalette.buttonText
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
                button.backgroundColor = LoginPalette.disabledButton
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
    private let gradientLayer = AuthBackgroundLayer()
    private var scrollView: UIScrollView!

    private var state: LoginState = .empty
    private let interaction: LoginInteraction
    private let disposables = DisposableSet()

    init(signal: Signal<LoginState, NoError>, interaction: LoginInteraction) {
        self.interaction = interaction
        super.init()
        backgroundColor = LoginPalette.background

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

        scrollView = UIScrollView()
        scrollView.keyboardDismissMode = .onDrag
        view.addSubview(scrollView)
        scrollView.layer.insertSublayer(gradientLayer, at: 0)
        scrollView.addSubview(componentHostView)

    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        scrollView.frame = CGRect(origin: .zero, size: layout.size)
        updateComponentContent()
    }

    func refreshLocalizedStrings() {
        updateComponentContent()
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

        let gradientHeight = gradientLayer.update(
            width: scrollView.bounds.width, viewportHeight: scrollView.bounds.height,
            contentBottom: componentHostView.frame.maxY
        )

        scrollView.contentSize = CGSize(width: scrollView.bounds.width, height: max(scrollView.bounds.height, gradientHeight + 30))
    }
}
