import UIKit
import AsyncDisplayKit

@MainActor
final class CreateNewRoleViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let repository: RolesRepository

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let headingLabel = UILabel()
    private let descriptionLabel = UILabel()

    private let inputContainer = UIView()
    private let inputLabel = UILabel()
    private let inputField = UITextField()

    private let createButton = UIButton(type: .system)
    private let accessoryCreateButton = UIButton(type: .system)

    private let maxNameCharacters = 64
    private var name: String = "" { didSet { refreshCreateButton() } }
    private var isCreating: Bool = false

    init(context: AccountContext, clanId: Int64) {
        self.context = context
        self.clanId = clanId
        self.repository = RolesRepository(context: context)
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func setupUI() {
        view.backgroundColor = .mezonSecondary
        navigationController?.setNavigationBarHidden(true, animated: false)
        setupHeader()
        setupCopy()
        setupInput()
        setupCreateButton()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        inputField.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // MARK: - Setup

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(
            UIImage(systemName: "xmark")?.withRenderingMode(.alwaysTemplate),
            for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        titleLabel.text = L(L10n.ClanRoles.createTitle)
        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .bold)
        titleLabel.textColor = .mezonTextPrimary
        titleLabel.textAlignment = .center

        [backButton, titleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50.sh),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8.sw),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44.swh),
            backButton.heightAnchor.constraint(equalToConstant: 44.swh),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    private func setupCopy() {
        headingLabel.text = L(L10n.ClanRoles.createHeading)
        headingLabel.font = .systemFont(ofSize: 22.sf, weight: .bold)
        headingLabel.textColor = .mezonTextPrimary

        descriptionLabel.text = L(L10n.ClanRoles.createDescription)
        descriptionLabel.font = .systemFont(ofSize: 13.sf, weight: .regular)
        descriptionLabel.textColor = UIColor.theme.textDisabled
        descriptionLabel.numberOfLines = 0

        [headingLabel, descriptionLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            headingLabel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 24.sh),
            headingLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            headingLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),

            descriptionLabel.topAnchor.constraint(equalTo: headingLabel.bottomAnchor, constant: 10.sh),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw)
        ])
    }

    private func setupInput() {
        inputContainer.backgroundColor = UIColor.theme.tertiary
        inputContainer.layer.cornerRadius = 12.swh
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputContainer)

        inputLabel.text = L(L10n.ClanRoles.createRoleName)
        inputLabel.font = .systemFont(ofSize: 11.sf, weight: .semibold)
        inputLabel.textColor = UIColor.theme.textDisabled
        inputLabel.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.addSubview(inputLabel)

        inputField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.ClanRoles.createNewRolePlaceholder),
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )
        inputField.textColor = .mezonTextPrimary
        inputField.font = .systemFont(ofSize: 15.sf, weight: .regular)
        inputField.returnKeyType = .done
        inputField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        inputField.delegate = self
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.addSubview(inputField)

        NSLayoutConstraint.activate([
            inputContainer.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 24.sh),
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),

            inputLabel.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 10.sh),
            inputLabel.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 14.sw),

            inputField.topAnchor.constraint(equalTo: inputLabel.bottomAnchor, constant: 4.sh),
            inputField.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 14.sw),
            inputField.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -14.sw),
            inputField.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -12.sh),
            inputField.heightAnchor.constraint(equalToConstant: 24.sh)
        ])
        setupInputAccessory()
    }

    private func setupInputAccessory() {
        let container = UIView()
        container.backgroundColor = .mezonSecondary

        accessoryCreateButton.setTitle(L(L10n.ClanRoles.createButton), for: .normal)
        accessoryCreateButton.setTitleColor(.white, for: .normal)
        accessoryCreateButton.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        accessoryCreateButton.backgroundColor = UIColor.theme.bgViolet
        accessoryCreateButton.layer.cornerRadius = 12.swh
        accessoryCreateButton.clipsToBounds = true
        accessoryCreateButton.addTarget(self, action: #selector(createTapped), for: .touchUpInside)
        accessoryCreateButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(accessoryCreateButton)

        let topPad: CGFloat = 8.sh
        let bottomPad: CGFloat = 8.sh
        NSLayoutConstraint.activate([
            accessoryCreateButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16.sw),
            accessoryCreateButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16.sw),
            accessoryCreateButton.topAnchor.constraint(equalTo: container.topAnchor, constant: topPad),
            accessoryCreateButton.heightAnchor.constraint(equalToConstant: 50.sh),
            accessoryCreateButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -bottomPad),
        ])

        let h = topPad + 50.sh + bottomPad
        let w = max(view.bounds.width, UIScreen.main.bounds.width)
        container.frame = CGRect(x: 0, y: 0, width: w, height: h)
        inputField.inputAccessoryView = container
    }

    private func setupCreateButton() {
        createButton.setTitle(L(L10n.ClanRoles.createButton), for: .normal)
        createButton.setTitleColor(.white, for: .normal)
        createButton.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        createButton.backgroundColor = UIColor.theme.bgViolet
        createButton.layer.cornerRadius = 12.swh
        createButton.translatesAutoresizingMaskIntoConstraints = false
        createButton.addTarget(self, action: #selector(createTapped), for: .touchUpInside)
        view.addSubview(createButton)

        NSLayoutConstraint.activate([
            createButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            createButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            createButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12.sh),
            createButton.heightAnchor.constraint(equalToConstant: 50.sh)
        ])
        refreshCreateButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let acc = inputField.inputAccessoryView else { return }
        let w = view.bounds.width
        guard w > 0.5, abs(acc.bounds.width - w) > 0.5 else { return }
        acc.frame.size.width = w
        acc.layoutIfNeeded()
    }

    private func refreshCreateButton() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let enabled = !trimmed.isEmpty && !isCreating
        for btn in [createButton, accessoryCreateButton] {
            btn.isEnabled = enabled
            btn.backgroundColor = enabled ? UIColor.theme.bgViolet : UIColor(white: 0.4, alpha: 1.0)
            btn.alpha = enabled ? 1.0 : 0.8
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func nameChanged() {
        let raw = inputField.text ?? ""
        let trimmed = String(raw.prefix(maxNameCharacters))
        if trimmed != raw {
            inputField.text = trimmed
        }
        name = trimmed
    }

    @objc private func createTapped() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isCreating else { return }
        isCreating = true
        refreshCreateButton()
        inputField.resignFirstResponder()

        Task { [weak self] in
            guard let self else { return }
            do {
                let role = try await self.repository.createRole(
                    clanId: self.clanId,
                    title: trimmed,
                    color: "",
                    roleIcon: "",
                    addUserIds: [],
                    activePermissionIds: []
                )
                let next = SetupPermissionsViewController(
                    context: self.context, clanId: self.clanId,
                    mode: .wizard(roleId: role.id)
                )
                let viewControllers = (self.navigationController?.viewControllers ?? [])
                    .filter { $0 !== self }
                self.navigationController?.setViewControllers(viewControllers + [next], animated: true)
            } catch {
                Toast.error(L(L10n.ClanRoles.failed))
                self.isCreating = false
                self.refreshCreateButton()
            }
        }
    }
}

extension CreateNewRoleViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        if createButton.isEnabled { createTapped() }
        return true
    }
}
