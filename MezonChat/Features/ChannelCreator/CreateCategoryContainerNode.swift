import UIKit
import AsyncDisplayKit

final class CreateCategoryContainerNode: ASDisplayNode {

    private let onClose: () -> Void
    private let onCreate: (String) -> Void

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let nameField = UITextField()
    private let nameErrorLabel = UILabel()
    private var createBtn: UIButton!
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    init(
        onClose: @escaping () -> Void,
        onCreate: @escaping (String) -> Void
    ) {
        self.onClose = onClose
        self.onCreate = onCreate
        super.init()
        backgroundColor = UIColor.theme.primary
    }

    override func didLoad() {
        super.didLoad()
        setupUI()
    }

    private func setupUI() {
        let t = UIColor.theme

        let header = UIView()
        view.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44.sh),
        ])

        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage(systemName: "xmark")?.withRenderingMode(.alwaysTemplate), for: .normal)
        closeBtn.tintColor = t.textStrong
        closeBtn.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
        header.addSubview(closeBtn)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            closeBtn.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16.sw),
            closeBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 24.swh),
            closeBtn.heightAnchor.constraint(equalToConstant: 24.swh),
        ])

        let titleLabel = UILabel()
        titleLabel.text = L(L10n.CategoryCreator.title)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        titleLabel.textColor = t.textStrong
        header.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        createBtn = UIButton(type: .system)
        createBtn.setTitle(L(L10n.CategoryCreator.create), for: .normal)
        createBtn.titleLabel?.font = .systemFont(ofSize: 17.sf, weight: .medium)
        createBtn.addTarget(self, action: #selector(handleCreate), for: .touchUpInside)
        createBtn.isEnabled = false
        createBtn.tintColor = t.textDisabled
        header.addSubview(createBtn)
        createBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            createBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16.sw),
            createBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        header.addSubview(activityIndicator)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: createBtn.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: createBtn.centerYAnchor),
        ])

        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        stackView.axis = .vertical
        stackView.spacing = 20.sh
        scrollView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16.sh),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16.sw),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16.sw),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16.sh),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32.sw),
        ])

        let nameSection = createInputSection(title: L(L10n.CategoryCreator.nameTitle), input: nameField)
        nameField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.CategoryCreator.namePlaceholder),
            attributes: [
                .foregroundColor: UIColor.theme.textDisabled,
                .font: UIFont.systemFont(ofSize: 14.sf)
            ]
        )
        stackView.addArrangedSubview(nameSection)
    }

    private func createInputSection(title: String, input: UIView) -> UIView {
        let v = UIStackView()
        v.axis = .vertical
        v.spacing = 8.sh

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 14.sf, weight: .bold)
        label.textColor = UIColor.theme.textStrong
        v.addArrangedSubview(label)

        input.backgroundColor = UIColor.theme.secondary
        input.layer.cornerRadius = 12
        if let tf = input as? UITextField {
            tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12.sw, height: 1))
            tf.leftViewMode = .always
            tf.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12.sw, height: 1))
            tf.rightViewMode = .always
            tf.textColor = UIColor.theme.textStrong
            tf.font = .systemFont(ofSize: 14.sf)
            tf.heightAnchor.constraint(equalToConstant: 48.sh).isActive = true
            tf.addTarget(self, action: #selector(handleNameChange), for: .editingChanged)
        }
        v.addArrangedSubview(input)

        nameErrorLabel.text = L(L10n.CategoryCreator.nameError)
        nameErrorLabel.font = .systemFont(ofSize: 12.sf)
        nameErrorLabel.textColor = .mezonError
        nameErrorLabel.numberOfLines = 0
        nameErrorLabel.isHidden = true
        v.addArrangedSubview(nameErrorLabel)

        return v
    }

    private func isValidCategoryName(_ name: String) -> Bool {
        ClanCreationNameRules.isValid(name)
    }

    @objc private func handleNameChange() {
        let name = nameField.text ?? ""
        let isValid = isValidCategoryName(name)
        let isPristine = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        createBtn.isEnabled = isValid
        createBtn.tintColor = isValid ? .mezonLink : UIColor.theme.textDisabled
        nameErrorLabel.isHidden = isValid || isPristine
    }

    @objc private func handleClose() { onClose() }

    @objc private func handleCreate() {
        let name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !isValidCategoryName(name) { return }
        onCreate(name)
    }

    func applyTheme() {
        backgroundColor = UIColor.theme.primary
        activityIndicator.color = UIColor.theme.textStrong
    }

    func setLoading(_ isLoading: Bool) {
        if isLoading {
            createBtn.setTitle("", for: .normal)
            createBtn.isEnabled = false
            activityIndicator.startAnimating()
            nameField.isEnabled = false
        } else {
            createBtn.setTitle(L(L10n.CategoryCreator.create), for: .normal)
            activityIndicator.stopAnimating()
            nameField.isEnabled = true
            handleNameChange()
        }
    }
}
