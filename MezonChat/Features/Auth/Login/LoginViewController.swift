import UIKit

enum LoginMode: Int, CaseIterable {
    case sms = 0
    case emailOTP = 1
    case password = 2
}

struct OTPContext {
    let reqId: String
    let target: String
    let type: OTPType
    enum OTPType { case email, sms }
}

struct LoginState {
    var mode: LoginMode
    var email: String
    var phone: String
    var countryPrefix: String
    var password: String
    var isSubmitEnabled: Bool
    var otpCooldown: Int
    var isLoading: Bool
    var errorMessage: String?
    var isPasswordVisible: Bool

    static let empty = LoginState(mode: .sms, email: "", phone: "", countryPrefix: "+84", password: "", isSubmitEnabled: false, otpCooldown: 0, isLoading: false, errorMessage: nil, isPasswordVisible: false)
}

final class LoginViewController: ViewController, AuthScreenStatusBarStyle {

    private let context: AccountContext
    private let disposables = DisposableSet()

    private let modePipe = ValuePipe<LoginMode>()
    private let emailPipe = ValuePipe<String>()
    private let phonePipe = ValuePipe<String>()
    private let countryPrefixPipe = ValuePipe<String>()
    private let passwordPipe = ValuePipe<String>()
    private let isSubmitEnabledPipe = ValuePipe<Bool>()
    private let otpCooldownPipe = ValuePipe<Int>()
    private let isLoadingPipe = ValuePipe<Bool>()
    private let errorMessagePipe = ValuePipe<String?>()
    private let isPasswordVisiblePipe = ValuePipe<Bool>()
    private let submitPipe = ValuePipe<Void>()
    private let needsReloadPipe = ValuePipe<Void>()

    private var cooldownTimer: Timer?
    private let mainQueue = Queue.mainQueue()

    private(set) var mode: LoginMode = .sms
    private(set) var email: String = ""
    private(set) var phone: String = ""
    private(set) var countryPrefix: String = "+84"
    private(set) var password: String = ""
    private(set) var isSubmitEnabled: Bool = false
    private(set) var otpCooldown: Int = 0
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var isPasswordVisible: Bool = false

    private var loginNode: LoginContainerNode { displayNode as! LoginContainerNode }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
        self.setStatusBarStyle(.Black, animated: false)
        bindValidation()
        bindSubmit()
        modePipe.putNext(mode)
        emailPipe.putNext(email)
        phonePipe.putNext(phone)
        countryPrefixPipe.putNext(countryPrefix)
        passwordPipe.putNext(password)
        isSubmitEnabledPipe.putNext(isSubmitEnabled)
        otpCooldownPipe.putNext(otpCooldown)
        isLoadingPipe.putNext(isLoading)
        errorMessagePipe.putNext(errorMessage)
        isPasswordVisiblePipe.putNext(isPasswordVisible)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let interaction = LoginInteraction(
            onPhoneChanged: { [weak self] text in self?.setPhone(text) },
            onEmailChanged: { [weak self] text in self?.setEmail(text) },
            onPasswordChanged: { [weak self] text in self?.setPassword(text) },
            onSubmitTapped: { [weak self] in self?.triggerSubmit() },
            onCountryPrefixTapped: { [weak self] in self?.showCountryPicker() },
            onShowPasswordToggled: { [weak self] in
                guard let self else { return }
                self.setPasswordVisible(!self.isPasswordVisible)
            },
            onModeSelected: { [weak self] mode in self?.setMode(mode) }
        )
        displayNode = LoginContainerNode(signal: stateSignal(), interaction: interaction)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.setStatusBarStyle(.Black, animated: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageChange), name: LanguageManager.didChangeNotification, object: nil)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        loginNode.updateLayout(layout: layout, transition: transition)
    }

    deinit { disposables.dispose() }

    func setMode(_ v: LoginMode) { mode = v; modePipe.putNext(v); needsReloadPipe.putNext(()) }
    func setEmail(_ v: String) { email = v; emailPipe.putNext(v) }
    func setPhone(_ v: String) { phone = v; phonePipe.putNext(v) }
    func setCountryPrefix(_ v: String) { countryPrefix = v; countryPrefixPipe.putNext(v); needsReloadPipe.putNext(()) }
    func setPassword(_ v: String) { password = v; passwordPipe.putNext(v) }

    private func setSubmitEnabled(_ v: Bool) { isSubmitEnabled = v; isSubmitEnabledPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setOtpCooldown(_ v: Int) { otpCooldown = v; otpCooldownPipe.putNext(v); needsReloadPipe.putNext(()) }
    func setIsLoading(_ v: Bool) { isLoading = v; isLoadingPipe.putNext(v); needsReloadPipe.putNext(()) }
    func setErrorMessage(_ v: String?) { errorMessage = v; errorMessagePipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setPasswordVisible(_ v: Bool) { isPasswordVisible = v; isPasswordVisiblePipe.putNext(v); needsReloadPipe.putNext(()) }

    func triggerSubmit() { submitPipe.putNext(()) }

    private func bindValidation() {
        let combined = combineLatest(queue: mainQueue, modePipe.signal(), emailPipe.signal(), phonePipe.signal(), passwordPipe.signal())
        let validated = combined |> map { [weak self] mode, email, phone, password in
            self?.validate(mode: mode, email: email, phone: phone, password: password) ?? false
        }
        disposables.add((validated |> deliverOnMainQueue).start(next: { [weak self] enabled in self?.setSubmitEnabled(enabled) }))
    }

    private func validate(mode: LoginMode, email: String, phone: String, password: String) -> Bool {
        switch mode {
        case .sms: return isValidPhone(phone, prefix: countryPrefix)
        case .emailOTP: return isValidEmail(email)
        case .password: return isValidEmail(email) && !password.isEmpty
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        email.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil
    }

    private func isValidPhone(_ phone: String, prefix: String) -> Bool {
        let cleaned = phone.trimmingCharacters(in: .whitespaces)
        if prefix == "+84" {
            let p = cleaned.hasPrefix("0") ? String(cleaned.dropFirst()) : cleaned
            return p.count == 9 && p.first.map { "3579".contains($0) } == true
        }
        return cleaned.count >= 7 && cleaned.allSatisfy { $0.isNumber }
    }

    private func bindSubmit() {
        let filtered = submitPipe.signal() |> filter { [weak self] in self?.isSubmitEnabled == true && self?.isLoading == false }
        disposables.add((filtered |> deliverOnMainQueue).start(next: { [weak self] in
            Task { await self?.handleSubmit() }
        }))
    }

    @MainActor private func handleSubmit() async {
        switch mode {
        case .sms: await sendSMSOTP()
        case .emailOTP: await sendEmailOTP()
        case .password: await loginWithPassword()
        }
    }

    @MainActor private func loginWithPassword() async {
        setIsLoading(true)
        setErrorMessage(nil)
        do {
            let session = try await self.context.account.network.authenticateEmail(email: email.trimmingCharacters(in: .whitespaces), password: password)
            handleSessionReceived(session)
        } catch {
            setErrorMessage(error.localizedDescription)
        }
        setIsLoading(false)
    }

    @MainActor private func sendEmailOTP() async {
        guard otpCooldown == 0 else { return }
        setIsLoading(true)
        setErrorMessage(nil)
        do {
            let res = try await self.context.account.network.authenticateEmailOTPRequest(email: email.trimmingCharacters(in: .whitespaces))
            guard let reqId = res.reqId else { setErrorMessage(L(L10n.OTPVerify.sendOtpError)); setIsLoading(false); return }
            startCooldown()
            pushOTPScreen(otpContext: OTPContext(reqId: reqId, target: email.trimmingCharacters(in: .whitespaces), type: .email))
        } catch {
            setErrorMessage(error.localizedDescription)
        }
        setIsLoading(false)
    }

    @MainActor private func sendSMSOTP() async {
        guard otpCooldown == 0 else { return }
        setIsLoading(true)
        setErrorMessage(nil)
        let fullPhone = buildFullPhone()
        do {
            let res = try await self.context.account.network.authenticateSMSOTPRequest(phone: fullPhone)
            guard let reqId = res.reqId else { setErrorMessage(L(L10n.OTPVerify.sendOtpError)); setIsLoading(false); return }
            startCooldown()
            pushOTPScreen(otpContext: OTPContext(reqId: reqId, target: fullPhone, type: .sms))
        } catch {
            setErrorMessage(error.localizedDescription)
        }
        setIsLoading(false)
    }

    func buildFullPhone() -> String {
        var p = phone.trimmingCharacters(in: .whitespaces)
        if countryPrefix == "+84" && p.hasPrefix("0") { p = String(p.dropFirst()) }
        return "\(countryPrefix)\(p)"
    }

    func handleSessionReceived(_ session: MezonSession) {
        SessionStore.save(session)
        self.context.account.network.updateBaseURL(from: session)
        let user = User(id: session.userId ?? UUID().uuidString, username: session.username ?? email, displayName: session.username ?? email, avatarURL: nil, status: .online, bio: nil)
        Task { @MainActor in context.login(user: user, session: session) }
    }

    private func pushOTPScreen(otpContext: OTPContext) {
        let vc = VerifyOTPViewController(otpContext: otpContext, context: context)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func startCooldown(seconds: Int = 60) {
        setOtpCooldown(seconds)
        cooldownTimer?.invalidate()
        let timer = Timer(timeout: 1, repeat: true, completion: { [weak self] t in
            guard let self else { t.invalidate(); return }
            if self.otpCooldown > 0 { self.setOtpCooldown(self.otpCooldown - 1) }
            else { t.invalidate() }
        }, queue: mainQueue)
        cooldownTimer = timer
        timer.start()
    }

    var currentState: LoginState {
        LoginState(mode: mode, email: email, phone: phone, countryPrefix: countryPrefix, password: password, isSubmitEnabled: isSubmitEnabled, otpCooldown: otpCooldown, isLoading: isLoading, errorMessage: errorMessage, isPasswordVisible: isPasswordVisible)
    }

    func stateSignal() -> Signal<LoginState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            subscriber.putNext(self.currentState)
            return (self.needsReloadPipe.signal()
                |> map { [weak self] _ in self?.currentState ?? .empty }
                |> deliverOnMainQueue
            ).start(next: { subscriber.putNext($0) })
        }
    }

    private func showCountryPicker() {
        let sheet = UIAlertController(title: L(L10n.Login.selectCountry), message: nil, preferredStyle: .actionSheet)
        let countries = [("+84", "🇻🇳 Việt Nam"), ("+81", "🇯🇵 Japan"), ("+1", "🇺🇸 USA")]
        for (prefix, name) in countries {
            sheet.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in self?.setCountryPrefix(prefix) })
        }
        sheet.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        if let pop = sheet.popoverPresentationController { pop.sourceView = loginNode.phonePrefixButton }
        present(sheet, animated: true)
    }

    @objc private func handleLanguageChange() { loginNode.refreshLocalizedStrings() }
}

#if DEBUG
import SwiftUI

@available(iOS 14.0, *)
struct LoginViewController_Previews: PreviewProvider {
    static var previews: some View {
        UIViewControllerPreview {
            UINavigationController(rootViewController: LoginViewController(context: AccountContextImpl.preview))
        }
        .ignoresSafeArea()
        .previewDisplayName("Login")
    }
}
#endif
