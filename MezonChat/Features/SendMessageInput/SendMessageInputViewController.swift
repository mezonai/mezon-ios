import UIKit
import Combine

final class SendMessageInputViewController: UIViewController {

    private let viewModel: SendMessageInputViewModel
    private var cancellables = Set<AnyCancellable>()

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
        let img = generateTintedImage(
            image: UIImage(bundleImageName: "Chat/IconMessagesIcon"),
            color: UIColor.theme.textRoleLink
        )
        btn.setImage(img, for: .normal)
        btn.addAction(UIAction { [weak self] _ in self?.viewModel.send() }, for: .touchUpInside)
        return btn
    }()

    init(viewModel: SendMessageInputViewModel) {
        self.viewModel = viewModel
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
            inputBarView.heightAnchor.constraint(equalToConstant: 56),
            bottomConstraint,

            textField.leadingAnchor.constraint(equalTo: inputBarView.leadingAnchor, constant: 12),
            textField.centerYAnchor.constraint(equalTo: inputBarView.centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            textField.heightAnchor.constraint(equalToConstant: 36),

            sendButton.trailingAnchor.constraint(equalTo: inputBarView.trailingAnchor, constant: -8),
            sendButton.centerYAnchor.constraint(equalTo: inputBarView.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 44),
            sendButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setupBindings() {
        viewModel.$text
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard self?.textField.text != text else { return }
                self?.textField.text = text
            }
            .store(in: &cancellables)

        viewModel.$placeholder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] placeholder in
                self?.textField.placeholder = placeholder
            }
            .store(in: &cancellables)
    }

    private func setupThemeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    @objc private func handleThemeChange() {
        applyTheme()
    }

    private func applyTheme() {
        let t = UIColor.theme
        inputBarView.backgroundColor = t.secondary
        textField.backgroundColor = t.tertiary
        textField.textColor = t.textStrong
        textField.attributedPlaceholder = NSAttributedString(
            string: viewModel.placeholder,
            attributes: [.foregroundColor: t.textDisabled]
        )
        if let sendImg = generateTintedImage(
            image: UIImage(bundleImageName: "Chat/IconMessagesIcon"),
            color: t.textRoleLink
        ) {
            sendButton.setImage(sendImg, for: .normal)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyTheme()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: ThemeManager.didChangeNotification, object: nil)
    }
}

extension SendMessageInputViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        viewModel.send()
        return true
    }

    func textFieldDidChangeSelection(_ textField: UITextField) {
        viewModel.text = textField.text ?? ""
    }
}
