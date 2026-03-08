import UIKit
import Combine
import SwiftProtobuf

final class ChannelMessagesViewController: BaseViewController {

    private let viewModel: ChannelMessagesViewModel

    private lazy var headerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var backButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "chevron.left")
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addAction(UIAction { [weak self] _ in self?.onBack() }, for: .touchUpInside)
        return btn
    }()

    private lazy var channelTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 17, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.backgroundColor = .clear
        tv.separatorStyle = .none
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 72
        tv.showsVerticalScrollIndicator = true
        tv.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseId)
        tv.dataSource = self
        tv.delegate = self
        return tv
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.translatesAutoresizingMaskIntoConstraints = false
        ai.hidesWhenStopped = true
        return ai
    }()

    private lazy var loadingMoreIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.translatesAutoresizingMaskIntoConstraints = false
        ai.hidesWhenStopped = true
        return ai
    }()

    private lazy var emptyLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isHidden = true
        return l
    }()

    private lazy var inputBarView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var textField: UITextField = {
        let tf = UITextField()
        tf.placeholder = L(L10n.ChannelMessages.writeMessage)
        tf.borderStyle = .roundedRect
        tf.returnKeyType = .send
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.delegate = self
        return tf
    }()

    private lazy var sendButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "arrow.up.circle.fill")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addAction(UIAction { [weak self] _ in self?.onSendTapped() }, for: .touchUpInside)
        return btn
    }()

    private var inputBarBottomConstraint: NSLayoutConstraint?

    init(viewModel: ChannelMessagesViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
        setupKeyboardObservers()
        viewModel.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tap)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let info = notification.userInfo,
              let keyboardFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else { return }
        let keyboardHeight = keyboardFrame.height
        inputBarBottomConstraint?.constant = -keyboardHeight
        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve << 16)) {
            self.view.layoutIfNeeded()
        }
        scrollToBottomIfNeeded()
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let info = notification.userInfo,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else { return }
        inputBarBottomConstraint?.constant = 0
        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve << 16)) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    override func setupUI() {
        view.addSubview(headerView)
        headerView.addSubview(backButton)
        headerView.addSubview(channelTitleLabel)
        view.addSubview(tableView)
        view.addSubview(loadingIndicator)
        view.addSubview(loadingMoreIndicator)
        view.addSubview(emptyLabel)
        view.addSubview(inputBarView)
        inputBarView.addSubview(textField)
        inputBarView.addSubview(sendButton)

        let bottomConstraint = inputBarView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        inputBarBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 44),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            channelTitleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            channelTitleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            channelTitleLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -60),

            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputBarView.topAnchor),

            inputBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBarView.heightAnchor.constraint(equalToConstant: 56),

            textField.leadingAnchor.constraint(equalTo: inputBarView.leadingAnchor, constant: 12),
            textField.centerYAnchor.constraint(equalTo: inputBarView.centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            textField.heightAnchor.constraint(equalToConstant: 36),

            sendButton.trailingAnchor.constraint(equalTo: inputBarView.trailingAnchor, constant: -8),
            sendButton.centerYAnchor.constraint(equalTo: inputBarView.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 44),
            sendButton.heightAnchor.constraint(equalToConstant: 44),
            bottomConstraint,

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            loadingMoreIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingMoreIndicator.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 12),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func setupBindings() {
        viewModel.$channelLabel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] label in
                let prefix = label.hasPrefix("#") ? "" : "#"
                self?.channelTitleLabel.text = "\(prefix)\(label)"
            }
            .store(in: &cancellables)

        viewModel.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
                self?.updateEmptyState()
                DispatchQueue.main.async {
                    self?.scrollToBottomIfNeeded()
                }
            }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                loading ? self?.loadingIndicator.startAnimating() : self?.loadingIndicator.stopAnimating()
            }
            .store(in: &cancellables)

        viewModel.$isLoadingMore
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                loading ? self?.loadingMoreIndicator.startAnimating() : self?.loadingMoreIndicator.stopAnimating()
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { msg in
                Toast.error(msg)
            }
            .store(in: &cancellables)
    }

    override func applyTheme() {
        let t = UIColor.theme
        view.backgroundColor = t.primary
        headerView.backgroundColor = t.secondary
        backButton.tintColor = t.textStrong
        channelTitleLabel.textColor = t.textStrong
        loadingIndicator.color = t.textDisabled
        loadingMoreIndicator.color = t.textDisabled
        emptyLabel.textColor = t.textDisabled
        inputBarView.backgroundColor = t.secondary
        textField.backgroundColor = t.tertiary
        textField.textColor = t.textStrong
        textField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.ChannelMessages.writeMessage),
            attributes: [.foregroundColor: t.textDisabled]
        )
        sendButton.tintColor = t.textRoleLink
    }

    private func updateEmptyState() {
        let isEmpty = !viewModel.isLoading && viewModel.messages.isEmpty
        emptyLabel.isHidden = !isEmpty
        emptyLabel.text = L(L10n.ChannelMessages.emptyMessages)
    }

    private var shouldScrollToBottom = true
    private var hasScrolledToBottomInitially = false
    private func scrollToBottomIfNeeded() {
        guard shouldScrollToBottom, !viewModel.messages.isEmpty else { return }
        let last = IndexPath(row: viewModel.messages.count - 1, section: 0)
        let isInitial = !hasScrolledToBottomInitially
        hasScrolledToBottomInitially = true
        if isInitial {
            tableView.scrollToRow(at: last, at: .bottom, animated: false)
            tableView.setContentOffset(CGPoint(x: 0, y: max(-tableView.contentInset.top, tableView.contentSize.height - tableView.bounds.height + tableView.contentInset.bottom)), animated: false)
        } else {
            tableView.scrollToRow(at: last, at: .bottom, animated: true)
        }
    }

    private func onSendTapped() {
        guard let text = textField.text else { return }
        viewModel.sendMessage(text: text)
        textField.text = ""
        shouldScrollToBottom = true
    }

    private func onBack() {
        navigationController?.popViewController(animated: true)
    }
}

extension ChannelMessagesViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.reuseId, for: indexPath) as! MessageCell
        let display = viewModel.messages[indexPath.row]
        cell.configure(display: display)
        return cell
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y < 80, viewModel.hasMoreOlder, !viewModel.isLoadingMore {
            viewModel.fetchMoreMessages()
        }
        shouldScrollToBottom = scrollView.contentOffset.y + scrollView.bounds.height >= scrollView.contentSize.height - 100
    }
}

extension ChannelMessagesViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onSendTapped()
        return true
    }
}

private final class MessageCell: UITableViewCell {

    static let reuseId = "MessageCell"

    private let avatarView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 18
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.backgroundColor = .colorAvatarDefault
        return iv
    }()

    private let avatarPlaceholder: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        l.textAlignment = .center
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let timeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let contentLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15)
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private var contentTopToName: NSLayoutConstraint?
    private var contentTopToView: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(avatarView)
        avatarView.addSubview(avatarPlaceholder)
        contentView.addSubview(nameLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(contentLabel)

        contentTopToName = contentLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2)
        contentTopToView = contentLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            avatarView.widthAnchor.constraint(equalToConstant: 36),
            avatarView.heightAnchor.constraint(equalToConstant: 36),

            avatarPlaceholder.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarPlaceholder.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),

            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            contentLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            contentLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            contentLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
        contentTopToName?.isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(display: ChannelMessageDisplay) {
        let t = UIColor.theme
        let isCombine = display.isCombine

        nameLabel.text = display.senderDisplayName
        nameLabel.textColor = t.textRoleLink
        timeLabel.text = formatDate(display.message.createdAt)
        timeLabel.textColor = t.textDisabled
        contentLabel.text = display.message.textContent ?? "[unsupported]"
        contentLabel.textColor = t.textStrong

        avatarView.isHidden = isCombine
        avatarPlaceholder.isHidden = isCombine
        nameLabel.isHidden = isCombine
        timeLabel.isHidden = isCombine

        contentTopToName?.isActive = !isCombine
        contentTopToView?.isActive = isCombine

        if !isCombine {
            if let urlString = display.avatarURL, !urlString.isEmpty, let url = URL(string: urlString) {
                avatarPlaceholder.isHidden = true
                avatarView.image = nil
                URLSession.shared.dataTask(with: url) { [weak avatarView] data, _, _ in
                    guard let data, let img = UIImage(data: data) else { return }
                    DispatchQueue.main.async { avatarView?.image = img }
                }
                .resume()
            } else {
                avatarView.image = nil
                avatarPlaceholder.isHidden = false
                avatarPlaceholder.text = String(display.senderDisplayName.prefix(1)).uppercased()
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        let timeF = DateFormatter()
        timeF.dateFormat = "HH:mm"
        let timeStr = timeF.string(from: date)
        if cal.isDateInToday(date) {
            return String(format: L(L10n.ChannelMessages.todayAt), timeStr)
        }
        if cal.isDateInYesterday(date) {
            return String(format: L(L10n.ChannelMessages.yesterdayAt), timeStr)
        }
        let fullF = DateFormatter()
        fullF.dateFormat = "dd/MM/yyyy, HH:mm"
        return fullF.string(from: date)
    }
}
