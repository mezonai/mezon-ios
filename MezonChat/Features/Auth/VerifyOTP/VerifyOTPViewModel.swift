import Foundation
import Combine

final class VerifyOTPViewModel: BaseViewModel {

    @Published var otpCode: String = ""

    @Published private(set) var isSubmitEnabled: Bool = false
    @Published private(set) var resendCooldown: Int = 0

    let submitTrigger = PassthroughSubject<Void, Never>()
    let resendTrigger = PassthroughSubject<Void, Never>()

    var onVerifySuccess: ((User, MezonSession) -> Void)?

    let otpContext: OTPContext
    private var cooldownTimer: AnyCancellable?

    init(otpContext: OTPContext) {
        self.otpContext = otpContext
        super.init()
        bindValidation()
        bindSubmit()
        bindResend()
        startCooldown()
    }

    private func bindValidation() {
        $otpCode
            .map { $0.count == 6 }
            .assign(to: &$isSubmitEnabled)
    }

    private func bindSubmit() {
        submitTrigger
            .filter { [weak self] in self?.isSubmitEnabled == true && self?.isLoading == false }
            .sink { [weak self] in Task { await self?.verifyOTP() } }
            .store(in: &cancellables)
    }

    private func bindResend() {
        resendTrigger
            .filter { [weak self] in self?.resendCooldown == 0 && self?.isLoading == false }
            .sink { [weak self] in Task { await self?.resendOTP() } }
            .store(in: &cancellables)
    }

    @MainActor
    private func verifyOTP() async {
        isLoading = true
        errorMessage = nil
        do {
            let session = try await MezonHTTPClient.shared.confirmAuthenticateOTP(
                reqId: otpContext.reqId,
                otp: otpCode
            )
            SessionStore.save(session)
            MezonHTTPClient.shared.updateBaseURL(from: session)
            let user = User(
                id: session.userId ?? UUID().uuidString,
                username: session.username ?? otpContext.target,
                displayName: session.username ?? otpContext.target,
                avatarURL: nil,
                status: .online,
                bio: nil
            )
            onVerifySuccess?(user, session)
        } catch {
            errorMessage = "Mã OTP không đúng. Vui lòng thử lại."
            AppLogger.app.error("OTP verify failed: \(error)")
        }
        isLoading = false
    }

    @MainActor
    private func resendOTP() async {
        guard resendCooldown == 0 else { return }
        isLoading = true
        errorMessage = nil
        do {
            switch otpContext.type {
            case .email:
                let res = try await MezonHTTPClient.shared.authenticateEmailOTPRequest(email: otpContext.target)
                if res.reqId == nil {
                    errorMessage = "Không thể gửi lại OTP. Vui lòng thử lại."
                    isLoading = false
                    return
                }
            case .sms:
                let res = try await MezonHTTPClient.shared.authenticateSMSOTPRequest(phone: otpContext.target)
                if res.reqId == nil {
                    errorMessage = "Không thể gửi lại OTP. Vui lòng thử lại."
                    isLoading = false
                    return
                }
            }
            startCooldown()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func startCooldown(seconds: Int = 60) {
        resendCooldown = seconds
        cooldownTimer?.cancel()
        cooldownTimer = Timer.publish(every: 1, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.resendCooldown > 0 {
                    self.resendCooldown -= 1
                } else {
                    self.cooldownTimer?.cancel()
                }
            }
    }
}
