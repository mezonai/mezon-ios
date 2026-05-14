import UIKit

@MainActor
final class AddMembersSheetController: UIViewController {

    private let candidates: [ClanMemberRecord]
    private var filtered: [ClanMemberRecord]
    private var selectedIds: Set<Int64> = []
    private var searchText: String = ""

    private let titleLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let searchContainer = UIView()
    private let searchField = UITextField()
    private let tableView = UITableView(frame: .zero, style: .plain)

    private let onConfirm: ([Int64]) -> Void
    private let tableBottomInsetBase: CGFloat = 24.sh

    init(candidates: [ClanMemberRecord], onConfirm: @escaping ([Int64]) -> Void) {
        self.candidates = candidates
        self.filtered = candidates
        self.onConfirm = onConfirm
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            if let sheet = sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 16
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .mezonSecondary
        setupHeader()
        setupSearch()
        setupTable()
        refreshDone()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(
            self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    @objc private func keyboardFrameChanged(_ notification: Notification) {
        guard let info = notification.userInfo,
            let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        let bottom = tableBottomInsetBase + overlap
        tableView.contentInset.bottom = bottom
        tableView.verticalScrollIndicatorInsets.bottom = bottom
        let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveValue = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 0
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: UIView.AnimationOptions(rawValue: curveValue << 16),
            animations: { self.view.layoutIfNeeded() }
        )
    }

    private func setupHeader() {
        titleLabel.text = L(L10n.ClanRoles.membersAdd)
        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        titleLabel.textColor = .mezonTextPrimary
        titleLabel.textAlignment = .center

        cancelButton.setTitle(L(L10n.Common.cancel), for: .normal)
        cancelButton.setTitleColor(UIColor.theme.textDisabled, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .regular)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        doneButton.setTitle(L(L10n.Common.save), for: .normal)
        doneButton.setTitleColor(UIColor.theme.bgViolet, for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        [titleLabel, cancelButton, doneButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14.sh),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            cancelButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            doneButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor)
        ])
    }

    private func setupSearch() {
        searchContainer.backgroundColor = UIColor.theme.tertiary
        searchContainer.layer.cornerRadius = 10.swh
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchContainer)

        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass")?.withRenderingMode(.alwaysTemplate))
        icon.tintColor = UIColor.theme.textDisabled
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(icon)

        searchField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.ClanRoles.membersSearch),
            attributes: [.foregroundColor: UIColor.theme.textDisabled]
        )
        searchField.textColor = .mezonTextPrimary
        searchField.font = .systemFont(ofSize: 14.sf, weight: .regular)
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14.sh),
            searchContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            searchContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            searchContainer.heightAnchor.constraint(equalToConstant: 40.sh),

            icon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 10.sw),
            icon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16.swh),
            icon.heightAnchor.constraint(equalToConstant: 16.swh),

            searchField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8.sw),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -10.sw),
            searchField.topAnchor.constraint(equalTo: searchContainer.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor)
        ])
    }

    private func setupTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 64.sh
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(MemberRowCell.self, forCellReuseIdentifier: MemberRowCell.reuseId)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 8.sh),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func refreshDone() {
        let enabled = !selectedIds.isEmpty
        doneButton.isEnabled = enabled
        doneButton.alpha = enabled ? 1.0 : 0.4
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func doneTapped() {
        let ids = Array(selectedIds)
        dismiss(animated: true) { [onConfirm] in
            onConfirm(ids)
        }
    }

    @objc private func searchChanged() {
        searchText = searchField.text ?? ""
        if searchText.isEmpty {
            filtered = candidates
        } else {
            filtered = candidates.filter { RoleMemberDisplay.matches($0, query: searchText) }
        }
        tableView.reloadData()
    }
}

extension AddMembersSheetController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(filtered.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if filtered.isEmpty {
            let cell = UITableViewCell()
            cell.backgroundColor = .clear
            cell.textLabel?.text = L(L10n.ClanRoles.membersNotFound)
            cell.textLabel?.textColor = UIColor.theme.textDisabled
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.font = .systemFont(ofSize: 13.sf, weight: .regular)
            cell.selectionStyle = .none
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: MemberRowCell.reuseId, for: indexPath) as! MemberRowCell
        let member = filtered[indexPath.row]
        cell.configure(
            name: RoleMemberDisplay.displayName(member),
            subtitle: member.username,
            avatarURL: RoleMemberDisplay.avatarURL(member),
            accessory: .checkbox(checked: selectedIds.contains(member.userId))
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !filtered.isEmpty else { return }
        let member = filtered[indexPath.row]
        if selectedIds.contains(member.userId) {
            selectedIds.remove(member.userId)
        } else {
            selectedIds.insert(member.userId)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        refreshDone()
    }
}
