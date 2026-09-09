import UIKit
import ImageIO

final class EventEditorViewController: UIViewController, UITextFieldDelegate, UITextViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let context: AccountContext
    private let clanId: Int64
    private let channels: [Mezon_Api_ChannelDescription]
    private let original: Mezon_Api_EventManagement?
    private var draft: EventEditorDraft
    var onSaved: ((Mezon_Api_EventManagement?) -> Void)?

    private let accent = UIColor(red: 0.39, green: 0.38, blue: 0.91, alpha: 1)
    private let card = UIView()
    private let header = UIStackView()
    private let body = UIStackView()
    private let scroll = UIScrollView()
    private let footer = UIStackView()
    private let stepLabel = UILabel()
    private let nextButton = EventEditorButton()
    private let backButton = EventEditorButton()
    private let closeButton = EventEditorButton()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()
    private var progressBars: [UIView] = []
    private var progressLabels: [UILabel] = []
    private var optionDescriptions: [UILabel] = []
    private var cardHeight: NSLayoutConstraint!
    private var cardCenter: NSLayoutConstraint!
    private var step = 0
    private var keyboardHeight: CGFloat = 0
    private var submitting = false
    private var uploading = false
    private var uploadTask: Task<Void, Never>?
    private var submitTask: Task<Void, Never>?
    private var dismissed = false

    private let nameField = UITextField()
    private let addressField = UITextField()
    private let descriptionView = UITextView()
    private let descriptionPlaceholder = UILabel()
    private let descriptionCount = UILabel()
    private let coverContainer = UIStackView()
    private let nameError = UILabel()
    private let addressError = UILabel()
    private let startError = UILabel()
    private let endError = UILabel()
    private var dateFields: [EventEditorFieldButton] = []
    private var repeatField: EventEditorFieldButton?
    private var previewImage: UIImage?

    init(context: AccountContext, clanId: Int64, channels: [Mezon_Api_ChannelDescription], event: Mezon_Api_EventManagement? = nil) {
        self.context = context
        self.clanId = clanId
        self.channels = channels
        self.original = event
        self.draft = EventEditorDraft(event: event)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit {
        uploadTask?.cancel()
        submitTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildShell()
        configureTextInputs()
        renderStep()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: ThemeManager.didChangeNotification, object: nil)
    }

    private func buildShell() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        card.backgroundColor = EventEditorPalette.surface
        card.layer.cornerRadius = 20
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        header.axis = .vertical
        header.spacing = 20
        header.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        header.isLayoutMarginsRelativeArrangement = true
        let title = label(L(original == nil ? L10n.EventEditor.create : L10n.EventEditor.edit), size: 20, weight: .bold)
        stepLabel.font = .systemFont(ofSize: 13)
        stepLabel.textColor = UIColor.theme.text
        let titles = UIStackView(arrangedSubviews: [title, stepLabel])
        titles.axis = .vertical
        titles.spacing = 6
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22)), for: .normal)
        closeButton.tintColor = UIColor.theme.text
        closeButton.accessibilityLabel = L(L10n.EventEditor.close)
        closeButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        closeButton.action = { [weak self] in self?.close() }
        let top = UIStackView(arrangedSubviews: [titles, closeButton])
        top.alignment = .center
        header.addArrangedSubview(top)
        let progress = UIStackView()
        progress.spacing = 8
        progress.distribution = .fillEqually
        for key in [L10n.EventEditor.location, L10n.EventEditor.details, L10n.EventEditor.preview] {
            let bar = UIView()
            bar.layer.cornerRadius = 2
            bar.heightAnchor.constraint(equalToConstant: 4).isActive = true
            let text = label(L(key), size: 12)
            let column = UIStackView(arrangedSubviews: [bar, text])
            column.axis = .vertical
            column.spacing = 10
            progress.addArrangedSubview(column)
            progressBars.append(bar)
            progressLabels.append(text)
        }
        header.addArrangedSubview(progress)
        scroll.keyboardDismissMode = .interactive
        scroll.showsVerticalScrollIndicator = false
        body.axis = .vertical
        body.spacing = 16
        body.layoutMargins = UIEdgeInsets(top: 4, left: 20, bottom: 20, right: 20)
        body.isLayoutMarginsRelativeArrangement = true
        body.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(body)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            body.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            body.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        footer.axis = .vertical
        footer.spacing = 10
        footer.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        footer.isLayoutMarginsRelativeArrangement = true
        configureError(errorLabel)
        footer.addArrangedSubview(errorLabel)
        let actions = UIStackView(arrangedSubviews: [backButton, nextButton])
        actions.spacing = 12
        actions.distribution = .fillEqually
        for button in [backButton, nextButton] {
            button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
            button.titleLabel?.numberOfLines = 2
            button.titleLabel?.textAlignment = .center
            button.layer.cornerRadius = 12
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
            button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        }
        backButton.layer.borderWidth = 1.5
        backButton.layer.borderColor = accent.cgColor
        backButton.setTitleColor(accent, for: .normal)
        backButton.action = { [weak self] in
            guard let self, !self.submitting else { return }
            if self.step == 0 { self.close() } else { self.step -= 1; self.renderStep() }
        }
        nextButton.setTitleColor(.white, for: .normal)
        nextButton.setTitleColor(UIColor.theme.textDisabled, for: .disabled)
        nextButton.action = { [weak self] in self?.advance() }
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        nextButton.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: nextButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor)
        ])
        footer.addArrangedSubview(actions)
        let separator = UIView()
        separator.backgroundColor = EventEditorPalette.border
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let root = UIStackView(arrangedSubviews: [header, scroll, separator, footer])
        root.axis = .vertical
        root.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(root)
        cardHeight = card.heightAnchor.constraint(equalToConstant: 600)
        cardCenter = card.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        let width = card.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -32)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            cardCenter, cardHeight, width,
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
            root.topAnchor.constraint(equalTo: card.topAnchor), root.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: card.leadingAnchor), root.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = card.bounds.width
        guard width > 0 else { return }
        for description in optionDescriptions {
            description.preferredMaxLayoutWidth = max(1, width - 146)
        }
        let fitting = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let bodyHeight = body.systemLayoutSizeFitting(fitting, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let headerHeight = header.systemLayoutSizeFitting(fitting, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let footerHeight = footer.systemLayoutSizeFitting(fitting, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let safeHeight = view.safeAreaLayoutGuide.layoutFrame.height
        let available = max(0, safeHeight - keyboardHeight - 24)
        let height = min(bodyHeight + headerHeight + footerHeight + 1, min(780, available))
        if abs(cardHeight.constant - height) > 0.5 { cardHeight.constant = height }
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let localFrame = view.convert(frame, from: nil)
        keyboardHeight = max(0, view.safeAreaLayoutGuide.layoutFrame.maxY - localFrame.minY)
        cardCenter.constant = -keyboardHeight / 2
        view.setNeedsLayout()
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
        if nameField.isFirstResponder { scroll.scrollRectToVisible(nameField.convert(nameField.bounds, to: body).insetBy(dx: 0, dy: -12), animated: true) }
        if descriptionView.isFirstResponder { scroll.scrollRectToVisible(descriptionView.convert(descriptionView.bounds, to: body).insetBy(dx: 0, dy: -12), animated: true) }
    }

    @objc private func themeChanged() {
        card.backgroundColor = EventEditorPalette.surface
        configureTextInputColors()
        renderStep(preservingScrollPosition: true)
    }

    private func configureTextInputs() {
        for field in [nameField, addressField] {
            field.font = .systemFont(ofSize: 16)
            field.clearButtonMode = .whileEditing
            field.borderStyle = .none
            field.layer.cornerRadius = 12
            field.layer.borderWidth = 1
            let inset = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 48))
            field.leftView = inset
            field.leftViewMode = .always
            field.heightAnchor.constraint(equalToConstant: 48).isActive = true
            field.delegate = self
            field.addTarget(self, action: #selector(textChanged), for: .editingChanged)
            field.returnKeyType = .done
        }
        nameField.accessibilityLabel = L(L10n.EventEditor.name)
        nameField.text = draft.title
        addressField.placeholder = L(L10n.EventEditor.addressPlaceholder)
        addressField.accessibilityLabel = L(L10n.EventEditor.address)
        addressField.text = draft.address
        descriptionView.font = .systemFont(ofSize: 15)
        descriptionView.delegate = self
        descriptionView.text = draft.description
        descriptionView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        descriptionView.layer.cornerRadius = 12
        descriptionView.layer.borderWidth = 1
        descriptionView.heightAnchor.constraint(equalToConstant: 100).isActive = true
        descriptionView.accessibilityLabel = L(L10n.EventEditor.description)
        descriptionPlaceholder.text = L(L10n.EventEditor.descriptionPlaceholder)
        descriptionPlaceholder.font = .systemFont(ofSize: 15)
        descriptionPlaceholder.numberOfLines = 0
        descriptionPlaceholder.isUserInteractionEnabled = false
        descriptionPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        descriptionView.addSubview(descriptionPlaceholder)
        NSLayoutConstraint.activate([
            descriptionPlaceholder.topAnchor.constraint(equalTo: descriptionView.topAnchor, constant: 12),
            descriptionPlaceholder.leadingAnchor.constraint(equalTo: descriptionView.leadingAnchor, constant: 12),
            descriptionPlaceholder.widthAnchor.constraint(equalTo: descriptionView.widthAnchor, constant: -24)
        ])
        descriptionCount.font = .systemFont(ofSize: 11)
        descriptionCount.textAlignment = .right
        for error in [nameError, addressError, startError, endError] { configureError(error) }
        configureTextInputColors()
    }

    private func configureTextInputColors() {
        for field in [nameField, addressField] {
            field.textColor = UIColor.theme.textStrong
            field.backgroundColor = EventEditorPalette.field
            field.layer.borderColor = EventEditorPalette.border.cgColor
            field.tintColor = accent
        }
        nameField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.EventEditor.namePlaceholder),
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )
        descriptionView.textColor = UIColor.theme.textStrong
        descriptionView.backgroundColor = EventEditorPalette.field
        descriptionView.layer.borderColor = EventEditorPalette.border.cgColor
        descriptionPlaceholder.textColor = UIColor.theme.textDisabled
        descriptionCount.textColor = UIColor.theme.text
    }

    private func renderStep(preservingScrollPosition: Bool = false) {
        let preservedOffset = scroll.contentOffset
        view.endEditing(true)
        body.arrangedSubviews.forEach { body.removeArrangedSubview($0); $0.removeFromSuperview() }
        errorLabel.isHidden = true
        optionDescriptions.removeAll()
        stepLabel.text = L(L10n.EventEditor.step, step + 1)
        for index in 0..<3 {
            progressBars[index].backgroundColor = index <= step ? accent : EventEditorPalette.border
            progressLabels[index].textColor = index == step ? accent : UIColor.theme.text
            progressLabels[index].font = .systemFont(ofSize: 12, weight: index == step ? .bold : .regular)
            progressLabels[index].accessibilityTraits = index == step ? [.staticText, .selected] : .staticText
        }
        if step == 0 { buildLocation() }
        else if step == 1 { buildDetails() }
        else { buildPreview() }
        refreshValidation()
        view.setNeedsLayout()
        if preservingScrollPosition {
            view.layoutIfNeeded()
            let minimumY = -scroll.adjustedContentInset.top
            let maximumY = max(
                minimumY,
                scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
            )
            let restoredY = min(max(preservedOffset.y, minimumY), maximumY)
            scroll.setContentOffset(CGPoint(x: preservedOffset.x, y: restoredY), animated: false)
        } else {
            scroll.setContentOffset(.zero, animated: false)
            UIAccessibility.post(notification: .screenChanged, argument: stepLabel)
        }
    }

    private func buildLocation() {
        body.addArrangedSubview(label(L(L10n.EventEditor.chooseType), size: 17, weight: .bold))
        body.addArrangedSubview(label(L(L10n.EventEditor.chooseTypeSubtitle), size: 13))
        let options: [(EventLocationType, String, String, String)] = [
            (.voice, L10n.EventEditor.voice, L10n.EventEditor.voiceSubtitle, "speaker.wave.2.fill"),
            (.location, L10n.EventEditor.elsewhere, L10n.EventEditor.elsewhereSubtitle, "mappin.and.ellipse"),
            (.external, L10n.EventEditor.external, L10n.EventEditor.externalSubtitle, "lock.fill")
        ]
        let voices = EventEditorAccess.voiceChannels(channels)
        let optionStack = UIStackView()
        optionStack.axis = .vertical
        optionStack.spacing = 8
        for (type, title, subtitle, symbol) in options {
            if let original, (type == .external) != original.isPrivate { continue }
            let selected = draft.locationType == type
            let enabled = type != .voice || !voices.isEmpty || draft.voiceChannelId != 0
            let button = EventEditorButton()
            button.layer.cornerRadius = 12
            button.layer.borderWidth = 1
            button.layer.borderColor = (selected ? accent : EventEditorPalette.border).cgColor
            button.backgroundColor = selected ? accent.withAlphaComponent(0.1) : EventEditorPalette.field
            button.isEnabled = enabled
            button.alpha = enabled ? 1 : 0.45
            let icon = UIImageView(image: UIImage(systemName: symbol))
            icon.tintColor = UIColor.theme.textStrong
            icon.contentMode = .scaleAspectFit
            icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
            let description = label(L(subtitle), size: 13)
            description.setContentCompressionResistancePriority(.required, for: .vertical)
            description.preferredMaxLayoutWidth = max(1, min(560, view.bounds.width - 32) - 146)
            optionDescriptions.append(description)
            let texts = UIStackView(arrangedSubviews: [label(L(title), size: 16, weight: .bold), description])
            texts.axis = .vertical
            texts.spacing = 6
            let radio = UIImageView(image: UIImage(systemName: selected ? "largecircle.fill.circle" : "circle"))
            radio.contentMode = .scaleAspectFit
            radio.tintColor = selected ? accent : UIColor.theme.textDisabled
            radio.widthAnchor.constraint(equalToConstant: 26).isActive = true
            radio.heightAnchor.constraint(equalToConstant: 26).isActive = true
            let row = UIStackView(arrangedSubviews: [icon, texts, radio])
            row.spacing = 14
            row.alignment = .center
            row.isUserInteractionEnabled = false
            row.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(row)
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: button.topAnchor, constant: 16), row.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -16),
                row.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 14), row.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14)
            ])
            button.accessibilityLabel = "\(L(title)). \(L(subtitle))"
            button.accessibilityTraits = selected ? [.button, .selected] : .button
            button.action = { [weak self] in
                guard let self else { return }
                self.draft.locationType = type
                self.renderStep(preservingScrollPosition: true)
            }
            optionStack.addArrangedSubview(button)
        }
        body.addArrangedSubview(optionStack)
        if draft.locationType == .voice {
            let field = EventEditorFieldButton(caption: L(L10n.EventEditor.voice))
            field.setValue(channelLabel(draft.voiceChannelId) ?? L(L10n.EventEditor.pickChannel))
            field.action = { [weak self] in self?.pickChannel(voice: true) }
            body.addArrangedSubview(field)
        } else if draft.locationType == .location {
            body.addArrangedSubview(labeledField(L(L10n.EventEditor.address) + " *", field: addressField, error: addressError))
        }
        if draft.locationType != .external {
            let field = EventEditorFieldButton(caption: L(L10n.EventEditor.announcement))
            field.setValue(channelLabel(draft.announcementChannelId) ?? L(L10n.EventEditor.pickChannel))
            field.action = { [weak self] in self?.pickChannel(voice: false) }
            body.addArrangedSubview(field)
        }
    }

    private func buildDetails() {
        body.addArrangedSubview(label(L(L10n.EventEditor.detailsTitle), size: 17, weight: .bold))
        body.addArrangedSubview(label(L(L10n.EventEditor.detailsSubtitle), size: 13))
        body.addArrangedSubview(labeledField(L(L10n.EventEditor.name) + " *", field: nameField, error: nameError))
        dateFields = [L10n.EventEditor.startDate, L10n.EventEditor.startTime, L10n.EventEditor.endDate, L10n.EventEditor.endTime].enumerated().map { index, key in
            let field = EventEditorFieldButton(caption: L(key))
            field.action = { [weak self] in self?.pickDate(index) }
            return field
        }
        let dates = UIStackView()
        dates.axis = .vertical
        dates.spacing = 8
        for index in [0, 2] {
            let row = UIStackView(arrangedSubviews: [dateFields[index], dateFields[index + 1]])
            row.distribution = .fillEqually
            row.spacing = 8
            dates.addArrangedSubview(row)
            dates.addArrangedSubview(index == 0 ? startError : endError)
        }
        body.addArrangedSubview(dates)
        let repeatField = EventEditorFieldButton(caption: L(L10n.EventEditor.repeatLabel))
        self.repeatField = repeatField
        repeatField.action = { [weak self] in self?.pickRepeat() }
        body.addArrangedSubview(repeatField)
        let description = UIStackView(arrangedSubviews: [label(L(L10n.EventEditor.description), size: 15, weight: .bold), descriptionView, descriptionCount])
        description.axis = .vertical
        description.spacing = 6
        body.addArrangedSubview(description)
        body.addArrangedSubview(label(L(L10n.EventEditor.cover), size: 14, weight: .bold))
        body.addArrangedSubview(coverContainer)
        refreshCover()
        refreshDateLabels()
    }

    private func refreshCover() {
        coverContainer.arrangedSubviews.forEach {
            coverContainer.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        coverContainer.addArrangedSubview(makeCover())
    }

    private func makeCover() -> UIView {
        let wrapper = UIView()
        wrapper.backgroundColor = EventEditorPalette.field
        wrapper.layer.cornerRadius = 12
        wrapper.layer.borderWidth = 1
        wrapper.layer.borderColor = EventEditorPalette.border.cgColor
        wrapper.clipsToBounds = true
        wrapper.heightAnchor.constraint(equalToConstant: 128).isActive = true
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(imageView)
        loadCover(into: imageView)
        let pick = EventEditorButton()
        pick.translatesAutoresizingMaskIntoConstraints = false
        pick.setTitle(draft.logoURL.isEmpty ? L(L10n.EventEditor.addCover) : "", for: .normal)
        pick.titleLabel?.font = .systemFont(ofSize: 13)
        pick.titleLabel?.numberOfLines = 0
        pick.setTitleColor(accent, for: .normal)
        pick.accessibilityLabel = L(L10n.EventEditor.addCover)
        pick.isEnabled = !uploading
        pick.action = { [weak self] in self?.pickCover() }
        wrapper.addSubview(pick)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: wrapper.topAnchor), imageView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor), imageView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            pick.topAnchor.constraint(equalTo: wrapper.topAnchor), pick.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            pick.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor), pick.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor)
        ])
        if !draft.logoURL.isEmpty {
            let remove = EventEditorButton()
            remove.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
            remove.tintColor = .systemRed
            remove.accessibilityLabel = L(L10n.EventEditor.removeCover)
            remove.translatesAutoresizingMaskIntoConstraints = false
            remove.isEnabled = !uploading
            remove.action = { [weak self] in
                guard let self else { return }
                self.draft.logoURL = ""
                self.previewImage = nil
                self.refreshCover()
                self.refreshValidation()
            }
            wrapper.addSubview(remove)
            NSLayoutConstraint.activate([
                remove.widthAnchor.constraint(equalToConstant: 44), remove.heightAnchor.constraint(equalToConstant: 44),
                remove.topAnchor.constraint(equalTo: wrapper.topAnchor), remove.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor)
            ])
        }
        if uploading {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(indicator)
            NSLayoutConstraint.activate([indicator.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor), indicator.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)])
            indicator.startAnimating()
        }
        return wrapper
    }

    private func buildPreview() {
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 10
        content.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        content.isLayoutMarginsRelativeArrangement = true
        let wrapper = UIView()
        wrapper.backgroundColor = EventEditorPalette.field
        wrapper.layer.cornerRadius = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: wrapper.topAnchor), content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor), content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor)
        ])
        content.addArrangedSubview(iconRow("calendar", text: formatted(draft.start, template: "EEE MMM d jm")))
        if !draft.logoURL.isEmpty {
            let image = UIImageView()
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            image.layer.cornerRadius = 8
            image.heightAnchor.constraint(equalToConstant: 112).isActive = true
            loadCover(into: image)
            content.addArrangedSubview(image)
        }
        let badgeKey = draft.locationType == .external ? L10n.EventMenu.privateEvent : (draft.channelId == 0 ? L10n.EventMenu.clanEvent : L10n.EventMenu.channelEvent)
        let badgeColor = draft.locationType == .external ? EventDisplayHelper.externalEventBadgeColor : (draft.channelId == 0 ? EventDisplayHelper.clanEventBadgeColor : EventDisplayHelper.channelEventBadgeColor)
        let badge = EventDisplayHelper.makeBadgeView(text: L(badgeKey), color: badgeColor)
        let badgeRow = UIStackView(arrangedSubviews: [badge, UIView()])
        badge.setContentHuggingPriority(.required, for: .horizontal)
        content.addArrangedSubview(badgeRow)
        content.addArrangedSubview(label(draft.title, size: 20, weight: .bold))
        if !draft.description.isEmpty { content.addArrangedSubview(label(draft.description, size: 14)) }
        let location: String
        switch draft.locationType {
        case .voice: location = channelLabel(draft.voiceChannelId) ?? L(L10n.EventMenu.privateRoom)
        case .location: location = draft.address
        default: location = L(L10n.EventMenu.privateEvent)
        }
        content.addArrangedSubview(iconRow(draft.locationType == .location ? "mappin.and.ellipse" : (draft.locationType == .external ? "lock.fill" : "speaker.wave.2.fill"), text: location))
        if draft.repeatType != EventRepeatType.doesNotRepeat { content.addArrangedSubview(iconRow("repeat", text: repeatLabel())) }
        if let channel = channelLabel(draft.channelId), draft.channelId != 0 {
            content.addArrangedSubview(label(L(L10n.EventMenu.channelAudience, channel), size: 12))
        }
        body.addArrangedSubview(wrapper)
        body.addArrangedSubview(label(L(L10n.EventEditor.previewTitle), size: 17, weight: .bold))
        let key = original != nil ? L10n.EventEditor.previewEdit : (draft.locationType == .voice ? L10n.EventEditor.previewVoice : (draft.locationType == .external ? L10n.EventEditor.previewExternal : L10n.EventEditor.previewLocation))
        body.addArrangedSubview(label(L(key), size: 14))
    }

    @objc private func textChanged() {
        draft.title = nameField.text ?? ""
        draft.address = addressField.text ?? ""
        refreshValidation()
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard textField === nameField else { return true }
        let current = textField.text ?? ""
        let proposed = (current as NSString).replacingCharacters(in: range, with: string)
        return proposed.utf16.count <= EventEditorDraft.maximumTitleLength || proposed.utf16.count < current.utf16.count
    }
    func textViewDidChange(_ textView: UITextView) {
        if textView.markedTextRange == nil, textView.text.utf16.count > 255 {
            var value = textView.text ?? ""
            while value.utf16.count > 255 { value.removeLast() }
            textView.text = value
        }
        draft.description = textView.text
        refreshValidation()
    }

    private func refreshValidation() {
        setError(nameError, draft.title.isEmpty ? nil : draft.titleError)
        setError(addressError, draft.address.utf16.count > 100 ? L(L10n.EventEditor.addressError) : nil)
        setError(startError, draft.startError())
        setError(endError, draft.endError())
        descriptionPlaceholder.isHidden = !draft.description.isEmpty
        descriptionCount.text = "\(draft.description.utf16.count)/255"
        let valid: Bool
        if step == 0 { valid = draft.isLocationValid }
        else { valid = draft.isLocationValid && draft.isDetailsValid() && (step != 2 || original.map { draft.hasChanges(from: $0) } ?? true) }
        nextButton.isEnabled = valid && !submitting && !uploading
        nextButton.backgroundColor = nextButton.isEnabled ? accent : EventEditorPalette.border
        let title = step < 2 ? L10n.EventEditor.next : (original == nil ? L10n.EventEditor.create : L10n.EventEditor.update)
        nextButton.setTitle(submitting ? "" : L(title), for: .normal)
        nextButton.accessibilityLabel = L(title)
        backButton.setTitle(L(step == 0 ? L10n.EventEditor.cancel : L10n.EventEditor.back), for: .normal)
        backButton.isEnabled = !submitting
        closeButton.isEnabled = !submitting
        body.isUserInteractionEnabled = !submitting
        if submitting { spinner.startAnimating() } else { spinner.stopAnimating() }
        view.setNeedsLayout()
    }

    private func advance() {
        view.endEditing(true)
        refreshValidation() 
        guard nextButton.isEnabled else { return }
        if step < 2 { step += 1; renderStep() } else { submit() }
    }

    private func pickChannel(voice: Bool) {
        view.endEditing(true)
        let options = voice ? EventEditorAccess.voiceChannels(channels) : EventEditorAccess.announcementChannels(channels)
        let choices = options.map { EventEditorChoiceViewController.Choice(id: $0.channelID, title: $0.channelLabel, icon: $0.channelListIconAssetName()) }
        let vc = EventEditorChoiceViewController(title: L(voice ? L10n.EventEditor.voice : L10n.EventEditor.announcement), choices: choices, selectedId: voice ? draft.voiceChannelId : draft.announcementChannelId) { [weak self] id in
            guard let self else { return }
            if voice {
                self.draft.voiceChannelId = id
            } else {
                self.draft.announcementChannelId = self.draft.announcementChannelId == id ? 0 : id
            }
            self.renderStep(preservingScrollPosition: true)
        }
        present(vc, animated: true)
    }

    private func pickDate(_ index: Int) {
        view.endEditing(true)
        let isStart = index < 2
        let isDate = index % 2 == 0
        let current = isStart ? draft.start : draft.end
        let calendar = Calendar.current
        let minimum = isDate ? calendar.startOfDay(for: isStart ? Date() : draft.start) : nil
        let vc = EventEditorDateViewController(title: dateFields[index].captionLabel.text ?? "", date: current, mode: isDate ? .date : .time, minimum: minimum) { [weak self] picked in
            guard let self else { return }
            let date = isDate ? picked : current
            let time = isDate ? current : picked
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            let clock = calendar.dateComponents([.hour, .minute], from: time)
            components.hour = clock.hour
            components.minute = clock.minute
            components.second = 0
            guard let combined = calendar.date(from: components) else { return }
            if isStart {
                self.draft.start = combined
                if isDate && calendar.startOfDay(for: combined) > calendar.startOfDay(for: self.draft.end) {
                    var endComponents = calendar.dateComponents([.year, .month, .day], from: combined)
                    let endClock = calendar.dateComponents([.hour, .minute], from: self.draft.end)
                    endComponents.hour = endClock.hour
                    endComponents.minute = endClock.minute
                    endComponents.second = 0
                    if let adjustedEnd = calendar.date(from: endComponents) {
                        self.draft.end = adjustedEnd
                    }
                }
            } else { self.draft.end = combined }
            self.refreshDateLabels()
            self.refreshValidation()
        }
        present(vc, animated: true)
    }

    private func pickRepeat() {
        view.endEditing(true)
        let choices = draft.repeatOptions().map { EventEditorChoiceViewController.Choice(id: Int64($0.0), title: $0.1, icon: nil) }
        let vc = EventEditorChoiceViewController(title: L(L10n.EventEditor.repeatLabel), choices: choices, selectedId: Int64(draft.repeatType), allowsSearch: false) { [weak self] id in
            self?.draft.repeatType = Int32(id)
            self?.refreshDateLabels()
            self?.refreshValidation()
        }
        present(vc, animated: true)
    }

    private func refreshDateLabels() {
        guard dateFields.count == 4 else { return }
        dateFields[0].setValue(formatted(draft.start, template: "MMM d y"))
        dateFields[1].setValue(formatted(draft.start, template: "jm"))
        dateFields[2].setValue(formatted(draft.end, template: "MMM d y"))
        dateFields[3].setValue(formatted(draft.end, template: "jm"))
        repeatField?.setValue(repeatLabel())
    }
    private func repeatLabel() -> String {
        draft.repeatOptions().first { $0.0 == draft.repeatType }?.1 ?? L(draft.repeatType == EventRepeatType.everyWeekday ? L10n.EventEditor.repeatWeekday : L10n.EventEditor.repeatNone)
    }

    private func pickCover() {
        guard !uploading else { return }
        view.endEditing(true)
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        picker.delegate = self
        present(picker, animated: true)
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { showError(L(L10n.EventEditor.coverFailed)); return }
        let data: Data
        if let url = info[.imageURL] as? URL {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > EventEditorDraft.maximumCoverBytes {
                showError(L(L10n.EventEditor.coverTooLarge)); return
            }
            guard let bytes = try? Data(contentsOf: url, options: .mappedIfSafe) else { showError(L(L10n.EventEditor.coverFailed)); return }
            data = bytes
        } else {
            guard let bytes = image.jpegData(compressionQuality: 0.9) else { showError(L(L10n.EventEditor.coverFailed)); return }
            data = bytes
        }
        guard data.count <= EventEditorDraft.maximumCoverBytes else { showError(L(L10n.EventEditor.coverTooLarge)); return }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source) as String? else {
            showError(L(L10n.EventEditor.coverFailed)); return
        }
        let formats = ["public.jpeg": ("image/jpeg", "jpg"), "public.png": ("image/png", "png"), "com.compuserve.gif": ("image/gif", "gif"), "public.heic": ("image/heic", "heic"), "public.heif": ("image/heif", "heif"), "org.webmproject.webp": ("image/webp", "webp"), "public.tiff": ("image/tiff", "tiff")]
        guard let format = formats[type] else { showError(L(L10n.EventEditor.coverFailed)); return }
        uploading = true
        errorLabel.isHidden = true
        refreshCover()
        refreshValidation()
        uploadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.uploading = false
                self.uploadTask = nil
                if !self.dismissed {
                    self.refreshCover()
                    self.refreshValidation()
                }
            }
            do {
                guard let token = await self.context.getToken() else { throw EventEditorError.sessionExpired }
                let upload = try await self.context.account.network.uploadAttachmentFile(
                    filename: "\(UUID().uuidString)_event_cover.\(format.1)", filetype: format.0, size: data.count,
                    width: image.cgImage?.width ?? Int(image.size.width * image.scale), height: image.cgImage?.height ?? Int(image.size.height * image.scale), token: token
                )
                try Task.checkCancellation()
                try await self.context.account.network.uploadToMinIO(url: upload.url, data: data, contentType: format.0)
                try Task.checkCancellation()
                guard !self.dismissed else { return }
                self.draft.logoURL = "\(MezonConfig.baseImgURL)/\(upload.filename)"
                self.previewImage = image
                ImageCache.shared.setImage(image, data: data, forKey: self.draft.logoURL)
            } catch is CancellationError {
            } catch {
                self.showError(error.localizedDescription)
            }
        }
    }

    private func submit() {
        guard !submitting, !uploading, draft.isLocationValid, draft.isDetailsValid() else { return }
        if let original, !EventEditorAccess.canEdit(original, context: context) { showError(L(L10n.EventEditor.permissionDenied)); return }
        submitting = true
        errorLabel.isHidden = true
        refreshValidation()
        let submitted = draft
        submitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.submitting = false; self.submitTask = nil; if !self.dismissed { self.refreshValidation() } }
            do {
                guard let token = await self.context.getToken() else { throw EventEditorError.sessionExpired }
                if let original = self.original {
                    try await self.context.engine.clanData.updateEvent(draft: submitted, clanId: self.clanId, original: original, token: token)
                } else {
                    let userId = Int64(self.context.currentUser?.id ?? self.context.account.id) ?? 0
                    guard userId != 0 else { throw EventEditorError.sessionExpired }
                    try await self.context.engine.clanData.createEvent(draft: submitted, clanId: self.clanId, creatorId: userId, token: token)
                }
                let updated = self.original.map { original in
                    self.context.engine.clanData.getClanEvents(clanId: self.clanId)?.events.first { $0.id == original.id } ?? submitted.applying(to: original)
                }
                self.onSaved?(updated)
                self.dismissed = true
                self.dismiss(animated: true) {
                    Toast.success(L(self.original == nil ? L10n.EventEditor.created : L10n.EventEditor.updated))
                }
            } catch { self.showError(error.localizedDescription) }
        }
    }

    private func close() {
        guard !submitting else { return }
        dismissed = true
        uploadTask?.cancel()
        view.endEditing(true)
        dismiss(animated: true)
    }
    private func showError(_ message: String) {
        guard !dismissed else { return }
        errorLabel.text = message
        errorLabel.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: message)
        view.setNeedsLayout()
    }
    private func loadCover(into imageView: UIImageView) {
        if let previewImage { imageView.image = previewImage; return }
        let url = draft.logoURL
        guard !url.isEmpty else { return }
        ImageCache.shared.loadImage(urlString: ImgproxyURL.create(from: url, width: 800, height: 256)) { [weak self, weak imageView] image in
            guard let self, self.draft.logoURL == url, !self.dismissed else { return }
            imageView?.image = image
        }
    }
    private func channelLabel(_ id: Int64) -> String? { id == 0 ? nil : channels.first { $0.channelID == id }?.channelLabel }
    private func formatted(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.current.locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
    private func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = weight == .regular ? UIColor.theme.text : UIColor.theme.textStrong
        return label
    }
    private func labeledField(_ title: String, field: UIView, error: UILabel) -> UIView {
        let caption = label(title, size: 15, weight: .bold)
        if title.hasSuffix(" *") {
            let attributed = NSMutableAttributedString(string: title)
            attributed.addAttribute(.foregroundColor, value: UIColor.systemRed, range: NSRange(location: (title as NSString).length - 1, length: 1))
            caption.attributedText = attributed
        }
        let stack = UIStackView(arrangedSubviews: [caption, field, error])
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }
    private func configureError(_ label: UILabel) {
        label.textColor = .systemRed
        label.font = .systemFont(ofSize: 12)
        label.numberOfLines = 0
        label.isHidden = true
    }
    private func setError(_ label: UILabel, _ text: String?) { label.text = text; label.isHidden = text == nil }
    private func iconRow(_ symbol: String, text: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.contentMode = .scaleAspectFit
        icon.tintColor = UIColor.theme.textStrong
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
        let row = UIStackView(arrangedSubviews: [icon, label(text, size: 14)])
        row.alignment = .center
        row.spacing = 8
        return row
    }
}

private enum EventEditorError: LocalizedError {
    case sessionExpired
    var errorDescription: String? { L(L10n.EventEditor.sessionExpired) }
}
