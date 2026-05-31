import UIKit

private final class AmountFormattingTextField: UITextField {
    var onPlainAmountChanged: ((Int64) -> Void)?
    private var isFormattingAmount = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(amountTextChanged), for: .editingChanged)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setFormattedAmount(_ raw: String) {
        text = raw
        normalizeAmountText(preserveCaret: false)
    }

    override func insertText(_ text: String) {
        super.insertText(text)
        normalizeAmountText(preserveCaret: true)
    }

    override func deleteBackward() {
        super.deleteBackward()
        normalizeAmountText(preserveCaret: true)
    }

    override func paste(_ sender: Any?) {
        super.paste(sender)
        normalizeAmountText(preserveCaret: true)
    }

    @objc private func amountTextChanged() {
        normalizeAmountText(preserveCaret: true)
    }

    private func normalizeAmountText(preserveCaret: Bool) {
        guard !isFormattingAmount else { return }
        isFormattingAmount = true
        defer { isFormattingAmount = false }

        let current = text ?? ""
        let caretDigitIndex = preserveCaret
            ? amountCaretDigitIndex()
            : MmnMoneyFormat.onlyDigitCharacters(current).count
        let result = MmnMoneyFormat.formatTokenAmount(current)
        onPlainAmountChanged?(result.plain)
        
        guard current != result.display else { return }
        
        text = result.display
        let digitCount = MmnMoneyFormat.onlyDigitCharacters(result.display).count
        let charIdx = MmnMoneyFormat.tokenAmountCaretCharacterIndex(
            display: result.display,
            digitIndex: min(caretDigitIndex, digitCount)
        )
        setCaret(characterIndex: charIdx)
    }

    private func amountCaretDigitIndex() -> Int {
        let current = text ?? ""
        guard let selectedRange = selectedTextRange else {
            return MmnMoneyFormat.onlyDigitCharacters(current).count
        }
        let offset = self.offset(from: beginningOfDocument, to: selectedRange.start)
        let clampedOffset = max(0, min(offset, (current as NSString).length))
        let beforeCaret = (current as NSString).substring(to: clampedOffset)
        return MmnMoneyFormat.onlyDigitCharacters(beforeCaret).count
    }

    private func setCaret(characterIndex: Int) {
        let len = (text ?? "") as NSString
        let c = max(0, min(characterIndex, len.length))
        if let pos = position(from: beginningOfDocument, offset: c) {
            selectedTextRange = textRange(from: pos, to: pos)
        }
    }
}

@MainActor
final class WalletTransferViewController: BaseViewController, UIGestureRecognizerDelegate {

    private let context: AccountContext
    private var payload: TransferQRPayload

    private var walletDetail: WalletDetail?
    private var isSending = false

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let headingLabel = UILabel()

    private let cardWalletView = WalletCardView()

    private let recipientLabel = UILabel()
    private let recipientField = TappableContainer()
    private let recipientRowStack = UIStackView()
    private let recipientValueLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private let recipientChevron = UIImageView()

    private let amountLabel = UILabel()
    private let amountField = AmountFormattingTextField()
    private let amountFieldContainer = UIView()

    private let noteLabel = UILabel()
    private let noteContainer = UIView()
    private let noteField = UITextView()
    private let notePlaceholder = UILabel()
    private let noteCounterLabel = UILabel()

    private let bottomBar = UIView()
    private let sendButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var bottomBarBottomConstraint: NSLayoutConstraint?

    private var plainAmount: Int64 = 0
    private var didAutoFocusAmountField = false

    init(context: AccountContext, payload: TransferQRPayload) {
        self.context = context
        self.payload = payload
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboardDismiss()
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardFrameWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        Task { await loadWalletDetail() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAutoFocusAmountField else { return }
        let hasRecipient = (payload.walletAddress?.isEmpty == false) || (payload.receiverUserId?.isEmpty == false)
        guard hasRecipient else { return }
        didAutoFocusAmountField = true
        let focus = { [weak self] in
            _ = self?.amountField.becomeFirstResponder()
        }
        if let tc = transitionCoordinator {
            tc.animate(alongsideTransition: nil) { _ in
                focus()
            }
        } else {
            DispatchQueue.main.async(execute: focus)
        }
    }

    override func setupUI() {
        view.addSubview(headerView)
        view.addSubview(scrollView)
        view.addSubview(bottomBar)
        scrollView.addSubview(contentStack)

        headerView.translatesAutoresizingMaskIntoConstraints = false
        backButton.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        headerView.addSubview(backButton)
        headerView.addSubview(titleLabel)

        let backImg = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        backButton.setImage(backImg, for: .normal)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.alignment = .fill

        headingLabel.font = .systemFont(ofSize: 18, weight: .bold)
        headingLabel.numberOfLines = 0

        contentStack.addArrangedSubview(headingLabel)
        contentStack.setCustomSpacing(20, after: headingLabel)
        contentStack.addArrangedSubview(cardWalletView)
        contentStack.setCustomSpacing(8, after: cardWalletView)

        contentStack.addArrangedSubview(recipientLabel)
        contentStack.setCustomSpacing(6, after: recipientLabel)
        contentStack.addArrangedSubview(recipientField)

        contentStack.addArrangedSubview(amountLabel)
        contentStack.setCustomSpacing(6, after: amountLabel)
        contentStack.addArrangedSubview(amountFieldContainer)

        contentStack.addArrangedSubview(noteLabel)
        contentStack.setCustomSpacing(6, after: noteLabel)
        contentStack.addArrangedSubview(noteContainer)

        configureRecipientField()
        recipientField.onTap = { [weak self] in self?.presentRecipientPickerIfNeeded() }
        configureAmountField()
        configureNoteField()
        configureBottomBar()

        bottomBar.addSubview(sendButton)
        bottomBar.addSubview(activityIndicator)

        let header: CGFloat = 56
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: header),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            sendButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            sendButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -20),
            sendButton.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),
            sendButton.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -12),
            sendButton.heightAnchor.constraint(equalToConstant: 50),

            activityIndicator.centerXAnchor.constraint(equalTo: sendButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),
        ])
        let bbBottom = bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        bbBottom.isActive = true
        bottomBarBottomConstraint = bbBottom
    }

    private func configureRecipientField() {
        recipientLabel.font = .systemFont(ofSize: 14)
        recipientField.translatesAutoresizingMaskIntoConstraints = false
        recipientField.layer.cornerRadius = 8
        recipientField.layer.borderWidth = 1
        recipientField.heightAnchor.constraint(equalToConstant: 44).isActive = true

        recipientRowStack.translatesAutoresizingMaskIntoConstraints = false
        recipientRowStack.axis = .horizontal
        recipientRowStack.alignment = .center
        recipientRowStack.spacing = 8
        recipientRowStack.isLayoutMarginsRelativeArrangement = true
        recipientRowStack.layoutMargins = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)

        recipientValueLabel.font = .systemFont(ofSize: 14)
        recipientValueLabel.lineBreakMode = .byTruncatingMiddle
        recipientValueLabel.numberOfLines = 1
        recipientValueLabel.translatesAutoresizingMaskIntoConstraints = false
        recipientValueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let copyIcon = UIImage(systemName: "doc.on.doc")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        copyButton.setImage(copyIcon, for: .normal)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.addTarget(self, action: #selector(copyAddressTapped), for: .touchUpInside)

        recipientChevron.image = UIImage(systemName: "chevron.down")
        recipientChevron.translatesAutoresizingMaskIntoConstraints = false
        recipientChevron.contentMode = .scaleAspectFit
        recipientChevron.setContentHuggingPriority(.required, for: .horizontal)

        recipientField.addSubview(recipientRowStack)
        recipientRowStack.addArrangedSubview(recipientValueLabel)
        recipientRowStack.addArrangedSubview(copyButton)
        recipientRowStack.addArrangedSubview(recipientChevron)

        NSLayoutConstraint.activate([
            recipientRowStack.leadingAnchor.constraint(equalTo: recipientField.leadingAnchor),
            recipientRowStack.trailingAnchor.constraint(equalTo: recipientField.trailingAnchor),
            recipientRowStack.topAnchor.constraint(equalTo: recipientField.topAnchor),
            recipientRowStack.bottomAnchor.constraint(equalTo: recipientField.bottomAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 26),
            copyButton.heightAnchor.constraint(equalToConstant: 26),
            recipientChevron.widthAnchor.constraint(equalToConstant: 16),
            recipientChevron.heightAnchor.constraint(equalToConstant: 16),
        ])

        copyButton.isHidden = !(payload.walletAddress != nil && !(payload.walletAddress?.isEmpty ?? true))
    }

    private func presentRecipientPickerIfNeeded() {
        if let w = payload.walletAddress, !w.isEmpty { return }
        if payload.recipientLocked { return }
        let picker = TransferRecipientPickerViewController(context: context) { [weak self] row in
            guard let self else { return }
            self.payload.receiverUserId = String(row.user.id)
            self.payload.walletAddress = nil
            self.payload.recipientLocked = false
            let label = row.primaryText.isEmpty ? "\(row.user.id)" : row.primaryText
            self.payload.receiverDisplayName = label
            self.recipientValueLabel.text = label
            self.copyButton.isHidden = true
            self.recipientChevron.isHidden = false
            DispatchQueue.main.async {
                _ = self.amountField.becomeFirstResponder()
            }
        }
        let nav = UINavigationController(rootViewController: picker)
        Self.styleRecipientPickerNavigation(nav)
        nav.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *), let sheet = nav.sheetPresentationController {
            sheet.prefersGrabberVisible = true
            sheet.detents = [.large()]
            if #available(iOS 16.0, *) {
                sheet.preferredCornerRadius = 10
            }
        }
        present(nav, animated: true)
    }

    private static func styleRecipientPickerNavigation(_ nav: UINavigationController) {
        nav.view.backgroundColor = .mezonPrimary
        nav.navigationBar.isTranslucent = false
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .mezonPrimary
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.mezonTextStrong]
        nav.navigationBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            nav.navigationBar.scrollEdgeAppearance = appearance
            nav.navigationBar.compactScrollEdgeAppearance = appearance
        }
        nav.navigationBar.compactAppearance = appearance
        nav.navigationBar.tintColor = .mezonTextStrong
    }

    private func configureAmountField() {
        amountLabel.font = .systemFont(ofSize: 14)
        amountFieldContainer.translatesAutoresizingMaskIntoConstraints = false
        amountFieldContainer.layer.cornerRadius = 8
        amountFieldContainer.layer.borderWidth = 1
        amountFieldContainer.heightAnchor.constraint(equalToConstant: 44).isActive = true

        amountField.translatesAutoresizingMaskIntoConstraints = false
        amountField.font = .systemFont(ofSize: 16, weight: .semibold)
        amountField.keyboardType = .numberPad
        amountField.textAlignment = .left
        amountField.onPlainAmountChanged = { [weak self] amount in
            self?.plainAmount = amount
        }
        amountField.setFormattedAmount("0")

        amountFieldContainer.addSubview(amountField)
        NSLayoutConstraint.activate([
            amountField.leadingAnchor.constraint(equalTo: amountFieldContainer.leadingAnchor, constant: 12),
            amountField.trailingAnchor.constraint(equalTo: amountFieldContainer.trailingAnchor, constant: -12),
            amountField.topAnchor.constraint(equalTo: amountFieldContainer.topAnchor),
            amountField.bottomAnchor.constraint(equalTo: amountFieldContainer.bottomAnchor),
        ])

        if let suggested = payload.suggestedAmount, !suggested.isEmpty {
            amountField.setFormattedAmount(suggested)
        }
    }

    private func configureNoteField() {
        noteLabel.font = .systemFont(ofSize: 14)
        noteContainer.translatesAutoresizingMaskIntoConstraints = false
        noteContainer.layer.cornerRadius = 8
        noteContainer.layer.borderWidth = 1

        noteField.translatesAutoresizingMaskIntoConstraints = false
        noteField.font = .systemFont(ofSize: 14)
        noteField.backgroundColor = .clear
        noteField.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        noteField.delegate = self

        notePlaceholder.translatesAutoresizingMaskIntoConstraints = false
        notePlaceholder.font = .systemFont(ofSize: 14)
        notePlaceholder.textColor = .placeholderText
        notePlaceholder.text = L(L10n.Profile.sendTokenDefaultNote)

        noteCounterLabel.translatesAutoresizingMaskIntoConstraints = false
        noteCounterLabel.font = .systemFont(ofSize: 12)
        noteCounterLabel.textAlignment = .right

        noteContainer.addSubview(noteField)
        noteContainer.addSubview(notePlaceholder)
        noteContainer.addSubview(noteCounterLabel)

        NSLayoutConstraint.activate([
            noteContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            noteField.topAnchor.constraint(equalTo: noteContainer.topAnchor, constant: 4),
            noteField.leadingAnchor.constraint(equalTo: noteContainer.leadingAnchor, constant: 4),
            noteField.trailingAnchor.constraint(equalTo: noteContainer.trailingAnchor, constant: -4),
            noteField.bottomAnchor.constraint(equalTo: noteCounterLabel.topAnchor, constant: -4),
            noteField.heightAnchor.constraint(greaterThanOrEqualToConstant: 90),

            notePlaceholder.topAnchor.constraint(equalTo: noteField.topAnchor, constant: 12),
            notePlaceholder.leadingAnchor.constraint(equalTo: noteField.leadingAnchor, constant: 12),

            noteCounterLabel.trailingAnchor.constraint(equalTo: noteContainer.trailingAnchor, constant: -10),
            noteCounterLabel.bottomAnchor.constraint(equalTo: noteContainer.bottomAnchor, constant: -8),
            noteCounterLabel.leadingAnchor.constraint(equalTo: noteContainer.leadingAnchor, constant: 10),
        ])

        let initialNote = payload.note?.isEmpty == false ? (payload.note ?? "") : L(L10n.Profile.sendTokenDefaultNote)
        noteField.text = initialNote
        updateNotePlaceholder()
        updateNoteCounter()
    }

    private func configureBottomBar() {
        sendButton.layer.cornerRadius = 14
        sendButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        sendButton.setTitle(L(L10n.Profile.transferSend), for: .normal)
        sendButton.setTitleColor(.white, for: .normal)
        sendButton.addTarget(self, action: #selector(onSendTapped), for: .touchUpInside)
        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
    }

    override func applyTheme() {
        view.backgroundColor = .mezonPrimary
        headerView.backgroundColor = .mezonPrimary
        scrollView.backgroundColor = .mezonPrimary
        bottomBar.backgroundColor = .mezonPrimary

        backButton.tintColor = .mezonTextStrong
        titleLabel.text = L(L10n.Profile.transferFunds)
        titleLabel.textColor = .mezonTextStrong

        headingLabel.text = L(L10n.Profile.sendTokenHeading)
        headingLabel.textColor = .mezonTextStrong

        cardWalletView.applyTheme()
        cardWalletView.titleLeftLabel.text = L(L10n.Profile.sendTokenDebitAccount)
        cardWalletView.titleRightLabel.text = context.currentUser?.username
        cardWalletView.balanceLeftLabel.text = L(L10n.Profile.balance)

        recipientLabel.text = (payload.walletAddress?.isEmpty == false) ? L(L10n.Profile.sendTokenSendToAddress) : L(L10n.Profile.sendTokenSendTo)
        recipientLabel.textColor = .mezonTextPrimary
        recipientField.backgroundColor = .loginInputBg
        recipientField.layer.borderColor = UIColor.loginInputBorder.cgColor
        recipientValueLabel.textColor = .mezonTextStrong
        copyButton.tintColor = .mezonTextStrong
        recipientChevron.tintColor = .mezonTextStrong

        amountLabel.text = L(L10n.Profile.sendTokenToken)
        amountLabel.textColor = .mezonTextPrimary
        amountFieldContainer.backgroundColor = .loginInputBg
        amountFieldContainer.layer.borderColor = UIColor.loginInputBorder.cgColor
        amountField.textColor = .mezonTextStrong

        noteLabel.text = L(L10n.Profile.sendTokenNote)
        noteLabel.textColor = .mezonTextPrimary
        noteContainer.backgroundColor = .loginInputBg
        noteContainer.layer.borderColor = UIColor.loginInputBorder.cgColor
        noteField.textColor = .mezonTextStrong
        noteCounterLabel.textColor = .mezonTextMuted
        notePlaceholder.textColor = .mezonTextMuted

        sendButton.backgroundColor = UIColor(red: 94/255, green: 101/255, blue: 238/255, alpha: 1)

        updateRecipientDisplay()
        updateBalanceDisplay()
    }

    private func updateRecipientDisplay() {
        if let w = payload.walletAddress, !w.isEmpty {
            recipientValueLabel.text = w
            copyButton.isHidden = false
            recipientChevron.isHidden = true
        } else if let r = payload.receiverUserId, !r.isEmpty {
            let shown: String = {
                if let n = payload.receiverDisplayName, !n.isEmpty { return n }
                return context.account.postbox.read { tx in
                    guard let p = tx.getProfile(userId: r) else { return r }
                    if let d = p.displayName, !d.isEmpty { return d }
                    if !p.username.isEmpty { return p.username }
                    return r
                }
            }()
            recipientValueLabel.text = shown
            copyButton.isHidden = true
            recipientChevron.isHidden = payload.recipientLocked
        } else {
            recipientValueLabel.text = L(L10n.Profile.sendTokenSelectAccount)
            copyButton.isHidden = true
            recipientChevron.isHidden = false
        }
    }

    private func updateBalanceDisplay() {
        let balance = walletDetail?.balance
        let decimals = walletDetail?.decimals ?? 6
        let formatted = MmnMoneyFormat.formatBalanceToString(balance, decimals: decimals)
        cardWalletView.balanceRightLabel.text = "\(formatted) \(MmnMoneyFormat.currencySymbol)"
    }

    private func updateNotePlaceholder() {
        notePlaceholder.isHidden = !(noteField.text?.isEmpty ?? true)
    }

    private func updateNoteCounter() {
        let len = noteField.text?.count ?? 0
        noteCounterLabel.text = "\(len)/\(MmnMoneyFormat.noteMaxLength)"
    }

    private func setupKeyboardDismiss() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        scrollView.addGestureRecognizer(tap)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var v: UIView? = touch.view
        while let x = v {
            if x is UITextField || x is UITextView { return false }
            v = x.superview
        }
        return true
    }

    @objc private func keyboardFrameWillChange(_ notification: Notification) {
        guard view.window != nil,
              let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
              let curveValue = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else { return }
        let kb = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - kb.minY)
        bottomBarBottomConstraint?.constant = overlap > 0 ? -overlap : 0
        let options = UIView.AnimationOptions(rawValue: curveValue << 16)
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    private func loadWalletDetail() async {
        guard let id = context.currentUser?.id else { return }
        if let w = try? await MmnClient.shared.getAccountByUserId(id) {
            walletDetail = w
            updateBalanceDisplay()
        }
    }

    private func applyDeductedBalanceIfServerStale(previousBalance: String, sentInput: String) {
        guard let w = walletDetail,
              let scaled = MmnAmountScale.scaleToChainAmount(sentInput)
        else { return }
        guard w.balance == previousBalance else { return }
        let newB = MmnAmountScale.balanceAfterDeducting(wallet: w.balance, send: scaled)
        walletDetail = WalletDetail(
            address: w.address,
            balance: newB,
            nonce: w.nonce,
            decimals: w.decimals
        )
        updateBalanceDisplay()
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func copyAddressTapped() {
        guard let addr = payload.walletAddress, !addr.isEmpty else { return }
        UIPasteboard.general.string = addr
        Toast.success(L(L10n.Profile.sendTokenCopyAddressSuccess))
    }

    @objc private func onSendTapped() {
        guard !isSending else { return }

        let hasRecipient = (payload.walletAddress?.isEmpty == false) || (payload.receiverUserId?.isEmpty == false)
        if !hasRecipient {
            Toast.error(L(L10n.Profile.sendTokenErrSelectUser))
            return
        }
        if plainAmount <= 0 {
            Toast.error(L(L10n.Profile.sendTokenErrAmountZero))
            return
        }
        let walletInDong = walletInDongValue()
        if plainAmount > walletInDong {
            Toast.error(L(L10n.Profile.sendTokenErrExceedWallet))
            return
        }

        view.endEditing(true)
        let recipientShort = recipientShortDisplay()
        let amountFormatted = MmnMoneyFormat.formatTokenAmount(String(plainAmount)).display
        let message = String(format: L(L10n.Profile.sendTokenConfirmMessage),
                             amountFormatted, MmnMoneyFormat.currencySymbol, recipientShort)
        MezonConfirm.present(
            from: self,
            title: L(L10n.Profile.sendTokenConfirmTitle),
            content: message,
            confirmTitle: L(L10n.Profile.sendTokenConfirmAction),
            onConfirm: { [weak self] in self?.performSend() }
        )
    }

    private func recipientShortDisplay() -> String {
        if let w = payload.walletAddress, !w.isEmpty {
            if w.count <= 14 { return w }
            return "\(w.prefix(6))…\(w.suffix(4))"
        }
        if let n = payload.receiverDisplayName, !n.isEmpty {
            return n
        }
        return payload.receiverUserId ?? ""
    }

    private func walletInDongValue() -> Int64 {
        let str = MmnMoneyFormat.formatBalanceToString(walletDetail?.balance, decimals: walletDetail?.decimals ?? 6)
        return MmnMoneyFormat.plainAmount(from: str)
    }

    private func performSend() {
        setSending(true)
        let amountInput = String(plainAmount)
        let note = (noteField.text ?? "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let r = try await MmnTransferCoordinator.send(
                    context: context,
                    payload: payload,
                    amountInput: amountInput,
                    note: note
                )
                await MainActor.run { self.setSending(false) }
                if r.ok == true {
                    let beforeBalance = self.walletDetail?.balance
                    await self.loadWalletDetail()
                    await MainActor.run {
                        if let b = beforeBalance {
                            self.applyDeductedBalanceIfServerStale(previousBalance: b, sentInput: amountInput)
                        }
                        self.showSuccess(amount: amountInput, note: note)
                    }
                } else {
                    await MainActor.run { self.showFailure(message: r.error) }
                }
            } catch MmnTransferError.walletNotReady {
                await MainActor.run {
                    self.setSending(false)
                    self.showSessionExpired()
                }
            } catch let nsErr as NSError {
                await MainActor.run {
                    self.setSending(false)
                    if nsErr.code == 401 {
                        self.showSessionExpired()
                    } else {
                        self.showFailure(message: nsErr.localizedDescription)
                    }
                }
            }
        }
    }

    private func setSending(_ flag: Bool) {
        isSending = flag
        sendButton.isEnabled = !flag
        sendButton.alpha = flag ? 0.6 : 1
        if flag {
            sendButton.setTitle("", for: .normal)
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
            sendButton.setTitle(L(L10n.Profile.transferSend), for: .normal)
        }
    }

    private func showFailure(message: String?) {
        Toast.error(message ?? L(L10n.Profile.sendTokenErrSendFailed))
    }

    private func showSessionExpired() {
        MezonConfirm.present(
            from: self,
            title: L(L10n.Profile.sendTokenErrSessionExpired),
            content: L(L10n.Profile.sendTokenErrLoginAgain),
            confirmTitle: L(L10n.Common.confirm),
            showsCancelButton: false,
            onConfirm: { [weak self] in
                self?.context.logout()
            }
        )
    }

    private func showSuccess(amount: String, note: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        let timeStr = formatter.string(from: Date())
        let amountFormatted = MmnMoneyFormat.formatTokenAmount(amount).display
        let receiver = recipientShortDisplay()
        let vc = TransferSuccessViewController(
            context: context,
            amountDisplay: amountFormatted,
            receiver: receiver,
            note: note.isEmpty ? "—" : note,
            dateText: timeStr,
            onDone: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onSendNew: { [weak self] in
                self?.resetForm()
            }
        )
        vc.modalPresentationStyle = .overFullScreen
        vc.modalTransitionStyle = .crossDissolve
        present(vc, animated: true)
    }

    private func resetForm() {
        amountField.setFormattedAmount("0")
        noteField.text = L(L10n.Profile.sendTokenDefaultNote)
        updateNotePlaceholder()
        updateNoteCounter()
    }
}

extension WalletTransferViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard textView === noteField else { return true }
        let current = textView.text ?? ""
        guard let r = Range(range, in: current) else { return false }
        let new = current.replacingCharacters(in: r, with: text)
        return new.count <= MmnMoneyFormat.noteMaxLength
    }

    func textViewDidChange(_ textView: UITextView) {
        updateNotePlaceholder()
        updateNoteCounter()
    }
}

private struct TransferRecipientRow {
    var user: Mezon_Api_User
    var primaryText: String
    var avatarURL: String
}

private final class TransferRecipientPickerCell: UITableViewCell {

    static let reuseId = "TransferRecipientPickerCell"
    private let textAvatar = TextAvatarView(username: "", size: 34, fontSize: 12)
    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 17
        return iv
    }()

    private let titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 14, weight: .medium)
        lbl.numberOfLines = 1
        return lbl
    }()

    private var currentAvatarTask: URLSessionDataTask?
    private var currentAvatarKey: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .mezonSecondary
        contentView.backgroundColor = .mezonSecondary
        selectionStyle = .default
        textAvatar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textAvatar)
        textAvatar.addSubview(avatarImageView)
        contentView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            textAvatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            textAvatar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textAvatar.widthAnchor.constraint(equalToConstant: 34),
            textAvatar.heightAnchor.constraint(equalToConstant: 34),
            avatarImageView.topAnchor.constraint(equalTo: textAvatar.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: textAvatar.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: textAvatar.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: textAvatar.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: textAvatar.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(row: TransferRecipientRow) {
        titleLabel.text = row.primaryText
        titleLabel.textColor = .mezonTextPrimary
        cancelAvatarLoad()
        avatarImageView.image = nil

        if !row.avatarURL.isEmpty {
            let proxied = ImgproxyURL.create(from: row.avatarURL, width: 68, height: 68)
            if let url = URL(string: proxied) {
                loadAvatar(from: url, key: proxied, fallbackUsername: row.user.username)
                return
            }
        }
        textAvatar.configure(username: row.user.username, fontSize: 12)
    }

    private func cancelAvatarLoad() {
        currentAvatarTask?.cancel()
        currentAvatarTask = nil
        currentAvatarKey = nil
    }

    private func loadAvatar(from url: URL, key: String, fallbackUsername: String) {
        currentAvatarKey = key
        if let cached = ImageCache.shared.image(forKey: key) {
            avatarImageView.image = cached
            textAvatar.showImageMode()
            return
        }
        textAvatar.showSkeleton()
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self, self.currentAvatarKey == key else { return }
                if let data, let image = UIImage(data: data) {
                    ImageCache.shared.setImage(image, data: data, forKey: key)
                    self.avatarImageView.image = image
                    self.textAvatar.showImageMode()
                } else {
                    self.textAvatar.configure(username: fallbackUsername, fontSize: 12)
                }
            }
        }
        currentAvatarTask = task
        task.resume()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelAvatarLoad()
        avatarImageView.image = nil
        titleLabel.text = nil
    }
}

@MainActor
private final class TransferRecipientPickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {

    private let context: AccountContext
    private let onPick: (TransferRecipientRow) -> Void
    private var allRecipients: [TransferRecipientRow] = []
    private var filteredUsers: [TransferRecipientRow] = []
    private var searchDebounceWork: DispatchWorkItem?

    private let searchContainer = UIView()
    private let searchIcon = UIImageView()
    private let searchField = UITextField()
    private let listContainer = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var didFocusSearch = false

    init(context: AccountContext, onPick: @escaping (TransferRecipientRow) -> Void) {
        self.context = context
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .mezonPrimary
        title = L(L10n.Profile.sendTokenSendTo)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))

        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.backgroundColor = .incomingBubble
        searchContainer.layer.cornerRadius = 6
        searchContainer.layer.borderWidth = 0.3
        searchContainer.layer.borderColor = UIColor.mezonTextMuted.cgColor

        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        let mag = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))?
            .withRenderingMode(.alwaysTemplate)
        searchIcon.image = mag
        searchIcon.tintColor = .mezonTextPrimary
        searchIcon.contentMode = .scaleAspectFit

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.font = .systemFont(ofSize: 14)
        searchField.textColor = .mezonTextPrimary
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.returnKeyType = .search
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchFieldChanged), for: .editingChanged)
        searchField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.Profile.sendTokenSelectAccount),
            attributes: [.foregroundColor: UIColor.mezonTextMuted]
        )
        searchField.keyboardAppearance = traitCollection.userInterfaceStyle == .dark ? .dark : .light

        listContainer.translatesAutoresizingMaskIntoConstraints = false
        listContainer.backgroundColor = .mezonSecondary
        listContainer.layer.cornerRadius = 8
        listContainer.clipsToBounds = true

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .mezonSecondary
        tableView.separatorColor = UIColor.mezonBorder
        tableView.separatorInset = .zero
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(TransferRecipientPickerCell.self, forCellReuseIdentifier: TransferRecipientPickerCell.reuseId)
        tableView.rowHeight = 60
        tableView.estimatedRowHeight = 60
        tableView.keyboardDismissMode = .onDrag
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        view.addSubview(searchContainer)
        searchContainer.addSubview(searchIcon)
        searchContainer.addSubview(searchField)
        view.addSubview(listContainer)
        listContainer.addSubview(tableView)
        NSLayoutConstraint.activate([
            searchContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            searchContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            searchContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            searchContainer.heightAnchor.constraint(equalToConstant: 40),

            searchIcon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 10),
            searchIcon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 20),
            searchIcon.heightAnchor.constraint(equalToConstant: 20),

            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -10),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),

            listContainer.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 10),
            listContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            listContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            listContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),

            tableView.topAnchor.constraint(equalTo: listContainer.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
        ])
        Task { await loadRecipients() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didFocusSearch else { return }
        didFocusSearch = true
        let focus: () -> Void = { [weak self] in
            _ = self?.searchField.becomeFirstResponder()
        }
        if let tc = transitionCoordinator {
            tc.animate(alongsideTransition: nil) { _ in
                focus()
            }
        } else {
            DispatchQueue.main.async {
                focus()
            }
        }
    }

    private func refreshClanMembersIfNeeded(clanId: Int64, token: String) async throws {
        let res = try await context.account.network.listClanUsers(clanId: clanId, token: token)
        guard !res.clanUsers.isEmpty else { return }
        let members = res.clanUsers.map { ClanMemberRecord(from: $0) }
        context.account.postbox.write { tx in
            for clanUser in res.clanUsers {
                tx.updateProfile(ProfileRecord(from: clanUser))
            }
            tx.updateClanMembers(members, clanId: clanId)
        }
    }

    private func loadRecipients() async {
        guard let token = await context.getToken(), !token.isEmpty else { return }
        let selfId = context.currentUser?.id ?? ""
        let clanIds = context.account.postbox.read { tx in tx.getClans().map(\.id) }
        for clanId in clanIds {
            let isEmpty = context.account.postbox.read { tx in tx.getClanMembers(clanId: clanId).isEmpty }
            if isEmpty {
                try? await refreshClanMembersIfNeeded(clanId: clanId, token: token)
            }
        }
        let dmType = MezonConstants.ChannelType.dm.rawValue
        let clanAndDm: [TransferRecipientRow] = context.account.postbox.read { tx in
            var seen = Set<String>()
            var out: [TransferRecipientRow] = []
            func append(_ row: TransferRecipientRow) {
                let k = "\(row.user.id)"
                guard !seen.contains(k) else { return }
                seen.insert(k)
                out.append(row)
            }
            for clan in tx.getClans() {
                for m in tx.getClanMembers(clanId: clan.id) {
                    let profileAvatar = tx.getProfile(userId: "\(m.userId)")?.avatarUrl ?? ""
                    let avatar = !profileAvatar.isEmpty ? profileAvatar : m.clanAvatar
                    let u = Self.apiUser(fromClanMember: m)
                    let primary = m.username.isEmpty ? "\(m.userId)" : m.username
                    append(TransferRecipientRow(user: u, primaryText: primary, avatarURL: avatar))
                }
            }
            for clan in tx.getClans() {
                for ch in tx.getChannels(clanId: clan.id) where ch.type == dmType {
                    let proto = ch.toProto()
                    guard let u = Self.apiUser(fromDMChannel: ch, proto: proto) else { continue }
                    let name0 = proto.usernames.first ?? ""
                    let primary: String = {
                        if !name0.isEmpty { return name0 }
                        if !ch.label.isEmpty { return ch.label }
                        return "\(u.id)"
                    }()
                    let av = proto.avatars.first ?? ""
                    append(TransferRecipientRow(user: u, primaryText: primary, avatarURL: av))
                }
            }
            return out
        }
        var seen = Set(clanAndDm.map { "\($0.user.id)" })
        var merged = clanAndDm
        do {
            let res = try await context.account.network.listFriends(token: token, limit: 100, state: 0)
            for f in res.friends where f.state == 0 && f.hasUser {
                let u = f.user
                let k = "\(u.id)"
                guard !seen.contains(k) else { continue }
                seen.insert(k)
                let primary: String = {
                    if !u.displayName.isEmpty { return u.displayName }
                    if !u.username.isEmpty { return u.username }
                    return "\(u.id)"
                }()
                merged.append(TransferRecipientRow(user: u, primaryText: primary, avatarURL: u.avatarURL))
            }
        } catch {}
        merged = merged.filter { "\($0.user.id)" != selfId }
        allRecipients = merged
        filteredUsers = merged
        tableView.reloadData()
    }

    private static func apiUser(fromClanMember member: ClanMemberRecord) -> Mezon_Api_User {
        var u = Mezon_Api_User()
        u.id = member.userId
        u.username = member.username
        u.displayName = displayName(forClanMember: member)
        if let url = member.resolvedAvatarURL(fallbackProfileAvatar: nil) {
            u.avatarURL = url
        }
        u.online = member.isOnline
        return u
    }

    private static func displayName(forClanMember member: ClanMemberRecord) -> String {
        if !member.clanNick.isEmpty { return member.clanNick }
        if !member.displayName.isEmpty { return member.displayName }
        return member.username
    }

    private static func apiUser(fromDMChannel channel: ChannelRecord, proto: Mezon_Api_ChannelDescription) -> Mezon_Api_User? {
        guard let uid = proto.userIds.first else { return nil }
        var u = Mezon_Api_User()
        u.id = uid
        let uname = proto.usernames.first ?? ""
        u.username = uname
        u.displayName = channel.label.isEmpty ? uname : channel.label
        if let av = proto.avatars.first, !av.isEmpty {
            u.avatarURL = av
        }
        return u
    }

    private func applyFilter(searchText: String) {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            filteredUsers = allRecipients
            tableView.reloadData()
            return
        }
        let search = trimmed.lowercased()
        let searchNorm = Self.normalizeSearch(search)
        struct Scored {
            let row: TransferRecipientRow
            let score: Int
            let len: Int
        }
        var scored: [Scored] = []
        scored.reserveCapacity(allRecipients.count)
        for row in allRecipients {
            let username = row.primaryText.lowercased()
            let usernameNorm = Self.normalizeSearch(username)
            let s = Self.matchScore(usernameLower: username, usernameNorm: usernameNorm, search: search, searchNorm: searchNorm)
            if s > 0 {
                scored.append(Scored(row: row, score: s, len: username.count))
            }
        }
        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.len < b.len
        }
        filteredUsers = scored.map(\.row)
        tableView.reloadData()
    }

    private static func normalizeSearch(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private static func matchScore(usernameLower: String, usernameNorm: String, search: String, searchNorm: String) -> Int {
        if usernameLower == search { return 1000 }
        if usernameLower.hasPrefix(search) { return 900 }
        if usernameNorm == searchNorm { return 800 }
        if usernameNorm.hasPrefix(searchNorm) { return 700 }
        if usernameLower.contains(search) { return 500 }
        if usernameNorm.contains(searchNorm) { return 400 }
        return 0
    }

    @objc private func searchFieldChanged() {
        let text = searchField.text ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            searchDebounceWork?.cancel()
            applyFilter(searchText: text)
            return
        }
        searchDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.applyFilter(searchText: text)
        }
        searchDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredUsers.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TransferRecipientPickerCell.reuseId, for: indexPath) as! TransferRecipientPickerCell
        cell.configure(row: filteredUsers[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onPick(filteredUsers[indexPath.row])
        dismiss(animated: true)
    }

    @objc private func cancelTapped() { dismiss(animated: true) }
}

private final class TappableContainer: UIView {
    var onTap: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handle))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func handle() { onTap?() }
}

final class WalletCardView: UIView {
    let titleLeftLabel = UILabel()
    let titleRightLabel = UILabel()
    let balanceLeftLabel = UILabel()
    let balanceRightLabel = UILabel()
    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 12
        layer.borderWidth = 0.5
        clipsToBounds = true
        layer.insertSublayer(gradient, at: 0)
        let row1 = UIStackView(arrangedSubviews: [titleLeftLabel, titleRightLabel])
        row1.axis = .horizontal
        row1.distribution = .equalSpacing
        let row2 = UIStackView(arrangedSubviews: [balanceLeftLabel, balanceRightLabel])
        row2.axis = .horizontal
        row2.distribution = .equalSpacing
        row2.alignment = .lastBaseline
        let stack = UIStackView(arrangedSubviews: [row1, row2])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
        titleLeftLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleRightLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        balanceLeftLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        balanceRightLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLeftLabel.numberOfLines = 1
        titleRightLabel.numberOfLines = 1
        titleRightLabel.lineBreakMode = .byTruncatingMiddle
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyTheme() {
        let c1 = UIColor.mezonSecondaryBackground
        let c2 = UIColor.theme.secondaryLight
        gradient.colors = [c2.cgColor, c1.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer.borderColor = UIColor.mezonBorder.cgColor
        titleLeftLabel.textColor = .mezonTextPrimary
        titleRightLabel.textColor = .mezonTextPrimary
        balanceLeftLabel.textColor = .mezonTextPrimary
        balanceRightLabel.textColor = .mezonTextStrong
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}
