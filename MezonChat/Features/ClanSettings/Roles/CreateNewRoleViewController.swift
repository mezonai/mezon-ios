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
    private let descriptionLabel = UILabel()

    private let inputContainer = UIView()
    private let inputLabel = UILabel()
    private let inputField = UITextField()

    private let colorRow = UIControl()
    private let colorTitleLabel = UILabel()
    private let colorValueLabel = UILabel()
    private let colorIndicator = UIView()

    private let createButton = UIButton(type: .system)
    private var createButtonBottomConstraint: NSLayoutConstraint?

    private let maxNameCharacters = 64
    private var name: String = "" { didSet { refreshCreateButton() } }
    private var selectedColor: String = ""
    private var isCreating: Bool = false

    init(context: AccountContext, clanId: Int64) {
        self.context = context
        self.clanId = clanId
        self.repository = RolesRepository(context: context)
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardFrameChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    override func setupUI() {
        view.backgroundColor = .mezonSecondary
        navigationController?.setNavigationBarHidden(true, animated: false)
        setupHeader()
        setupCopy()
        setupInput()
        setupColorRow()
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
        inputField.resignFirstResponder()
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
        descriptionLabel.text = L(L10n.ClanRoles.createDescription)
        descriptionLabel.font = .systemFont(ofSize: 13.sf, weight: .regular)
        descriptionLabel.textColor = UIColor.theme.textDisabled
        descriptionLabel.numberOfLines = 0
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descriptionLabel)

        NSLayoutConstraint.activate([
            descriptionLabel.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 10.sh),
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
    }

    private func setupColorRow() {
        colorRow.backgroundColor = UIColor.theme.tertiary
        colorRow.layer.cornerRadius = 12.swh
        colorRow.addTarget(self, action: #selector(colorRowTapped), for: .touchUpInside)
        colorRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(colorRow)

        colorTitleLabel.text = L(L10n.ClanRoles.colorRow)
        colorTitleLabel.font = .systemFont(ofSize: 14.sf, weight: .medium)
        colorTitleLabel.textColor = .mezonTextPrimary

        colorValueLabel.font = .systemFont(ofSize: 13.sf, weight: .regular)
        colorValueLabel.textColor = UIColor.theme.textDisabled

        colorIndicator.layer.cornerRadius = 8.swh
        colorIndicator.layer.borderWidth = 1
        colorIndicator.layer.borderColor = UIColor.theme.borderDim.cgColor

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right")?.withRenderingMode(.alwaysTemplate))
        chevron.tintColor = UIColor.theme.textDisabled
        chevron.contentMode = .scaleAspectFit

        [colorTitleLabel, colorValueLabel, colorIndicator, chevron].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            colorRow.addSubview($0)
        }

        NSLayoutConstraint.activate([
            colorRow.topAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: 12.sh),
            colorRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            colorRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            colorRow.heightAnchor.constraint(equalToConstant: 56.sh),

            colorTitleLabel.leadingAnchor.constraint(equalTo: colorRow.leadingAnchor, constant: 14.sw),
            colorTitleLabel.centerYAnchor.constraint(equalTo: colorRow.centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: colorRow.trailingAnchor, constant: -12.sw),
            chevron.centerYAnchor.constraint(equalTo: colorRow.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10.swh),
            chevron.heightAnchor.constraint(equalToConstant: 14.swh),

            colorIndicator.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -10.sw),
            colorIndicator.centerYAnchor.constraint(equalTo: colorRow.centerYAnchor),
            colorIndicator.widthAnchor.constraint(equalToConstant: 16.swh),
            colorIndicator.heightAnchor.constraint(equalToConstant: 16.swh),

            colorValueLabel.trailingAnchor.constraint(equalTo: colorIndicator.leadingAnchor, constant: -8.sw),
            colorValueLabel.centerYAnchor.constraint(equalTo: colorRow.centerYAnchor)
        ])
        refreshColorRow()
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

        let bottomConstraint = createButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12.sh)
        createButtonBottomConstraint = bottomConstraint
        NSLayoutConstraint.activate([
            createButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            createButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            bottomConstraint,
            createButton.heightAnchor.constraint(equalToConstant: 50.sh)
        ])
        refreshCreateButton()
    }

    private func refreshColorRow() {
        let hex = selectedColor.isEmpty ? RolePermissionConstants.defaultRoleColor : selectedColor
        colorIndicator.backgroundColor = UIColor(hexString: hex) ?? .systemGray
        colorValueLabel.text = selectedColor.isEmpty ? "" : selectedColor.uppercased()
    }

    private func refreshCreateButton() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let enabled = !trimmed.isEmpty && !isCreating
        createButton.isEnabled = enabled
        createButton.backgroundColor = enabled ? UIColor.theme.bgViolet : UIColor(white: 0.4, alpha: 1.0)
        createButton.alpha = enabled ? 1.0 : 0.8
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

    @objc private func colorRowTapped() {
        inputField.resignFirstResponder()
        let picker = RoleColorPickerSheetController(initialColor: selectedColor) { [weak self] hex in
            self?.selectedColor = hex
            self?.refreshColorRow()
        }
        present(picker, animated: true)
    }

    @objc private func handleKeyboardFrameChange(_ notification: Notification) {
        guard let info = notification.userInfo,
            let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }

        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        let keyboardOffset = max(0, overlap - view.safeAreaInsets.bottom)
        createButtonBottomConstraint?.constant = -12.sh - keyboardOffset

        let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveValue = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 0
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: UIView.AnimationOptions(rawValue: curveValue << 16),
            animations: { self.view.layoutIfNeeded() }
        )
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
                    color: self.selectedColor,
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
