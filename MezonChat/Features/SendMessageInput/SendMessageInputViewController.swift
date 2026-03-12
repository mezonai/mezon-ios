import UIKit

final class SendMessageInputViewController: UIViewController {

    private let context: AccountContext
    private let channel: Mezon_Api_ChannelDescription
    private let clanId: Int64
    private var disposables = DisposableSet()

    private let textPipe = ValuePipe<String>()
    private let placeholderPipe = ValuePipe<String>()

    private(set) var text: String = ""
    var placeholder: String

    var onVoiceTapped: (() -> Void)?
    var onSent: (() -> Void)?
    var onError: ((String) -> Void)?

    var inputBarBottomConstraint: NSLayoutConstraint?

    private lazy var inputBarView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var textField: UITextField = {
        let tf = UITextField()
        tf.borderStyle = .roundedRect
        tf.returnKeyType = .send
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.delegate = self
        return tf
    }()

    private lazy var sendButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.translatesAutoresizingMaskIntoConstraints = false
        let img = generateTintedImage(image: UIImage(bundleImageName: "Chat/IconMessagesIcon"), color: UIColor.theme.textRoleLink)
        btn.setImage(img, for: .normal)
        btn.addAction(UIAction { [weak self] _ in self?.send() }, for: .touchUpInside)
        return btn
    }()

    init(placeholder: String = "", channel: Mezon_Api_ChannelDescription, clanId: Int64, context: AccountContext) {
        self.placeholder = placeholder
        self.channel = channel
        self.clanId = clanId
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
        setupThemeObserver()
    }

    func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendChannelMessage(text: trimmed, clanId: clanId, channel: channel)
    }

    func clearText() { text = ""; textPipe.putNext("") }
    func updateText(_ newText: String) { text = newText; textPipe.putNext(newText) }

    private func setupUI() {
        view.addSubview(inputBarView)
        inputBarView.addSubview(textField)
        inputBarView.addSubview(sendButton)

        let bottomConstraint = inputBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        inputBarBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            inputBarView.topAnchor.constraint(equalTo: view.topAnchor),
            inputBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBarView.heightAnchor.constraint(equalToConstant: 56.sh),
            bottomConstraint,
            textField.leadingAnchor.constraint(equalTo: inputBarView.leadingAnchor, constant: 12.sw),
            textField.centerYAnchor.constraint(equalTo: inputBarView.centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8.sw),
            textField.heightAnchor.constraint(equalToConstant: 36.sh),
            sendButton.trailingAnchor.constraint(equalTo: inputBarView.trailingAnchor, constant: -8.sw),
            sendButton.centerYAnchor.constraint(equalTo: inputBarView.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 44.swh),
            sendButton.heightAnchor.constraint(equalToConstant: 44.swh),
        ])
    }

    private func setupBindings() {
        textField.placeholder = placeholder

        disposables.add(
            (textPipe.signal() |> deliverOnMainQueue).start(next: { [weak self] text in
                guard self?.textField.text != text else { return }
                self?.textField.text = text
            })
        )
    }

    private func setupThemeObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
    }

    @objc private func handleThemeChange() { applyTheme() }

    private func applyTheme() {
        let t = UIColor.theme
        inputBarView.backgroundColor = t.secondary
        textField.backgroundColor = t.tertiary
        textField.textColor = t.textStrong
        textField.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: t.textDisabled])
        if let sendImg = generateTintedImage(image: UIImage(bundleImageName: "Chat/IconMessagesIcon"), color: t.textRoleLink) {
            sendButton.setImage(sendImg, for: .normal)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyTheme()
    }

    deinit {
        disposables.dispose()
        NotificationCenter.default.removeObserver(self, name: ThemeManager.didChangeNotification, object: nil)
    }

    private func sendChannelMessage(text: String, clanId: Int64, channel: Mezon_Api_ChannelDescription) {
        guard let token = context.session?.token else {
            onError?("No session")
            return
        }
        let localId = "pending-\(UUID().uuidString)"
        let channelIdStr = "\(channel.channelID)"
        if let sender = context.currentUser {
            let pendingRecord = MessageRecord.pending(localId: localId, text: text, channelId: channelIdStr, clanId: clanId, sender: sender)
            self.context.account.postbox.write { tx in tx.addMessages([pendingRecord]) }
        }
        self.text = ""
        textPipe.putNext("")
        onSent?()

        let contentJSON = ["t": text]
        guard let data = try? JSONSerialization.data(withJSONObject: contentJSON),
              let contentStr = String(data: data, encoding: .utf8) else {
            self.context.account.postbox.write { tx in tx.markMessageFailed(id: localId) }
            onError?("Invalid content")
            return
        }
        let mode: Int32 = clanId == 0 ? (channel.type == MezonConstants.ChannelType.dm.rawValue ? 4 : 3) : 2
        let isPublic = channel.parentID != 0 ? false : (channel.channelPrivate == 0)
        let avatar: String = context.currentUser?.avatarURL?.absoluteString ?? ""

        Task { @MainActor in
            do {
                _ = try await self.context.account.network.sendChannelMessage(clanId: clanId, channelId: channel.channelID, mode: mode, isPublic: isPublic, content: contentStr, mentions: [], attachments: [], references: [], anonymous: false, mentionEveryone: false, avatar: avatar, topicId: 0, token: token)
                self.context.account.postbox.write { tx in tx.deleteMessage(id: localId) }
            } catch {
                self.context.account.postbox.write { tx in tx.markMessageFailed(id: localId) }
                self.onError?(error.localizedDescription)
            }
        }
    }
}

extension SendMessageInputViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        send()
        return true
    }

    func textFieldDidChangeSelection(_ textField: UITextField) {
        updateText(textField.text ?? "")
    }
}
