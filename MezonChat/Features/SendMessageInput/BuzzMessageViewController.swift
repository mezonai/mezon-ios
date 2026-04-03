import UIKit

final class BuzzMessageViewController: UIViewController {

    var onSend: ((String) -> Void)?

    private static let maxLength = 160

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    private lazy var backdropView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleCancel))
        v.addGestureRecognizer(tap)
        return v
    }()

    private lazy var containerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 16
        v.clipsToBounds = true
        return v
    }()

    private lazy var titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = "Send a Buzz message to get attention!"
        lbl.font = .systemFont(ofSize: 15, weight: .semibold)
        lbl.textAlignment = .center
        lbl.numberOfLines = 2
        return lbl
    }()

    private lazy var textView: UITextView = {
        let tv = UITextView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.font = .systemFont(ofSize: 15)
        tv.text = "Buzz!!"
        tv.layer.cornerRadius = 10
        tv.layer.borderWidth = 1
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        tv.delegate = self
        return tv
    }()

    private lazy var charCountLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 11)
        lbl.textAlignment = .right
        return lbl
    }()

    private lazy var confirmButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle("Confirm", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        btn.layer.cornerRadius = 10
        btn.clipsToBounds = true
        btn.addAction(UIAction { [weak self] _ in self?.handleSend() }, for: .touchUpInside)
        return btn
    }()

    private var containerCenterYConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        applyTheme()
        updateCharCount()

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
        textView.selectAll(nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupLayout() {
        view.addSubview(backdropView)
        view.addSubview(containerView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(textView)
        containerView.addSubview(charCountLabel)
        containerView.addSubview(confirmButton)

        let centerY = containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        containerCenterYConstraint = centerY

        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerY,
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            textView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            textView.heightAnchor.constraint(equalToConstant: 90),

            charCountLabel.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 4),
            charCountLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor),

            confirmButton.topAnchor.constraint(equalTo: charCountLabel.bottomAnchor, constant: 12),
            confirmButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            confirmButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            confirmButton.heightAnchor.constraint(equalToConstant: 44),
            confirmButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
        ])
    }

    private func applyTheme() {
        let t = UIColor.theme
        containerView.backgroundColor = t.secondary
        titleLabel.textColor = t.textStrong
        textView.backgroundColor = t.tertiary
        textView.textColor = t.textStrong
        textView.layer.borderColor = t.border.cgColor
        charCountLabel.textColor = t.textDisabled
        confirmButton.backgroundColor = UIColor.systemBlue
        confirmButton.setTitleColor(.white, for: .normal)
    }

    private func updateCharCount() {
        let count = textView.text.count
        charCountLabel.text = "\(count)/\(Self.maxLength)"
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }
        let offset = -(frame.height / 2 - 40)
        containerCenterYConstraint?.constant = offset
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }
        containerCenterYConstraint?.constant = 0
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
    }

    @objc private func handleCancel() {
        dismiss(animated: true)
    }

    private func handleSend() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSend?(text)
        dismiss(animated: true)
    }
}


extension BuzzMessageViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let current = textView.text ?? ""
        guard let stringRange = Range(range, in: current) else { return false }
        let updated = current.replacingCharacters(in: stringRange, with: text)
        return updated.count <= Self.maxLength
    }

    func textViewDidChange(_ textView: UITextView) {
        updateCharCount()
    }
}
