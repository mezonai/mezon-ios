import UIKit

final class VerifyOTPViewController: BaseViewController {

    private let otpContext: OTPContext
    private let context: AccountContext
    private(set) var currentReqId: String
    private var cooldownTimer: Timer?
    private let mainQueue = Queue.mainQueue()

    private let otpCodePipe = ValuePipe<String>()
    private let isSubmitEnabledPipe = ValuePipe<Bool>()
    private let resendCooldownPipe = ValuePipe<Int>()
    private let isLoadingPipe = ValuePipe<Bool>()
    private let errorMessagePipe = ValuePipe<String?>()
    private let submitPipe = ValuePipe<Void>()
    private let resendPipe = ValuePipe<Void>()

    private(set) var otpCode: String = ""
    private(set) var isSubmitEnabled: Bool = false
    private(set) var resendCooldown: Int = 0
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

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

    private lazy var instructionLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14.sf)
        l.textColor = .loginSubtitleColor
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var targetLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        l.textColor = .loginTitleColor
        l.textAlignment = .center
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

    private lazy var actionButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        btn.setTitleColor(.white, for: .normal)
        btn.setTitleColor(UIColor.white.withAlphaComponent(0.5), for: .disabled)
        btn.layer.cornerRadius = 12.sw
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var alternativeSection: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 6.sh
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.color = .white
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    init(otpContext: OTPContext, context: AccountContext) {
        self.otpContext = otpContext
        self.context = context
        self.currentReqId = otpContext.reqId
        super.init(navigationBarPresentationData: nil)
        bindValidation()
        bindSubmit()
        bindResend()
        startCooldown()
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageChange), name: LanguageManager.didChangeNotification, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }

    override func setupUI() {
        view.layer.insertSublayer(gradientLayer, at: 0)
        navigationController?.setNavigationBarHidden(true, animated: false)

        let instructionStack = UIStackView(arrangedSubviews: [instructionLabel, targetLabel])
        instructionStack.axis = .vertical
        instructionStack.spacing = 4.sh
        instructionStack.alignment = .center
        instructionStack.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = UIStackView(arrangedSubviews: [titleLabel, instructionStack, otpStack, actionButton, alternativeSection])
        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.setCustomSpacing(12.sh, after: titleLabel)
        contentStack.setCustomSpacing(28.sh, after: instructionStack)
        contentStack.setCustomSpacing(28.sh, after: otpStack)
        contentStack.setCustomSpacing(16.sh, after: actionButton)
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
            contentStack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 60.sh),
            contentStack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 24.sw),
            contentStack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -24.sw),
            contentStack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -40.sh),
            contentStack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -48.sw),
            otpStack.heightAnchor.constraint(equalToConstant: 56.sh),
            actionButton.heightAnchor.constraint(equalToConstant: 52.sh),
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        applyTheme()
        refreshLocalizedStrings()
        updateActionButton()
        digitFields.first?.becomeFirstResponder()
    }

    override func setupBindings() {
        disposables.add(actionButton.tapSignal().start(next: { [weak self] in
            guard let self else { return }
            if self.resendCooldown == 0 { self.triggerResend() }
            else { self.triggerSubmit() }
        }))
        disposables.add((isSubmitEnabledPipe.signal() |> deliverOnMainQueue).start(next: { [weak self] _ in self?.updateActionButton() }))
        disposables.add((resendCooldownPipe.signal() |> deliverOnMainQueue).start(next: { [weak self] _ in self?.updateActionButton() }))
        disposables.add((isLoadingPipe.signal() |> deliverOnMainQueue).start(next: { [weak self] loading in
            if loading { self?.loadingIndicator.startAnimating() } else { self?.loadingIndicator.stopAnimating() }
            self?.actionButton.isUserInteractionEnabled = !loading
        }))
        disposables.add((errorMessagePipe.signal() |> deliverOnMainQueue).start(next: { [weak self] msg in
            guard let msg else { return }
            Toast.error(msg)
            self?.shakeOTPFields()
        }))
        for field in digitFields { field.addTarget(self, action: #selector(digitFieldChanged(_:)), for: .editingChanged) }
    }

    override func applyTheme() {
        let attrs = ThemeManager.shared.attributes
        gradientLayer.colors = attrs.loginGradientColors.map { $0.cgColor }
        titleLabel.textColor = attrs.loginTitleColor
        instructionLabel.textColor = attrs.loginSubtitleColor
        targetLabel.textColor = attrs.loginTitleColor
        actionButton.backgroundColor = (resendCooldown == 0 || isSubmitEnabled) ? attrs.loginButtonBg : attrs.loginButtonBgDisabled
        digitFields.forEach { tf in
            tf.backgroundColor = attrs.loginInputBg
            tf.layer.borderColor = attrs.loginInputBorder.cgColor
            tf.textColor = attrs.loginInputTextColor
        }
        if let hintLabel = alternativeSection.arrangedSubviews.first as? UILabel { hintLabel.textColor = attrs.loginAlternativeText }
        if let changeBtn = alternativeSection.arrangedSubviews.last as? UIButton { changeBtn.setTitleColor(attrs.textLink, for: .normal) }
    }

    func setOtpCode(_ v: String) { otpCode = v; otpCodePipe.putNext(v) }
    private func setSubmitEnabled(_ v: Bool) { isSubmitEnabled = v; isSubmitEnabledPipe.putNext(v) }
    private func setResendCooldown(_ v: Int) { resendCooldown = v; resendCooldownPipe.putNext(v) }
    private func setIsLoading(_ v: Bool) { isLoading = v; isLoadingPipe.putNext(v) }
    private func setErrorMessage(_ v: String?) { errorMessage = v; errorMessagePipe.putNext(v) }
    func triggerSubmit() { submitPipe.putNext(()) }
    func triggerResend() { resendPipe.putNext(()) }

    private func bindValidation() {
        disposables.add((otpCodePipe.signal() |> map { $0.count == 6 } |> deliverOnMainQueue).start(next: { [weak self] enabled in self?.setSubmitEnabled(enabled) }))
    }

    private func bindSubmit() {
        let filtered = submitPipe.signal() |> filter { [weak self] in self?.isSubmitEnabled == true && self?.isLoading == false }
        disposables.add((filtered |> deliverOnMainQueue).start(next: { [weak self] in Task { await self?.verifyOTP() } }))
    }

    private func bindResend() {
        let filtered = resendPipe.signal() |> filter { [weak self] in self?.resendCooldown == 0 && self?.isLoading == false }
        disposables.add((filtered |> deliverOnMainQueue).start(next: { [weak self] in Task { await self?.resendOTP() } }))
    }

    @MainActor private func verifyOTP() async {
        setIsLoading(true)
        setErrorMessage(nil)
        do {
            let session = try await self.context.account.network.confirmAuthenticateOTP(reqId: currentReqId, otp: otpCode)
            SessionStore.save(session)
            self.context.account.network.updateBaseURL(from: session)
            let user = User(id: session.userId ?? UUID().uuidString, username: session.username ?? otpContext.target, displayName: session.username ?? otpContext.target, avatarURL: nil, status: .online, bio: nil)
            context.login(user: user, session: session)
        } catch {
            setErrorMessage(L(L10n.OTPVerify.otpNotMatch))
        }
        setIsLoading(false)
    }

    @MainActor private func resendOTP() async {
        guard resendCooldown == 0 else { return }
        setIsLoading(true)
        setErrorMessage(nil)
        do {
            switch otpContext.type {
            case .email:
                let res = try await self.context.account.network.authenticateEmailOTPRequest(email: otpContext.target)
                guard let newReqId = res.reqId else { setErrorMessage(L(L10n.OTPVerify.resendFailed)); setIsLoading(false); return }
                currentReqId = newReqId
            case .sms:
                let res = try await self.context.account.network.authenticateSMSOTPRequest(phone: otpContext.target)
                guard let newReqId = res.reqId else { setErrorMessage(L(L10n.OTPVerify.resendFailed)); setIsLoading(false); return }
                currentReqId = newReqId
            }
            setOtpCode("")
            clearOTPFields()
            startCooldown()
        } catch {
            setErrorMessage(error.localizedDescription)
        }
        setIsLoading(false)
    }

    private func startCooldown(seconds: Int = 60) {
        setResendCooldown(seconds)
        cooldownTimer?.invalidate()
        let timer = Timer(timeout: 1, repeat: true, completion: { [weak self] t in
            guard let self else { t.invalidate(); return }
            if self.resendCooldown > 0 { self.setResendCooldown(self.resendCooldown - 1) }
            else { t.invalidate() }
        }, queue: mainQueue)
        cooldownTimer = timer
        timer.start()
    }

    @objc private func handleLanguageChange() { refreshLocalizedStrings() }

    private func refreshLocalizedStrings() {
        titleLabel.text = L(L10n.OTPVerify.loginToMezon)
        instructionLabel.text = L(L10n.OTPVerify.enterCodeFrom)
        targetLabel.text = otpContext.target
        updateAlternativeSection()
        updateActionButton()
    }

    private func updateAlternativeSection() {
        alternativeSection.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let hintLabel = UILabel()
        hintLabel.text = L(L10n.OTPVerify.didNotReceive)
        hintLabel.font = .systemFont(ofSize: 14.sf)
        hintLabel.textColor = .loginAlternativeText
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        alternativeSection.addArrangedSubview(hintLabel)

        let changeLink = UIButton(type: .system)
        let changeTitle = otpContext.type == .email ? L(L10n.OTPVerify.changeEmail) : L(L10n.OTPVerify.changePhone)
        changeLink.setTitle(changeTitle, for: .normal)
        changeLink.titleLabel?.font = .systemFont(ofSize: 14.sf)
        changeLink.setTitleColor(.mezonLink, for: .normal)
        changeLink.addAction(UIAction { [weak self] _ in self?.navigationController?.popToRootViewController(animated: true) }, for: .touchUpInside)
        alternativeSection.addArrangedSubview(changeLink)
    }

    private func updateActionButton() {
        let cd = resendCooldown
        UIView.performWithoutAnimation {
            if cd > 0 {
                actionButton.setTitle("\(L(L10n.OTPVerify.verifyOTP)) (\(cd))", for: .normal)
                actionButton.isEnabled = isSubmitEnabled
            } else {
                actionButton.setTitle(L(L10n.OTPVerify.resendOTP), for: .normal)
                actionButton.isEnabled = true
            }
            actionButton.backgroundColor = actionButton.isEnabled ? ThemeManager.shared.attributes.loginButtonBg : ThemeManager.shared.attributes.loginButtonBgDisabled
            actionButton.layoutIfNeeded()
        }
    }

    private func clearOTPFields() {
        digitFields.forEach { $0.text = "" }
        setOtpCode("")
        digitFields.first?.becomeFirstResponder()
    }

    @objc private func digitFieldChanged(_ field: UITextField) {
        let text = field.text ?? ""
        if text.count == 6 && text.allSatisfy({ $0.isNumber }) {
            for (i, char) in text.enumerated() where i < digitFields.count { digitFields[i].text = String(char) }
            updateOTPCode()
            digitFields.last?.becomeFirstResponder()
            return
        }
        if text.count > 1 { field.text = String(text.last!) }
        updateOTPCode()
        if let idx = digitFields.firstIndex(of: field), field.text?.isEmpty == false {
            if idx + 1 < digitFields.count { digitFields[idx + 1].becomeFirstResponder() }
            else { field.resignFirstResponder() }
        }
    }

    private func updateOTPCode() {
        let code = digitFields.compactMap { $0.text }.joined()
        setOtpCode(code)
    }

    private func makeDigitField() -> UITextField {
        let tf = OTPDigitTextField()
        tf.keyboardType = .numberPad
        tf.textAlignment = .center
        tf.font = .systemFont(ofSize: 22.sf, weight: .semibold)
        tf.layer.cornerRadius = 12.sw
        tf.layer.borderWidth = 1
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
