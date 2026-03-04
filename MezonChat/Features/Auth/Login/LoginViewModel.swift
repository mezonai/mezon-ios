import Foundation
import Combine

enum LoginMode: Int, CaseIterable {
    case sms      = 0
    case emailOTP = 1
    case password = 2
}

final class LoginViewModel: BaseViewModel {

    @Published var mode: LoginMode = .sms
    @Published var email: String = ""
    @Published var phone: String = ""
    @Published var countryPrefix: String = "+84"
    @Published var password: String = ""

    @Published private(set) var isSubmitEnabled: Bool = false
    @Published private(set) var otpCooldown: Int = 0

    let submitTrigger = PassthroughSubject<Void, Never>()

    var onLoginSuccess: ((User, MezonSession) -> Void)?
    var onOTPRequired: ((OTPContext) -> Void)?

    private let context: AppContext
    private var cooldownTimer: AnyCancellable?

    init(context: AppContext) {
        self.context = context
        super.init()
        bindValidation()
        bindSubmit()
    }

    private func bindValidation() {
        Publishers.CombineLatest4($mode, $email, $phone, $password)
            .map { [weak self] mode, email, phone, password in
                self?.validate(mode: mode, email: email, phone: phone, password: password) ?? false
            }
            .assign(to: &$isSubmitEnabled)
    }

    private func validate(mode: LoginMode, email: String, phone: String, password: String) -> Bool {
        switch mode {
        case .sms:      return isValidPhone(phone, prefix: countryPrefix)
        case .emailOTP: return isValidEmail(email)
        case .password: return isValidEmail(email) && !password.isEmpty
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$"
        return email.range(of: pattern, options: .regularExpression) != nil
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
        submitTrigger
            .filter { [weak self] in self?.isSubmitEnabled == true && self?.isLoading == false }
            .sink { [weak self] in
                Task { await self?.handleSubmit() }
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func handleSubmit() async {
        switch mode {
        case .sms:       await sendSMSOTP()
        case .emailOTP:  await sendEmailOTP()
        case .password:  await loginWithPassword()
        }
    }

    @MainActor
    private func loginWithPassword() async {
        isLoading = true
        errorMessage = nil
        do {
            let session = try await MezonHTTPClient.shared.authenticateEmail(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
            handleSessionReceived(session)
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.app.error("Login failed: \(error)")
        }
        isLoading = false
    }

    @MainActor
    private func sendEmailOTP() async {
        guard otpCooldown == 0 else { return }
        isLoading = true
        errorMessage = nil
        do {
            let res = try await MezonHTTPClient.shared.authenticateEmailOTPRequest(
                email: email.trimmingCharacters(in: .whitespaces)
            )
            guard let reqId = res.reqId else {
                errorMessage = "Failed to receive OTP. Please try again."
                isLoading = false
                return
            }
            startCooldown()
            onOTPRequired?(OTPContext(reqId: reqId, target: email, type: .email))
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func sendSMSOTP() async {
        guard otpCooldown == 0 else { return }
        isLoading = true
        errorMessage = nil
        let fullPhone = buildFullPhone()
        do {
            let res = try await MezonHTTPClient.shared.authenticateSMSOTPRequest(phone: fullPhone)
            guard let reqId = res.reqId else {
                errorMessage = "Failed to receive OTP. Please try again."
                isLoading = false
                return
            }
            startCooldown()
            onOTPRequired?(OTPContext(reqId: reqId, target: fullPhone, type: .sms))
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func buildFullPhone() -> String {
        var p = phone.trimmingCharacters(in: .whitespaces)
        if countryPrefix == "+84" && p.hasPrefix("0") { p = String(p.dropFirst()) }
        return "\(countryPrefix)\(p)"
    }

    func handleSessionReceived(_ session: MezonSession) {
        SessionStore.save(session)
        MezonHTTPClient.shared.updateBaseURL(from: session)
        let user = User(
            id: session.userId ?? UUID().uuidString,
            username: session.username ?? email,
            displayName: session.username ?? email,
            avatarURL: nil,
            status: .online,
            bio: nil
        )
        onLoginSuccess?(user, session)
    }

    private func startCooldown(seconds: Int = 60) {
        otpCooldown = seconds
        cooldownTimer?.cancel()
        cooldownTimer = Timer.publish(every: 1, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.otpCooldown > 0 {
                    self.otpCooldown -= 1
                } else {
                    self.cooldownTimer?.cancel()
                }
            }
    }
}

struct OTPContext {
    let reqId: String
    let target: String
    let type: OTPType

    enum OTPType { case email, sms }
}
