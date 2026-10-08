import UIKit

enum QuickMenuNameRules {
    static let maxNameScalars = 64
    static let maxActionMsgBytes = 512

    static func isValidName(_ name: String) -> Bool {
        let scalars = name.unicodeScalars
        guard let first = scalars.first, scalars.count <= maxNameScalars else { return false }
        if first == "_" || first == "-" { return false }
        return scalars.allSatisfy(isAllowedNameScalar)
    }

    static func isValidActionMsg(_ actionMsg: String) -> Bool {
        !actionMsg.isEmpty && actionMsg.utf8.count <= maxActionMsgBytes
    }

    static func nameExists(_ name: String, in items: [Mezon_Api_QuickMenuAccess], excludingId: Int64?) -> Bool {
        items.contains { item in
            item.menuName == name && (excludingId.map { item.id != $0 } ?? true)
        }
    }

    private static func isAllowedNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        if isNameEmoji(scalar) { return true }
        switch scalar {
        case "_", " ", "-", ".", "+":
            return true
        default:
            break
        }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber,
             .otherSymbol:
            return true
        default:
            return false
        }
    }

    private static func isNameEmoji(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1F600...0x1F64F, 0x1F300...0x1F5FF, 0x1F680...0x1F6FF, 0x1F700...0x1F77F,
             0x1F780...0x1F7FF, 0x1F800...0x1F8FF, 0x1F900...0x1F9FF, 0x1FA00...0x1FA6F,
             0x1FA70...0x1FAFF:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class QuickActionEditViewController: BaseViewController {

    private enum FormError {
        case none
        case invalidName
        case duplicateName
        case messageTooLong
    }

    private static let botEventAction = "bot_event"

    var onSaved: ((Mezon_Api_QuickMenuAccess, Bool) -> Void)?

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private let kind: QuickActionKind
    private let editingItem: Mezon_Api_QuickMenuAccess?
    private let existingItems: [Mezon_Api_QuickMenuAccess]

    private var formError: FormError = .none
    private var isSubmitting = false
    private var didAutofocus = false

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let submitButton = UIButton(type: .system)
    private let submitIndicator = UIActivityIndicatorView(style: .medium)

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    private let nameTitleLabel = UILabel()
    private let nameContainer = UIView()
    private let slashLabel = UILabel()
    private let nameField = UITextField()
    private let nameHelperLabel = UILabel()
    private let nameErrorLabel = UILabel()

    private let contentTitleLabel = UILabel()
    private let contentTextView = UITextView()
    private let contentPlaceholderLabel = UILabel()
    private let contentHelperLabel = UILabel()
    private let contentErrorLabel = UILabel()

    private let calloutView = UIView()
    private let calloutIconView = UIImageView()
    private let calloutTitleLabel = UILabel()
    private let calloutBodyLabel = UILabel()

    init(
        context: AccountContext,
        clanId: Int64,
        channelId: Int64,
        kind: QuickActionKind,
        editing: Mezon_Api_QuickMenuAccess?,
        existingItems: [Mezon_Api_QuickMenuAccess]
    ) {
        self.context = context
        self.clanId = clanId
        self.channelId = channelId
        self.kind = kind
        self.editingItem = editing
        self.existingItems = existingItems
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) { fatalError() }

    private var isFlash: Bool { kind == .flashMessage }

    private var draftName: String {
        (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    private var draftContent: String {
        contentTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !isSubmitting
            && !draftName.isEmpty
            && (!isFlash || !draftContent.isEmpty)
            && currentError() == .none
    }

    override func setupUI() {
        view.backgroundColor = UIColor.theme.primary
        setupHeader()
        setupScrollView()
        setupNameSection()
        if isFlash {
            setupContentSection()
        } else {
            setupCallout()
        }
        if let editingItem {
            nameField.text = editingItem.menuName
            if isFlash {
                contentTextView.text = editingItem.actionMsg
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAutofocus else { return }
        didAutofocus = true
        if editingItem == nil {
            nameField.becomeFirstResponder()
        }
    }

    override func applyTheme() {
        let t = UIColor.theme
        view.backgroundColor = t.primary
        titleLabel.textColor = t.textStrong
        backButton.tintColor = t.textStrong
        submitIndicator.color = t.textDisabled

        nameTitleLabel.attributedText = requiredTitle(isFlash ? L(L10n.QuickAction.commandName) : L(L10n.QuickAction.menuName))
        nameContainer.backgroundColor = t.secondary
        nameContainer.layer.borderColor = t.border.cgColor
        slashLabel.textColor = t.textStrong
        nameField.textColor = t.textStrong
        nameField.attributedPlaceholder = NSAttributedString(
            string: isFlash ? "example" : "menu-name",
            attributes: [.foregroundColor: t.textDisabled]
        )
        nameHelperLabel.textColor = t.textDisabled

        contentTitleLabel.attributedText = requiredTitle(L(L10n.QuickAction.messageContent))
        contentTextView.backgroundColor = t.secondary
        contentTextView.layer.borderColor = t.border.cgColor
        contentTextView.textColor = t.textStrong
        contentPlaceholderLabel.textColor = t.textDisabled
        contentHelperLabel.textColor = t.textDisabled

        calloutView.backgroundColor = QuickActionPalette.typeBadge.withAlphaComponent(0.1)
        calloutView.layer.borderColor = QuickActionPalette.typeBadge.withAlphaComponent(0.2).cgColor
        calloutIconView.tintColor = QuickActionPalette.typeBadgeText
        calloutTitleLabel.textColor = QuickActionPalette.typeBadgeText
        calloutBodyLabel.textColor = QuickActionPalette.calloutBody.withAlphaComponent(0.8)

        updateFormState()
    }

    private func requiredTitle(_ title: String) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: 14.sf, weight: .semibold)
        let text = NSMutableAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: UIColor.theme.textStrong
        ])
        text.append(NSAttributedString(string: " *", attributes: [
            .font: font,
            .foregroundColor: UIColor(rgb: 0xe44141)
        ]))
        return text
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate), for: .normal)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        let titleKey: String
        switch (kind, editingItem == nil) {
        case (.flashMessage, true): titleKey = L10n.QuickAction.createFlashMessage
        case (.flashMessage, false): titleKey = L10n.QuickAction.editFlashMessage
        case (.quickMenu, true): titleKey = L10n.QuickAction.createQuickMenu
        case (.quickMenu, false): titleKey = L10n.QuickAction.editQuickMenu
        }
        titleLabel.text = L(titleKey)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        titleLabel.textAlignment = .center

        submitButton.setTitle(editingItem == nil ? L(L10n.QuickAction.create) : L(L10n.QuickAction.update), for: .normal)
        submitButton.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)

        submitIndicator.hidesWhenStopped = true

        [backButton, titleLabel, submitButton, submitIndicator].forEach {
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
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 4.sw),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: submitButton.leadingAnchor, constant: -4.sw),

            submitButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16.sw),
            submitButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            submitIndicator.centerXAnchor.constraint(equalTo: submitButton.centerXAnchor),
            submitIndicator.centerYAnchor.constraint(equalTo: submitButton.centerYAnchor)
        ])
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = 24.sh
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16.sh),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16.sw),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16.sw),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -40.sh),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32.sw)
        ])
    }

    private func makeSection(title: UILabel, field: UIView, helper: UILabel, error: UILabel, helperText: String) -> UIStackView {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = 8.sh

        title.numberOfLines = 0
        section.addArrangedSubview(title)
        section.addArrangedSubview(field)

        helper.text = helperText
        helper.font = .systemFont(ofSize: 12.sf)
        helper.numberOfLines = 0
        section.addArrangedSubview(helper)
        section.setCustomSpacing(4.sh, after: helper)

        error.font = .systemFont(ofSize: 12.sf)
        error.textColor = .mezonError
        error.numberOfLines = 0
        error.isHidden = true
        section.addArrangedSubview(error)
        return section
    }

    private func setupNameSection() {
        nameContainer.layer.cornerRadius = 12
        nameContainer.layer.borderWidth = 1
        nameContainer.translatesAutoresizingMaskIntoConstraints = false

        slashLabel.text = "/"
        slashLabel.font = .monospacedSystemFont(ofSize: 16.sf, weight: .regular)
        slashLabel.isHidden = !isFlash
        slashLabel.setContentHuggingPriority(.required, for: .horizontal)
        slashLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        nameField.font = .systemFont(ofSize: 16.sf)
        nameField.autocapitalizationType = .none
        nameField.autocorrectionType = .no
        nameField.spellCheckingType = .no
        nameField.returnKeyType = isFlash ? .next : .done
        nameField.delegate = self
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)

        let row = UIStackView(arrangedSubviews: [slashLabel, nameField])
        row.axis = .horizontal
        row.spacing = 8.sw
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        nameContainer.addSubview(row)

        NSLayoutConstraint.activate([
            nameContainer.heightAnchor.constraint(equalToConstant: 48.sh),
            row.leadingAnchor.constraint(equalTo: nameContainer.leadingAnchor, constant: 12.sw),
            row.trailingAnchor.constraint(equalTo: nameContainer.trailingAnchor, constant: -12.sw),
            row.topAnchor.constraint(equalTo: nameContainer.topAnchor),
            row.bottomAnchor.constraint(equalTo: nameContainer.bottomAnchor),
            nameField.heightAnchor.constraint(equalTo: row.heightAnchor)
        ])

        let section = makeSection(
            title: nameTitleLabel,
            field: nameContainer,
            helper: nameHelperLabel,
            error: nameErrorLabel,
            helperText: isFlash ? L(L10n.QuickAction.commandNameHelper) : L(L10n.QuickAction.menuNameHelper)
        )
        stackView.addArrangedSubview(section)
    }

    private func setupContentSection() {
        contentTextView.font = .systemFont(ofSize: 16.sf)
        contentTextView.layer.cornerRadius = 12
        contentTextView.layer.borderWidth = 1
        contentTextView.textContainerInset = UIEdgeInsets(top: 12.sh, left: 8.sw, bottom: 12.sh, right: 8.sw)
        contentTextView.delegate = self
        contentTextView.translatesAutoresizingMaskIntoConstraints = false
        contentTextView.heightAnchor.constraint(equalToConstant: 150.sh).isActive = true

        contentPlaceholderLabel.text = L(L10n.QuickAction.messageContentPlaceholder)
        contentPlaceholderLabel.font = .systemFont(ofSize: 16.sf)
        contentPlaceholderLabel.numberOfLines = 0
        contentPlaceholderLabel.isUserInteractionEnabled = false
        contentPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        contentTextView.addSubview(contentPlaceholderLabel)

        NSLayoutConstraint.activate([
            contentPlaceholderLabel.topAnchor.constraint(equalTo: contentTextView.topAnchor, constant: 12.sh),
            contentPlaceholderLabel.leadingAnchor.constraint(equalTo: contentTextView.leadingAnchor, constant: 13.sw),
            contentPlaceholderLabel.widthAnchor.constraint(equalTo: contentTextView.widthAnchor, constant: -26.sw)
        ])

        let section = makeSection(
            title: contentTitleLabel,
            field: contentTextView,
            helper: contentHelperLabel,
            error: contentErrorLabel,
            helperText: L(L10n.QuickAction.messageContentDescription)
        )
        stackView.addArrangedSubview(section)
    }

    private func setupCallout() {
        calloutView.layer.cornerRadius = 12
        calloutView.layer.borderWidth = 1

        calloutIconView.image = UIImage(systemName: "info.circle.fill")?.withRenderingMode(.alwaysTemplate)
        calloutIconView.contentMode = .scaleAspectFit

        calloutTitleLabel.text = L(L10n.QuickAction.botEventTrigger)
        calloutTitleLabel.font = .systemFont(ofSize: 14.sf, weight: .medium)
        calloutTitleLabel.numberOfLines = 0

        calloutBodyLabel.text = L(L10n.QuickAction.botEventDescription)
        calloutBodyLabel.font = .systemFont(ofSize: 12.sf)
        calloutBodyLabel.numberOfLines = 0

        [calloutIconView, calloutTitleLabel, calloutBodyLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            calloutView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            calloutIconView.leadingAnchor.constraint(equalTo: calloutView.leadingAnchor, constant: 12.sw),
            calloutIconView.topAnchor.constraint(equalTo: calloutView.topAnchor, constant: 13.sh),
            calloutIconView.widthAnchor.constraint(equalToConstant: 16.swh),
            calloutIconView.heightAnchor.constraint(equalToConstant: 16.swh),

            calloutTitleLabel.leadingAnchor.constraint(equalTo: calloutIconView.trailingAnchor, constant: 8.sw),
            calloutTitleLabel.trailingAnchor.constraint(equalTo: calloutView.trailingAnchor, constant: -12.sw),
            calloutTitleLabel.topAnchor.constraint(equalTo: calloutView.topAnchor, constant: 12.sh),

            calloutBodyLabel.leadingAnchor.constraint(equalTo: calloutTitleLabel.leadingAnchor),
            calloutBodyLabel.trailingAnchor.constraint(equalTo: calloutTitleLabel.trailingAnchor),
            calloutBodyLabel.topAnchor.constraint(equalTo: calloutTitleLabel.bottomAnchor, constant: 4.sh),
            calloutBodyLabel.bottomAnchor.constraint(equalTo: calloutView.bottomAnchor, constant: -12.sh)
        ])

        stackView.addArrangedSubview(calloutView)
    }

    private func currentError() -> FormError {
        let name = draftName
        if !name.isEmpty {
            if !QuickMenuNameRules.isValidName(name) {
                return .invalidName
            }
            if QuickMenuNameRules.nameExists(name, in: existingItems, excludingId: editingItem?.id) {
                return .duplicateName
            }
        }
        if isFlash {
            let content = draftContent
            if !content.isEmpty && !QuickMenuNameRules.isValidActionMsg(content) {
                return .messageTooLong
            }
        }
        return .none
    }

    private func revalidate() {
        formError = currentError()
        updateFormState()
    }

    private func updateFormState() {
        switch formError {
        case .invalidName:
            nameErrorLabel.text = L(L10n.QuickAction.errorInvalidName)
        case .duplicateName:
            nameErrorLabel.text = L(L10n.QuickAction.errorDuplicateName)
        case .messageTooLong:
            contentErrorLabel.text = L(L10n.QuickAction.errorMessageTooLong)
        case .none:
            break
        }
        nameErrorLabel.isHidden = !(formError == .invalidName || formError == .duplicateName)
        contentErrorLabel.isHidden = formError != .messageTooLong
        contentPlaceholderLabel.isHidden = !contentTextView.text.isEmpty

        let enabled = canSubmit
        submitButton.isEnabled = enabled
        submitButton.tintColor = UIColor.theme.bgViolet
        submitButton.alpha = enabled ? 1 : 0.5
        submitButton.isHidden = isSubmitting
        if isSubmitting {
            submitIndicator.startAnimating()
        } else {
            submitIndicator.stopAnimating()
        }
        backButton.isEnabled = !isSubmitting
    }

    @objc private func nameChanged() {
        revalidate()
    }

    @objc private func backTapped() {
        guard !isSubmitting else { return }
        navigationController?.popViewController(animated: true)
    }

    @objc private func submitTapped() {
        submit()
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let keyboardFrame = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - keyboardFrame.minY - view.safeAreaInsets.bottom)
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
    }

    private func submit() {
        revalidate()
        guard canSubmit else { return }
        let name = draftName
        let actionMsg = isFlash ? draftContent : Self.botEventAction
        let isNew = editingItem == nil
        isSubmitting = true
        updateFormState()
        view.endEditing(true)

        let item = makeItem(name: name, actionMsg: actionMsg)

        Task { [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                self.isSubmitting = false
                self.updateFormState()
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            do {
                if isNew {
                    try await MezonHTTPClient.shared.addQuickMenuAccess(item, token: token)
                } else {
                    try await MezonHTTPClient.shared.updateQuickMenuAccess(item, token: token)
                }
                self.onSaved?(item, isNew)
                self.navigationController?.popViewController(animated: true)
            } catch {
                self.isSubmitting = false
                self.updateFormState()
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func makeItem(name: String, actionMsg: String) -> Mezon_Api_QuickMenuAccess {
        var item = Mezon_Api_QuickMenuAccess()
        item.id = editingItem?.id ?? ClientSnowflakeID.next()
        item.clanID = clanId
        item.channelID = channelId
        item.menuName = name
        item.actionMsg = actionMsg
        item.menuType = kind.menuType
        return item
    }
}

extension QuickActionEditViewController: UITextFieldDelegate, UITextViewDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if isFlash {
            contentTextView.becomeFirstResponder()
        } else {
            submit()
        }
        return false
    }

    func textViewDidChange(_ textView: UITextView) {
        revalidate()
    }
}
