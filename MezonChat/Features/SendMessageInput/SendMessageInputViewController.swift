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

    private lazy var attachButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16.sf, weight: .medium)), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.layer.cornerRadius = 20.swh
        return btn
    }()

    private lazy var textField: UITextField = {
        let tf = UITextField()
        tf.borderStyle = .none
        tf.returnKeyType = .send
        tf.layer.cornerRadius = 20.swh
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16.sw, height: 1))
        tf.leftViewMode = .always
        tf.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 40.sw, height: 1))
        tf.rightViewMode = .always
        tf.delegate = self
        return tf
    }()

    private lazy var emojiButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "face.smiling", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.sf)), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var sendButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.layer.cornerRadius = 20.swh
        btn.clipsToBounds = true
        btn.setImage(UIImage(systemName: "paperplane.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16.sf, weight: .medium)), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1)
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
        applyTheme()
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
        inputBarView.addSubview(attachButton)
        inputBarView.addSubview(textField)
        inputBarView.addSubview(emojiButton)
        inputBarView.addSubview(sendButton)

        let bottomConstraint = inputBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        inputBarBottomConstraint = bottomConstraint

        let btnSize: CGFloat = 40.swh

        NSLayoutConstraint.activate([
            inputBarView.topAnchor.constraint(equalTo: view.topAnchor, constant: 14.sh),
            inputBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBarView.heightAnchor.constraint(equalToConstant: 56.sh),
            bottomConstraint,

            attachButton.leadingAnchor.constraint(equalTo: inputBarView.leadingAnchor, constant: 4.sw),
            attachButton.centerYAnchor.constraint(equalTo: inputBarView.centerYAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: btnSize),
            attachButton.heightAnchor.constraint(equalToConstant: btnSize),

            textField.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 4.sw),
            textField.centerYAnchor.constraint(equalTo: inputBarView.centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -6.sw),
            textField.heightAnchor.constraint(equalToConstant: 40.sh),

            emojiButton.trailingAnchor.constraint(equalTo: textField.trailingAnchor, constant: -8.sw),
            emojiButton.centerYAnchor.constraint(equalTo: textField.centerYAnchor),
            emojiButton.widthAnchor.constraint(equalToConstant: 28.swh),
            emojiButton.heightAnchor.constraint(equalToConstant: 28.swh),

            sendButton.trailingAnchor.constraint(equalTo: inputBarView.trailingAnchor, constant: -4.sw),
            sendButton.centerYAnchor.constraint(equalTo: inputBarView.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: btnSize),
            sendButton.heightAnchor.constraint(equalToConstant: btnSize),
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
        textField.font = .systemFont(ofSize: 15.sf)
        textField.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: t.textDisabled])
        attachButton.backgroundColor = t.tertiary
        attachButton.tintColor = t.textStrong
        emojiButton.tintColor = t.textDisabled
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
