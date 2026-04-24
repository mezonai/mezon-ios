import AsyncDisplayKit

private struct AddFriendByUsernameState {
    var query: String
    var isSending: Bool
    var currentUsername: String
}

private struct AddFriendByUsernameInteraction {
    let onBackTapped: () -> Void
    let onQueryChanged: (String) -> Void
    let onSubmit: () -> Void
}

final class AddFriendByUsernameViewController: ViewController {
    private let context: AccountContext
    private let needsReloadPipe = ValuePipe<Void>()

    private var query: String = ""
    private var isSending: Bool = false
    private var friendByUsername: [String: Mezon_Api_Friend] = [:]
    private var isNodeReady = false
    private var didPlayAppearAnimation = false

    private var addFriendNode: AddFriendByUsernameContainerNode { displayNode as! AddFriendByUsernameContainerNode }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let interaction = AddFriendByUsernameInteraction(
            onBackTapped: { [weak self] in
                self?.closeWithZoomAnimation()
            },
            onQueryChanged: { [weak self] text in
                self?.setQuery(text)
            },
            onSubmit: { [weak self] in
                self?.submitAddFriend()
            }
        )
        displayNode = AddFriendByUsernameContainerNode(signal: stateSignal(), interaction: interaction)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playAppearAnimationIfNeeded()
        if !isNodeReady {
            isNodeReady = true
            addFriendNode.focusInputWithDelay()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleThemeChange() {
        guard isNodeLoaded else { return }
        addFriendNode.applyTheme()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let viewSafeTop = isViewLoaded ? view.safeAreaInsets.top : 0
        let safeTop = max(layout.safeInsets.top, layout.statusBarHeight ?? 0, viewSafeTop)
        addFriendNode.updateLayout(
            size: layout.size,
            safeTop: safeTop,
            bottomInset: layout.intrinsicInsets.bottom,
            transition: transition
        )
    }

    private func setQuery(_ text: String) {
        query = text
        needsReloadPipe.putNext(())
    }

    private func setIsSending(_ value: Bool) {
        isSending = value
        needsReloadPipe.putNext(())
    }

    private func playAppearAnimationIfNeeded() {
        guard !didPlayAppearAnimation else { return }
        didPlayAppearAnimation = true
        let targetView = addFriendNode.view
        targetView.alpha = 0
        targetView.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            options: [.curveEaseOut],
            animations: {
                targetView.alpha = 1
                targetView.transform = .identity
            }
        )
    }

    private func closeWithZoomAnimation() {
        let targetView = addFriendNode.view
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseIn],
            animations: {
                targetView.alpha = 0
                targetView.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            },
            completion: { [weak self] _ in
                guard let self else { return }
                if let nav = self.navigationController as? NavigationController,
                   nav.viewControllers.contains(where: { $0 === self }) {
                    _ = nav.popViewController(animated: false)
                } else {
                    self.dismiss()
                }
            }
        )
    }

    private var currentState: AddFriendByUsernameState {
        AddFriendByUsernameState(
            query: query,
            isSending: isSending,
            currentUsername: context.currentUser?.username ?? ""
        )
    }

    private func stateSignal() -> Signal<AddFriendByUsernameState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            subscriber.putNext(self.currentState)
            return (self.needsReloadPipe.signal()
                |> map { [weak self] _ in
                    self?.currentState ?? AddFriendByUsernameState(query: "", isSending: false, currentUsername: "")
                }
                |> deliverOnMainQueue
            ).start(next: { subscriber.putNext($0) })
        }
    }

    private func submitAddFriend() {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !isSending else { return }
        setIsSending(true)

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.setIsSending(false) }

            guard let token = await self.context.getToken() else { return }
            let myUsername = self.context.currentUser?.username ?? ""

            if !myUsername.isEmpty, normalized.caseInsensitiveCompare(myUsername) == .orderedSame {
                Toast.error(L(L10n.FriendRequest.toastSelfAddError), title: "")
                return
            }

            await self.ensureFriendLookup(token: token)
            if let existing = self.friendByUsername[normalized.lowercased()] {
                switch existing.state {
                case EStateFriend.block.rawValue:
                    Toast.error(L(L10n.FriendRequest.toastBlockedError), title: "")
                    return
                case EStateFriend.friend.rawValue:
                    Toast.error(L(L10n.FriendRequest.toastAlreadyFriend), title: "")
                    return
                case EStateFriend.otherPending.rawValue:
                    Toast.error(L(L10n.FriendRequest.toastWaitAccept), title: "")
                    return
                case EStateFriend.myPending.rawValue:
                    Toast.error(L(L10n.FriendRequest.toastIncomingReq), title: "")
                    return
                default:
                    break
                }
            }

            do {
                try await self.context.account.network.addFriends(usernames: [normalized], token: token)
                self.query = ""
                self.friendByUsername.removeAll()
                self.needsReloadPipe.putNext(())
                await self.context.engine.friendsData.refreshFromNetwork(token: token)
                Toast.success(L(L10n.FriendRequest.toastSendSuccess))
            } catch {
                Toast.error(L(L10n.FriendRequest.toastSelfAddError), title: "")
            }
        }
    }

    @MainActor
    private func ensureFriendLookup(token: String) async {
        var map = context.engine.friendsData.lookupByUsername()
        if map.isEmpty {
            await context.engine.friendsData.refreshFromNetwork(token: token)
            map = context.engine.friendsData.lookupByUsername()
        }
        friendByUsername = map
    }
}

private final class AddFriendByUsernameContainerNode: ASDisplayNode, ASEditableTextNodeDelegate {
    private let interaction: AddFriendByUsernameInteraction
    private let disposables = DisposableSet()

    private lazy var gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.startPoint = CGPoint(x: 0.5, y: 0)
        gl.endPoint = CGPoint(x: 0.5, y: 1)
        return gl
    }()

    private let backButton = ASButtonNode()
    private let titleNode = ASTextNode()
    private let questionNode = ASTextNode()
    private let inputBackgroundNode = ASDisplayNode()
    private let inputNode = EditableTextNode()
    private let hintNode = ASTextNode()
    private let submitButton = ASButtonNode()

    private var state = AddFriendByUsernameState(query: "", isSending: false, currentUsername: "")
    private var validLayout: (size: CGSize, safeTop: CGFloat, bottomInset: CGFloat)?

    init(signal: Signal<AddFriendByUsernameState, NoError>, interaction: AddFriendByUsernameInteraction) {
        self.interaction = interaction
        super.init()

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                self.state = newState
                self.updateStateUI()
            })
        )
    }

    deinit { disposables.dispose() }

    override func didLoad() {
        super.didLoad()

        layer.addSublayer(gradientLayer)

        addSubnode(backButton)
        addSubnode(titleNode)
        addSubnode(questionNode)
        addSubnode(inputBackgroundNode)
        addSubnode(inputNode)
        addSubnode(hintNode)
        addSubnode(submitButton)

        let chevronImg = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.sf, weight: .semibold)
        )?.withRenderingMode(.alwaysTemplate)
        backButton.setImage(chevronImg, for: .normal)
        backButton.addTarget(self, action: #selector(backTapped), forControlEvents: .touchUpInside)

        inputNode.delegate = self
        inputNode.typingAttributes = [
            NSAttributedString.Key.font.rawValue: UIFont.systemFont(ofSize: 14.sf),
            NSAttributedString.Key.foregroundColor.rawValue: UIColor.theme.textStrong
        ]
        inputNode.textContainerInset = UIEdgeInsets(top: 12.sh, left: 12.sw, bottom: 12.sh, right: 12.sw)
        inputNode.autocapitalizationType = .none
        inputNode.autocorrectionType = .no
        inputNode.keyboardType = .default
        inputNode.returnKeyType = .done
        inputNode.enablesReturnKeyAutomatically = true

        submitButton.cornerRadius = 24.swh
        submitButton.clipsToBounds = true
        submitButton.addTarget(self, action: #selector(submitTapped), forControlEvents: .touchUpInside)

        applyTheme()
        updateStateUI()
    }

    func focusInputWithDelay() {
        Queue.mainQueue().after(0.3) { [weak self] in
            self?.inputNode.becomeFirstResponder()
        }
    }

    func updateLayout(size: CGSize, safeTop: CGFloat, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) {
        let top = isNodeLoaded ? max(safeTop, view.safeAreaInsets.top) : safeTop
        validLayout = (size, top, bottomInset)
        applyLayout(transition: transition)
    }

    func applyTheme() {
        let t = UIColor.theme
        gradientLayer.colors = [t.primary.cgColor, t.primaryGradient.cgColor]

        backButton.tintColor = .mezonTextStrong
        inputBackgroundNode.backgroundColor = t.secondary

        let titleParagraphStyle = NSMutableParagraphStyle()
        titleParagraphStyle.alignment = .center

        let title = NSAttributedString(
            string: L(L10n.FriendRequest.addByTitle),
            attributes: [
                .font: UIFont.systemFont(ofSize: 17.sf, weight: .semibold),
                .foregroundColor: t.textStrong,
                .paragraphStyle: titleParagraphStyle
            ]
        )
        titleNode.attributedText = title
        titleNode.maximumNumberOfLines = 2
        titleNode.truncationMode = .byWordWrapping

        questionNode.attributedText = NSAttributedString(
            string: L(L10n.FriendRequest.addByQuestion),
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .medium),
                .foregroundColor: t.textStrong
            ]
        )

        let placeholderColor = t.textDisabled
        inputNode.attributedPlaceholderText = NSAttributedString(
            string: L(L10n.FriendRequest.addByPlaceholder),
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf),
                .foregroundColor: placeholderColor
            ]
        )

        updateStateUI()
        setNeedsLayout()
    }

    private func updateStateUI() {
        let t = UIColor.theme
        let currentUsername = state.currentUsername.isEmpty ? "..." : state.currentUsername
        let hintText = String(format: L(L10n.FriendRequest.addByHintFormat), currentUsername)
        hintNode.attributedText = NSAttributedString(
            string: hintText,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf),
                .foregroundColor: t.textStrong
            ]
        )

        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let enabled = !query.isEmpty && !state.isSending
        submitButton.isEnabled = enabled
        submitButton.backgroundColor = enabled ? t.bgViolet : t.textDisabled.withAlphaComponent(0.45)
        submitButton.setTitle(
            state.isSending ? L(L10n.FriendRequest.addBySending) : L(L10n.FriendRequest.addBySubmit),
            with: .systemFont(ofSize: 15.sf, weight: .semibold),
            with: UIColor.white.withAlphaComponent(enabled ? 1.0 : 0.8),
            for: .normal
        )

        if inputNode.attributedText?.string != state.query {
            inputNode.attributedText = NSAttributedString(
                string: state.query,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14.sf),
                    .foregroundColor: t.textStrong
                ]
            )
        }
    }

    private func applyLayout(transition: ContainedViewLayoutTransition) {
        guard let (size, safeTop, bottomInset) = validLayout else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = CGRect(origin: .zero, size: size)
        CATransaction.commit()

        let sideInset: CGFloat = 18.sw
        let headerH: CGFloat = 44.sh
        let headerY = safeTop
        let backSize: CGFloat = 36.swh

        transition.updateFrame(
            node: backButton,
            frame: CGRect(x: sideInset - 8.sw, y: headerY + (headerH - backSize) / 2, width: backSize, height: backSize)
        )

        let titleMaxWidth = size.width - (sideInset + backSize + 8.sw) * 2
        let titleSize = titleNode.measure(CGSize(width: titleMaxWidth, height: CGFloat.greatestFiniteMagnitude))
        let titleY = headerY + max(0, (headerH - titleSize.height) / 2)
        transition.updateFrame(
            node: titleNode,
            frame: CGRect(
                x: floor((size.width - titleSize.width) / 2),
                y: titleY,
                width: titleSize.width,
                height: titleSize.height
            )
        )

        let questionY = headerY + headerH + 28.sh
        let questionSize = questionNode.measure(CGSize(width: size.width - sideInset * 2, height: CGFloat.greatestFiniteMagnitude))
        transition.updateFrame(node: questionNode, frame: CGRect(x: sideInset, y: questionY, width: size.width - sideInset * 2, height: questionSize.height))

        let inputY = questionY + questionSize.height + 16.sh
        let inputHeight: CGFloat = 46.sh
        transition.updateFrame(node: inputBackgroundNode, frame: CGRect(x: sideInset, y: inputY, width: size.width - sideInset * 2, height: inputHeight))
        inputBackgroundNode.cornerRadius = 12.sf
        transition.updateFrame(node: inputNode, frame: CGRect(x: sideInset, y: inputY + 1.sh, width: size.width - sideInset * 2, height: inputHeight - 2.sh))

        let hintY = inputY + inputHeight + 20.sh
        let hintSize = hintNode.measure(CGSize(width: size.width - sideInset * 2, height: CGFloat.greatestFiniteMagnitude))
        transition.updateFrame(node: hintNode, frame: CGRect(x: sideInset, y: hintY, width: size.width - sideInset * 2, height: hintSize.height))

        let buttonHeight: CGFloat = 48.sh
        let buttonY = size.height - bottomInset - buttonHeight - 20.sh
        transition.updateFrame(node: submitButton, frame: CGRect(x: sideInset, y: buttonY, width: size.width - sideInset * 2, height: buttonHeight))
    }

    @objc private func backTapped() {
        interaction.onBackTapped()
    }

    @objc private func submitTapped() {
        interaction.onSubmit()
    }

    func editableTextNodeDidUpdateText(_ editableTextNode: ASEditableTextNode) {
        interaction.onQueryChanged(editableTextNode.attributedText?.string ?? "")
    }

    func editableTextNode(_ editableTextNode: ASEditableTextNode, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            interaction.onSubmit()
            return false
        }
        return true
    }
}
