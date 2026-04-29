import CoreLocation
import UIKit

final class CreateThreadFormViewController: UIViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let parentChannelId: Int64
    private let parentCategoryId: Int64
    private let parentChannelLabel: String
    private let composerParentChannel: Mezon_Api_ChannelDescription
    private let onComplete: ((Result<Mezon_Api_ChannelDescription, Error>) -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let contextLabel = UILabel()
    private let nameCaptionLabel = UILabel()

    private let nameContainer = UIView()
    private let nameField: UITextField = {
        let t = UITextField()
        t.borderStyle = .none
        t.font = .systemFont(ofSize: 16.sf)
        t.autocorrectionType = .no
        t.returnKeyType = .done
        t.translatesAutoresizingMaskIntoConstraints = false
        return t
    }()

    private let visibilityCard = UIView()
    private let visibilityHeadlineLabel = UILabel()
    private let visibilityDetailLabel = UILabel()
    private let visibilitySwitch = UISwitch()
    private let visibilityRow = UIStackView()
    private var threadIsPrivate = false

    private let composerChrome = UIView()
    private let composerTopHairline = UIView()
    private var composerHeightConstraint: NSLayoutConstraint!
    private var composerPinConstraint: NSLayoutConstraint!

    private var pendingThreadSubmission = false

    private lazy var emojiPicker: ChatEmojiPickerPresenter = {
        let p = ChatEmojiPickerPresenter(sendInput: sendInputVC)
        p.onRequestRelayout = { [weak self] _ in
            self?.view.layoutIfNeeded()
        }
        return p
    }()

    private lazy var advancePanelView: AdvancedFunctionPanelView = {
        let v = AdvancedFunctionPanelView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        v.onRequestDismiss = { [weak self] in
            guard let self else { return }
            self.sendInputVC.markAdvancePanelDismissedByHost()
            self.handleAdvancePanelToggle(visible: false, collapsedHeight: 0)
            self.sendInputVC.focusTextInput()
        }
        v.onActionTapped = { [weak self] item in
            self?.handleAdvanceAction(item)
        }
        v.onHeightChanged = { [weak self] newHeight in
            self?.updateAdvancePanelOverlayHeight(newHeight)
        }
        return v
    }()

    private var advancePanelHeightConstraint: NSLayoutConstraint?
    private var advancePanelBottomConstraint: NSLayoutConstraint?
    private var advancePanelCollapsedHeight: CGFloat = 0

    private let locationManager = CLLocationManager()
    private var locationCompletion: ((CLLocationCoordinate2D?) -> Void)?

    private lazy var sendInputVC: SendMessageInputViewController = {
        let vc = SendMessageInputViewController(
            placeholder: L(L10n.ChannelMessages.writeMessage),
            channel: composerParentChannel,
            clanId: clanId,
            context: context
        )
        vc.hidesAdvanceComposerButton = true
        vc.suppressStoredComposerDraftRestoreOnLoad = true
        vc.skipsPersistingComposerDraftOnLifecycleEnd = true
        vc.onHeightChanged = { [weak self] h in
            guard let self else { return }
            self.composerHeightConstraint.constant = 1 / UIScreen.main.scale + max(52.swh, h)
            self.view.layoutIfNeeded()
        }
        return vc
    }()

    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    init(
        context: AccountContext,
        clanId: Int64,
        parentChannelId: Int64,
        parentCategoryId: Int64,
        parentChannelLabel: String,
        composerParentChannel: Mezon_Api_ChannelDescription,
        onComplete: ((Result<Mezon_Api_ChannelDescription, Error>) -> Void)? = nil
    ) {
        self.context = context
        self.clanId = clanId
        self.parentChannelId = parentChannelId
        self.parentCategoryId = parentCategoryId
        self.parentChannelLabel = parentChannelLabel
        self.composerParentChannel = composerParentChannel
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        contextLabel.font = .systemFont(ofSize: 13.sf)
        contextLabel.numberOfLines = 2
        nameCaptionLabel.font = .systemFont(ofSize: 13.sf, weight: .semibold)

        visibilityHeadlineLabel.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        visibilityHeadlineLabel.numberOfLines = 2
        visibilityDetailLabel.font = .systemFont(ofSize: 13.sf)
        visibilityDetailLabel.numberOfLines = 0

        navigationItem.title = L(L10n.ThreadList.createThreadTitle)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L(L10n.ThreadList.createThreadCancel),
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L(L10n.ThreadList.createThreadSubmit),
            style: .done,
            target: self,
            action: #selector(submitTapped)
        )

        contextLabel.text = String(format: L(L10n.ThreadList.createThreadInChannel), parentChannelLabel)
        nameCaptionLabel.text = L(L10n.ThreadList.createThreadNameLabel)

        nameField.delegate = self

        visibilitySwitch.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true

        contentStack.axis = .vertical
        contentStack.spacing = 18.sh
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        nameContainer.layer.cornerRadius = 8
        nameContainer.translatesAutoresizingMaskIntoConstraints = false
        nameContainer.addSubview(nameField)

        visibilityCard.translatesAutoresizingMaskIntoConstraints = false
        visibilityCard.layer.cornerRadius = 12
        visibilityCard.clipsToBounds = true

        let textColumn = UIStackView(arrangedSubviews: [visibilityHeadlineLabel, visibilityDetailLabel])
        textColumn.axis = .vertical
        textColumn.spacing = 4.sh
        textColumn.translatesAutoresizingMaskIntoConstraints = false

        visibilityRow.axis = .horizontal
        visibilityRow.alignment = .center
        visibilityRow.spacing = 12.sw
        visibilityRow.translatesAutoresizingMaskIntoConstraints = false
        visibilityRow.addArrangedSubview(textColumn)
        visibilityRow.addArrangedSubview(visibilitySwitch)
        visibilitySwitch.setContentHuggingPriority(.required, for: .horizontal)
        visibilitySwitch.addTarget(self, action: #selector(visibilitySwitchChanged(_:)), for: .valueChanged)

        visibilityCard.addSubview(visibilityRow)

        composerChrome.translatesAutoresizingMaskIntoConstraints = false
        composerChrome.clipsToBounds = true
        composerTopHairline.translatesAutoresizingMaskIntoConstraints = false

        composerHeightConstraint = composerChrome.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale + 56.swh)
        if #available(iOS 15.0, *) {
            composerPinConstraint = composerChrome.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        } else {
            composerPinConstraint = composerChrome.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        }

        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        contentStack.addArrangedSubview(contextLabel)
        contentStack.addArrangedSubview(nameCaptionLabel)
        contentStack.addArrangedSubview(nameContainer)
        contentStack.addArrangedSubview(visibilityCard)

        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)
        view.addSubview(composerChrome)
        composerChrome.addSubview(composerTopHairline)
        view.addSubview(activityIndicator)

        view.addSubview(advancePanelView)
        let advH = advancePanelView.heightAnchor.constraint(equalToConstant: 0)
        advancePanelHeightConstraint = advH
        let advBottom = advancePanelView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        advancePanelBottomConstraint = advBottom
        NSLayoutConstraint.activate([
            advancePanelView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            advancePanelView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            advH,
            advBottom,
        ])

        addChild(sendInputVC)
        composerChrome.addSubview(sendInputVC.view)
        sendInputVC.didMove(toParent: self)
        sendInputVC.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            scrollView.bottomAnchor.constraint(equalTo: composerChrome.topAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16.sh),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20.sh),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            nameField.leadingAnchor.constraint(equalTo: nameContainer.leadingAnchor, constant: 12.sw),
            nameField.trailingAnchor.constraint(equalTo: nameContainer.trailingAnchor, constant: -12.sw),
            nameField.topAnchor.constraint(equalTo: nameContainer.topAnchor, constant: 12.sh),
            nameField.bottomAnchor.constraint(equalTo: nameContainer.bottomAnchor, constant: -12.sh),

            visibilityRow.leadingAnchor.constraint(equalTo: visibilityCard.leadingAnchor, constant: 14.sw),
            visibilityRow.trailingAnchor.constraint(equalTo: visibilityCard.trailingAnchor, constant: -14.sw),
            visibilityRow.topAnchor.constraint(equalTo: visibilityCard.topAnchor, constant: 14.sh),
            visibilityRow.bottomAnchor.constraint(equalTo: visibilityCard.bottomAnchor, constant: -14.sh),

            composerChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composerChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composerPinConstraint,
            composerHeightConstraint,

            composerTopHairline.leadingAnchor.constraint(equalTo: composerChrome.leadingAnchor),
            composerTopHairline.trailingAnchor.constraint(equalTo: composerChrome.trailingAnchor),
            composerTopHairline.topAnchor.constraint(equalTo: composerChrome.topAnchor),
            composerTopHairline.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            sendInputVC.view.leadingAnchor.constraint(equalTo: composerChrome.leadingAnchor),
            sendInputVC.view.trailingAnchor.constraint(equalTo: composerChrome.trailingAnchor),
            sendInputVC.view.topAnchor.constraint(equalTo: composerTopHairline.bottomAnchor),
            sendInputVC.view.bottomAnchor.constraint(equalTo: composerChrome.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        emojiPicker.install(in: view, engine: context.engine)

        view.bringSubviewToFront(scrollView)
        view.bringSubviewToFront(composerChrome)
        emojiPicker.bringToFront()
        view.bringSubviewToFront(advancePanelView)
        view.bringSubviewToFront(activityIndicator)

        refreshVisibilityLabels()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeChanged),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
        if #available(iOS 15.0, *) {
        } else {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardFrameWillChange(_:)),
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: nil
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(formKeyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(formKeyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )

        applyTheme()

        sendInputVC.onToggleEmojiPicker = { [weak self] visible, collapsedH in
            self?.emojiPicker.setVisible(visible, collapsedHeight: collapsedH)
        }
        sendInputVC.onToggleAdvancePanel = { [weak self] visible, collapsedH in
            self?.handleAdvancePanelToggle(visible: visible, collapsedHeight: collapsedH)
        }

        sendInputVC.primarySendActionOverride = { [weak self] in
            self?.performCreateThreadSubmission()
        }
        sendInputVC.alwaysShowAttachToolbarWhileTyping = true
    }

    @objc private func keyboardFrameWillChange(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.intersection(converted).height)
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
        let curveNumber = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 7
        let curveOptions = UIView.AnimationOptions(rawValue: UInt(curveNumber) << 16)
        func applyLift() {
            self.composerPinConstraint.constant = overlap > 0.5 ? -overlap : 0
            self.view.layoutIfNeeded()
        }
        if duration > 0.01 {
            UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, curveOptions]) {
                applyLift()
            }
        } else {
            applyLift()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sendInputVC.setClanAnonymousPolicy(preventAnonymous: clanPreventsAnonymous())
        sendInputVC.refreshAnonymousUI()
        rebuildAdvancePanelActions()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let inset = view.safeAreaInsets.bottom
        emojiPicker.updateBottomInset(inset)
        advancePanelBottomConstraint?.constant = -inset
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sendInputVC.view.layoutIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        if #available(iOS 15.0, *) {
        } else {
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        }
    }

    @objc private func formKeyboardWillShow(_ notification: Notification) {
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
        let curveNumber = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 7
        let curveOptions = UIView.AnimationOptions(rawValue: UInt(curveNumber) << 16)
        switch emojiPicker.handleKeyboardWillShow() {
        case .searchAbsorbed:
            break
        case .dismissedForKeyboard:
            if duration > 0.01 {
                UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, curveOptions]) {
                    self.view.layoutIfNeeded()
                }
            }
        case .unaffected:
            break
        }
    }

    @objc private func formKeyboardWillHide(_ notification: Notification) {
        emojiPicker.handleKeyboardWillHide()
        if advancePanelCollapsedHeight > 0 && !advancePanelView.isHidden {
            advancePanelView.applySnapCollapsed()
        }
    }

    @objc private func visibilitySwitchChanged(_ sender: UISwitch) {
        threadIsPrivate = sender.isOn
        refreshVisibilityLabels()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func themeChanged() {
        applyTheme()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            refreshVisibilityLabels()
        }
    }

    private func refreshVisibilityLabels() {
        if threadIsPrivate {
            visibilityHeadlineLabel.text = L(L10n.ThreadList.createThreadPrivateTitle)
            visibilityDetailLabel.text = L(L10n.ThreadList.createThreadPrivateSubtitle)
        } else {
            visibilityHeadlineLabel.text = L(L10n.ThreadList.createThreadPublicTitle)
            visibilityDetailLabel.text = L(L10n.ThreadList.createThreadPublicSubtitle)
        }
        visibilitySwitch.setOn(threadIsPrivate, animated: false)
    }

    private func applyTheme() {
        let t = UIColor.theme
        view.backgroundColor = t.primary
        scrollView.backgroundColor = t.primary
        composerChrome.backgroundColor = t.secondary
        composerTopHairline.backgroundColor = t.border
        visibilityCard.backgroundColor = t.secondary
        nameContainer.backgroundColor = t.secondary
        contextLabel.textColor = t.textDisabled
        nameCaptionLabel.textColor = t.textStrong
        nameField.textColor = t.textStrong
        nameField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.ThreadList.createThreadNamePlaceholder),
            attributes: [.foregroundColor: t.textDisabled]
        )
        visibilityHeadlineLabel.textColor = t.textStrong
        visibilityDetailLabel.textColor = t.textDisabled
        activityIndicator.color = t.textStrong
        advancePanelView.applyTheme()
        refreshVisibilityLabels()

        guard let nav = navigationController else { return }
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = t.secondary
        appearance.titleTextAttributes = [.foregroundColor: t.textStrong]
        appearance.shadowColor = t.border.withAlphaComponent(0.35)
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance
        nav.navigationBar.tintColor = t.textStrong
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func submitTapped() {
        performCreateThreadSubmission()
    }

    private func performCreateThreadSubmission() {
        guard !pendingThreadSubmission else { return }
        let trimmed = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1, trimmed.count <= 64 else {
            let msg = L(L10n.ThreadList.createThreadNameInvalid)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                Toast.error(msg)
                let r = self.nameContainer.convert(self.nameContainer.bounds, to: self.scrollView)
                self.scrollView.scrollRectToVisible(r.insetBy(dx: 0, dy: -24), animated: true)
                self.nameField.becomeFirstResponder()
                let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
                anim.values = [0, -8, 8, -6, 6, -3, 3, 0]
                anim.duration = 0.45
                self.nameContainer.layer.add(anim, forKey: "shake")
            }
            return
        }

        pendingThreadSubmission = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        navigationItem.leftBarButtonItem?.isEnabled = false
        activityIndicator.startAnimating()

        Task { @MainActor in
            guard let token = await context.getToken() else {
                pendingThreadSubmission = false
                activityIndicator.stopAnimating()
                navigationItem.rightBarButtonItem?.isEnabled = true
                navigationItem.leftBarButtonItem?.isEnabled = true
                Toast.error(L(L10n.ThreadList.createThreadFailed))
                return
            }
            do {
                let created = try await context.account.network.createThreadChannelDesc(
                    clanId: clanId,
                    parentChannelId: parentChannelId,
                    categoryId: parentCategoryId,
                    channelLabel: trimmed,
                    channelPrivate: threadIsPrivate ? 1 : 0,
                    token: token
                )
                sendInputVC.syncStoredDraftIdentity(
                    channel: created,
                    topicId: 0,
                    migrateDraftToNewChannelIdentity: true,
                    preserveComposerContentsDuringMigration: true
                )
                if sendInputVC.hasComposerSendPayload() {
                    sendInputVC.onSent = { [weak self] in
                        guard let self else { return }
                        self.sendInputVC.onSent = nil
                        self.sendInputVC.onError = nil
                        self.pendingThreadSubmission = false
                        self.activityIndicator.stopAnimating()
                        self.navigationItem.rightBarButtonItem?.isEnabled = true
                        self.navigationItem.leftBarButtonItem?.isEnabled = true
                        self.finishCreateSuccess(created: created)
                    }
                    sendInputVC.onError = { [weak self] message in
                        guard let self else { return }
                        self.sendInputVC.onSent = nil
                        self.sendInputVC.onError = nil
                        self.pendingThreadSubmission = false
                        self.activityIndicator.stopAnimating()
                        self.navigationItem.rightBarButtonItem?.isEnabled = true
                        self.navigationItem.leftBarButtonItem?.isEnabled = true
                        let trimmedMsg = message.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedMsg.isEmpty {
                            Toast.error(trimmedMsg)
                        }
                        self.finishCreateSuccess(created: created)
                    }
                    sendInputVC.primarySendActionOverride = nil
                    sendInputVC.skipOptimisticPendingMessageOnSend = true
                    sendInputVC.send()
                } else {
                    pendingThreadSubmission = false
                    activityIndicator.stopAnimating()
                    navigationItem.rightBarButtonItem?.isEnabled = true
                    navigationItem.leftBarButtonItem?.isEnabled = true
                    finishCreateSuccess(created: created)
                }
            } catch {
                pendingThreadSubmission = false
                activityIndicator.stopAnimating()
                navigationItem.rightBarButtonItem?.isEnabled = true
                navigationItem.leftBarButtonItem?.isEnabled = true
                Toast.error(L(L10n.ThreadList.createThreadFailed))
            }
        }
    }

    private func finishCreateSuccess(created: Mezon_Api_ChannelDescription) {
        let cb = onComplete
        dismiss(animated: true) {
            cb?(.success(created))
        }
    }

    private func clanPreventsAnonymous() -> Bool {
        guard clanId != 0 else { return true }
        let rec = context.account.postbox.read { tx in tx.getClan(id: clanId) }
        return rec?.preventsAnonymousMessages ?? false
    }

    private func rebuildAdvancePanelActions() {
        let prevent = clanPreventsAnonymous()
        let on = AnonymousMessageStore.isEnabled(clanId: clanId)
        let items = AdvancedFunctionPanelView.defaultActionItems(
            anonymousOn: on,
            includeAnonymous: clanId != 0 && !prevent,
            includeCreateThread: false
        )
        advancePanelView.setActions(items)
    }

    private func handleAdvancePanelToggle(visible: Bool, collapsedHeight: CGFloat) {
        if visible {
            rebuildAdvancePanelActions()
            emojiPicker.dismissSilently(markAsJustDismissed: false)
            let screenH = UIScreen.main.bounds.height
            let expandedH = max(screenH * 0.85, collapsedHeight + 200)
            advancePanelView.collapsedHeight = collapsedHeight
            advancePanelView.expandedHeight = expandedH
            advancePanelView.resetToCollapsed()
            advancePanelCollapsedHeight = collapsedHeight
            advancePanelHeightConstraint?.constant = collapsedHeight
            advancePanelView.isHidden = false
            advancePanelView.applyTheme()
        } else {
            advancePanelCollapsedHeight = 0
            advancePanelHeightConstraint?.constant = 0
            advancePanelView.isHidden = true
            advancePanelView.resetToCollapsed()
        }
        view.layoutIfNeeded()
        if visible {
            advancePanelView.transform = CGAffineTransform(translationX: 0, y: 30)
            advancePanelView.alpha = 0
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.8, options: .curveEaseOut) {
                self.advancePanelView.transform = .identity
                self.advancePanelView.alpha = 1
            }
        } else {
            advancePanelView.transform = .identity
            advancePanelView.alpha = 1
        }
    }

    private func updateAdvancePanelOverlayHeight(_ newHeight: CGFloat) {
        advancePanelHeightConstraint?.constant = newHeight
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut]) {
            self.view.layoutIfNeeded()
        }
    }

    private func navigateToTransferFundsForThreadForm() {
        view.endEditing(true)
        sendInputVC.markAdvancePanelDismissedByHost()
        handleAdvancePanelToggle(visible: false, collapsedHeight: 0)
        let payload = TransferQRPayload(
            receiverUserId: nil,
            walletAddress: nil,
            suggestedAmount: nil,
            note: nil,
            extraAttribute: nil,
            receiverDisplayName: nil
        )
        let vc = WalletTransferViewController(context: context, payload: payload)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func presentFromTopMost(_ vc: UIViewController, animated: Bool = true) {
        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(vc, animated: animated)
    }

    private func handleAdvanceAction(_ item: AdvancedFunctionItem) {
        switch item.id {
        case "pickFiles":
            sendInputVC.openFilePicker()
        case "location":
            guard !AnonymousMessageStore.isEnabled(clanId: clanId) else { return }
            handleSendLocationForThreadForm()
        case "buzz":
            let buzzVC = BuzzMessageViewController()
            buzzVC.onSend = { [weak self] text in
                guard let self else { return }
                self.sendInputVC.sendBuzzMessage(text: text)
                DispatchQueue.main.async { self.sendInputVC.focusTextInput() }
            }
            presentFromTopMost(buzzVC)
        case "anonymous":
            guard clanId != 0, !clanPreventsAnonymous() else { return }
            _ = AnonymousMessageStore.toggle(clanId: clanId)
            sendInputVC.refreshAnonymousUI()
            rebuildAdvancePanelActions()
            DispatchQueue.main.async { [weak self] in self?.sendInputVC.focusTextInput() }
        case "transfer_funds":
            navigateToTransferFundsForThreadForm()
        default:
            Toast.comingSoonLine(item.label.replacingOccurrences(of: "\n", with: " "))
        }
    }

    private func handleSendLocationForThreadForm() {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        switch status {
        case .notDetermined:
            locationManager.delegate = self
            locationCompletion = { [weak self] coord in
                guard let self, let coord else { return }
                self.showLocationConfirmForThreadForm(coordinate: coord)
            }
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            fetchLocationAndShowConfirmForThreadForm()
        case .denied, .restricted:
            showLocationPermissionDeniedAlertForThreadForm()
        @unknown default:
            break
        }
    }

    private func fetchLocationAndShowConfirmForThreadForm() {
        locationManager.delegate = self
        locationCompletion = { [weak self] coord in
            guard let self, let coord else { return }
            self.showLocationConfirmForThreadForm(coordinate: coord)
        }
        locationManager.requestLocation()
    }

    private func showLocationConfirmForThreadForm(coordinate: CLLocationCoordinate2D) {
        let label = parentChannelLabel.isEmpty ? "this channel" : parentChannelLabel
        let confirmVC = ShareLocationConfirmViewController(coordinate: coordinate, channelLabel: label)
        confirmVC.onSend = { [weak self] lat, lng in
            guard let self else { return }
            self.sendInputVC.sendLocation(latitude: lat, longitude: lng)
            DispatchQueue.main.async { self.sendInputVC.focusTextInput() }
        }
        presentFromTopMost(confirmVC)
    }

    private func showLocationPermissionDeniedAlertForThreadForm() {
        let alert = UIAlertController(
            title: "Location Permission",
            message: "Mezon needs access to your location to share it. Please enable location access in Settings.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        presentFromTopMost(alert)
    }
}

extension CreateThreadFormViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        manager.delegate = nil
        let completion = locationCompletion
        locationCompletion = nil
        completion?(locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        manager.delegate = nil
        let completion = locationCompletion
        locationCompletion = nil
        completion?(nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = manager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        guard status != .notDetermined else { return }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        } else {
            manager.delegate = nil
            let completion = locationCompletion
            locationCompletion = nil
            completion?(nil)
            showLocationPermissionDeniedAlertForThreadForm()
        }
    }
}

extension CreateThreadFormViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        let next =
            ((textField.text ?? "") as NSString).replacingCharacters(in: range, with: string) as String
        return next.count <= 64
    }
}
