import UIKit

enum EventEditorPalette {
    static var surface: UIColor { UIColor.theme.secondaryLight }
    static var field: UIColor { UIColor.theme.tertiary }
    static var border: UIColor { UIColor.theme.textDisabled.withAlphaComponent(0.45) }
}

final class EventEditorButton: UIButton {
    var action: (() -> Void)?
    init() {
        super.init(frame: .zero)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func tapped() { action?() }
}

final class EventEditorFieldButton: UIControl {
    let valueLabel = UILabel()
    let captionLabel = UILabel()
    var action: (() -> Void)?
    init(caption: String) {
        super.init(frame: .zero)
        backgroundColor = EventEditorPalette.field
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = EventEditorPalette.border.cgColor
        captionLabel.text = caption
        captionLabel.font = .systemFont(ofSize: 12)
        captionLabel.textColor = UIColor.theme.text
        captionLabel.numberOfLines = 0
        valueLabel.font = .systemFont(ofSize: 14)
        valueLabel.textColor = UIColor.theme.textStrong
        valueLabel.numberOfLines = 2
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = UIColor.theme.textDisabled
        chevron.contentMode = .scaleAspectFit
        chevron.widthAnchor.constraint(equalToConstant: 10).isActive = true
        let row = UIStackView(arrangedSubviews: [valueLabel, chevron])
        row.spacing = 8
        let stack = UIStackView(arrangedSubviews: [captionLabel, row])
        stack.axis = .vertical
        stack.spacing = 8
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = caption
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func tapped() { action?() }
    func setValue(_ value: String) {
        valueLabel.text = value
        accessibilityValue = value
    }
}

final class EventEditorChoiceViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    struct Choice {
        let id: Int64
        let title: String
        let icon: String?
    }
    private let choices: [Choice]
    private var filtered: [Choice]
    private let selectedId: Int64?
    private let onSelect: (Int64) -> Void
    private let allowsSearch: Bool
    private let table = UITableView(frame: .zero, style: .plain)
    private let searchContainer = UIView()
    private let searchField = UITextField()
    private var searchWorkItem: DispatchWorkItem?

    init(title: String, choices: [Choice], selectedId: Int64?, allowsSearch: Bool = true, onSelect: @escaping (Int64) -> Void) {
        self.choices = choices
        self.filtered = choices
        self.selectedId = selectedId
        self.allowsSearch = allowsSearch
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
        self.title = title
        modalPresentationStyle = .pageSheet
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { searchWorkItem?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = EventEditorPalette.surface
        if #available(iOS 15.0, *) {
            sheetPresentationController?.detents = [.medium(), .large()]
        }
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.numberOfLines = 0
        let close = EventEditorButton()
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = UIColor.theme.text
        close.accessibilityLabel = L(L10n.EventEditor.close)
        close.widthAnchor.constraint(equalToConstant: 44).isActive = true
        close.heightAnchor.constraint(equalToConstant: 44).isActive = true
        close.action = { [weak self] in self?.dismiss(animated: true) }
        let header = UIStackView(arrangedSubviews: [titleLabel, close])
        header.alignment = .center
        searchContainer.backgroundColor = EventEditorPalette.field
        searchContainer.layer.cornerRadius = 12
        searchContainer.layer.borderWidth = 1
        searchContainer.layer.borderColor = EventEditorPalette.border.cgColor
        searchContainer.isHidden = !allowsSearch

        let searchIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        searchIcon.tintColor = UIColor.theme.text
        searchIcon.contentMode = .scaleAspectFit
        searchIcon.translatesAutoresizingMaskIntoConstraints = false

        searchField.font = .systemFont(ofSize: 16)
        searchField.textColor = UIColor.theme.textStrong
        searchField.tintColor = UIColor.theme.textStrong
        searchField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.EventEditor.search),
            attributes: [.foregroundColor: UIColor.theme.text]
        )
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.clearButtonMode = .whileEditing
        searchField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        searchContainer.addSubview(searchIcon)
        searchContainer.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchContainer.heightAnchor.constraint(equalToConstant: 48),
            searchIcon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 14),
            searchIcon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 22),
            searchIcon.heightAnchor.constraint(equalToConstant: 22),
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -14),
            searchField.topAnchor.constraint(equalTo: searchContainer.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor)
        ])

        let stack = UIStackView(arrangedSubviews: [header, searchContainer, table])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.keyboardDismissMode = .onDrag
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 60
        updateEmptyState()
    }
    func numberOfSections(in tableView: UITableView) -> Int { filtered.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { 8 }
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? { UIView() }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let choice = filtered[indexPath.section]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let selected = choice.id == selectedId
        cell.backgroundColor = EventEditorPalette.field
        cell.selectionStyle = .none
        cell.layer.cornerRadius = 12
        cell.layer.borderWidth = selected ? 1 : 0
        cell.layer.borderColor = selected ? UIColor.theme.bgViolet.cgColor : UIColor.clear.cgColor
        let title = UILabel()
        title.text = choice.title
        title.font = .systemFont(ofSize: 16)
        title.textColor = UIColor.theme.textStrong
        title.numberOfLines = allowsSearch ? 1 : 0
        title.lineBreakMode = allowsSearch ? .byTruncatingTail : .byWordWrapping
        title.setContentCompressionResistancePriority(.required, for: .vertical)
        let row = UIStackView()
        row.alignment = .center
        row.spacing = 12
        if let iconName = choice.icon {
            let image = UIImage(named: iconName) ?? UIImage(systemName: iconName)
            let icon = UIImageView(image: image?.withRenderingMode(.alwaysTemplate))
            icon.tintColor = UIColor.theme.textStrong
            icon.contentMode = .scaleAspectFit
            icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 24).isActive = true
            row.addArrangedSubview(icon)
        }
        row.addArrangedSubview(title)
        if selected {
            cell.accessibilityTraits.insert(.selected)
        }
        row.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 16),
            row.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -16),
            row.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -14),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 24)
        ])
        cell.accessibilityLabel = choice.title
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let id = filtered[indexPath.section].id
        dismiss(animated: true) { [onSelect] in onSelect(id) }
    }
    @objc private func searchTextChanged() {
        searchWorkItem?.cancel()
        let searchText = searchField.text ?? ""
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.filtered = searchText.isEmpty ? self.choices : self.choices.filter { $0.title.localizedStandardContains(searchText) }
            self.table.reloadData()
            self.updateEmptyState()
        }
        searchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    private func updateEmptyState() {
        let label = UILabel()
        label.text = L(L10n.EventEditor.noChannels)
        label.textColor = UIColor.theme.textDisabled
        label.textAlignment = .center
        label.numberOfLines = 0
        table.backgroundView = filtered.isEmpty ? label : nil
    }
}

final class EventEditorDateViewController: UIViewController {
    private let picker = UIDatePicker()
    private let date: Date
    private let mode: UIDatePicker.Mode
    private let minimum: Date?
    private let onSelect: (Date) -> Void
    init(title: String, date: Date, mode: UIDatePicker.Mode, minimum: Date?, onSelect: @escaping (Date) -> Void) {
        self.date = date
        self.mode = mode
        self.minimum = minimum
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
        self.title = title
        modalPresentationStyle = .pageSheet
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = EventEditorPalette.surface
        if #available(iOS 15.0, *) {
            sheetPresentationController?.detents = [.medium()]
        }
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.numberOfLines = 0
        let done = EventEditorButton()
        done.setTitle(L(L10n.EventEditor.done), for: .normal)
        done.setTitleColor(UIColor(red: 0.39, green: 0.38, blue: 0.91, alpha: 1), for: .normal)
        done.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        done.heightAnchor.constraint(equalToConstant: 44).isActive = true
        done.action = { [weak self] in
            guard let self else { return }
            let value = self.picker.date
            self.dismiss(animated: true) { [onSelect = self.onSelect] in onSelect(value) }
        }
        let header = UIStackView(arrangedSubviews: [titleLabel, done])
        header.alignment = .center
        picker.datePickerMode = mode
        picker.locale = LanguageManager.shared.current.locale
        if #available(iOS 13.4, *) { picker.preferredDatePickerStyle = .wheels }
        let currentTheme = ThemeManager.shared.current
        let effectiveTheme = currentTheme == .system
            ? (traitCollection.userInterfaceStyle == .dark ? AppTheme.dark : AppTheme.light)
            : currentTheme
        picker.overrideUserInterfaceStyle = (effectiveTheme == .light || effectiveTheme == .sunrise) ? .light : .dark
        picker.minimumDate = minimum
        picker.date = date
        let stack = UIStackView(arrangedSubviews: [header, picker])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }
}
