import UIKit

private func makeProfileOptionRadioImage(selected: Bool, diameter: CGFloat = 20) -> UIImage? {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
    return renderer.image { _ in
        let outerRect = CGRect(x: 1, y: 1, width: diameter - 2, height: diameter - 2)
        let outer = UIBezierPath(ovalIn: outerRect)

        if selected {
            UIColor.outgoingBubble.setFill()
            outer.fill()
            let innerDiameter = diameter * 0.46
            let innerRect = CGRect(
                x: (diameter - innerDiameter) / 2,
                y: (diameter - innerDiameter) / 2,
                width: innerDiameter,
                height: innerDiameter
            )
            let inner = UIBezierPath(ovalIn: innerRect)
            UIColor.white.setFill()
            inner.fill()
        } else {
            UIColor.mezonTextStrong.setStroke()
            outer.lineWidth = 1.6
            outer.stroke()
        }
    }
}

private final class ProfileSheetPresenceCell: UITableViewCell {
    static let reuseId = "ProfileSheetPresenceCell"

    private let iconView: UIImageView = {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let radioView: UIImageView = {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let titleLbl: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf, weight: .regular)
        l.textColor = .mezonTextStrong
        l.numberOfLines = 1
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .mezonPrimary
        selectionStyle = .none
        contentView.addSubview(iconView)
        contentView.addSubview(titleLbl)
        contentView.addSubview(radioView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleLbl.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12.sw),
            titleLbl.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLbl.trailingAnchor.constraint(lessThanOrEqualTo: radioView.leadingAnchor, constant: -10.sw),

            radioView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            radioView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            radioView.widthAnchor.constraint(equalToConstant: 22),
            radioView.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, icon: UIImage?, selected: Bool) {
        titleLbl.text = title
        iconView.image = icon
        radioView.image = makeProfileOptionRadioImage(selected: selected)
    }
}

private final class ProfileSheetCustomStatusCell: UITableViewCell {
    static let reuseId = "ProfileSheetCustomStatusCell"

    private let iconView: UIImageView = {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let titleLbl: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf, weight: .regular)
        l.textColor = .mezonTextStrong
        l.numberOfLines = 1
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let clearBtn: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .mezonPrimary
        selectionStyle = .default
        contentView.addSubview(iconView)
        contentView.addSubview(titleLbl)
        contentView.addSubview(clearBtn)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleLbl.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12.sw),
            titleLbl.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLbl.trailingAnchor.constraint(lessThanOrEqualTo: clearBtn.leadingAnchor, constant: -8.sw),

            clearBtn.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            clearBtn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            clearBtn.widthAnchor.constraint(equalToConstant: 28),
            clearBtn.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, icon: UIImage?, showClear: Bool, clearTarget: Any?, clearAction: Selector) {
        titleLbl.text = title
        iconView.image = icon
        clearBtn.isHidden = !showClear
        clearBtn.removeTarget(nil, action: nil, for: .allEvents)
        if showClear {
            let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            clearBtn.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: cfg), for: .normal)
            clearBtn.tintColor = .mezonTextSecondary
            clearBtn.addTarget(clearTarget, action: clearAction, for: .touchUpInside)
        } else {
            clearBtn.setImage(nil, for: .normal)
        }
    }
}

@MainActor
final class ProfileAddStatusViewController: UIViewController {

    private let context: AccountContext

    private static let maxStatusLength = 128

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private let textInputContainer: UIView = {
        let v = UIView()
        v.backgroundColor = .mezonPrimary
        v.layer.cornerRadius = 12.swh
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor.mezonBorder.cgColor
        v.clipsToBounds = true
        return v
    }()

    private let textView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 16.sf)
        tv.textColor = .mezonTextStrong
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 4, right: 10)
        return tv
    }()

    private let characterCountLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12.sf)
        l.textColor = .mezonTextPrimary
        l.text = "0/128"
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let durationHeader = UILabel()
    private let durationTable = UITableView(frame: .zero, style: .plain)
    private let durationSpacer = UIView()

    private let durationOptions: [(value: Int, titleKey: String)] = [
        (-1, L10n.Profile.statusDurationToday),
        (240, L10n.Profile.statusDurationFourHours),
        (60, L10n.Profile.statusDurationOneHour),
        (30, L10n.Profile.statusDurationThirtyMinutes),
        (0, L10n.Profile.statusDurationDontClear),
    ]

    private var selectedDurationValue: Int = -1

    private var currentUserObserver: NSObjectProtocol?

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .mezonSecondaryBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
        navigationItem.leftBarButtonItem?.tintColor = .mezonTextStrong

        let hasExistingStatus = !(context.currentUser?.customStatus?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ?? true)
        navigationItem.title = hasExistingStatus
            ? L(L10n.Profile.statusTitle)
            : L(L10n.Profile.addStatus)
        navigationController?.navigationBar.titleTextAttributes = [
            .foregroundColor: UIColor.mezonTextStrong,
        ]

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L(L10n.Common.save),
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )
        navigationItem.rightBarButtonItem?.tintColor = .outgoingBubble

        syncFromCurrentUser()

        durationHeader.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        durationHeader.textColor = .mezonTextStrong
        durationHeader.text = L(L10n.Profile.statusDurationLabel)

        durationTable.dataSource = self
        durationTable.delegate = self
        durationTable.backgroundColor = .clear
        durationTable.separatorStyle = .singleLine
        durationTable.separatorInset = .zero
        durationTable.isScrollEnabled = false
        durationTable.register(UITableViewCell.self, forCellReuseIdentifier: "duration")
        durationTable.layer.cornerRadius = 12.swh
        durationTable.clipsToBounds = true
        durationTable.rowHeight = 56.sh

        stack.axis = .vertical
        stack.spacing = 12.sh
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        textInputContainer.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        textInputContainer.addSubview(textView)
        textInputContainer.addSubview(characterCountLabel)
        stack.addArrangedSubview(textInputContainer)
        durationSpacer.translatesAutoresizingMaskIntoConstraints = false
        durationSpacer.heightAnchor.constraint(equalToConstant: 10.sh).isActive = true
        stack.addArrangedSubview(durationSpacer)
        stack.addArrangedSubview(durationHeader)
        stack.addArrangedSubview(durationTable)

        textView.delegate = self
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: textInputContainer.topAnchor),
            textView.leadingAnchor.constraint(equalTo: textInputContainer.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: textInputContainer.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: characterCountLabel.topAnchor, constant: -2.sh),

            characterCountLabel.trailingAnchor.constraint(equalTo: textInputContainer.trailingAnchor, constant: -12.sw),
            characterCountLabel.bottomAnchor.constraint(equalTo: textInputContainer.bottomAnchor, constant: -8.sh),
        ])
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16.sh),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16.sw),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16.sw),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24.sh),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32.sw),

            textInputContainer.heightAnchor.constraint(equalToConstant: 120.sh),
            durationTable.heightAnchor.constraint(equalToConstant: CGFloat(durationOptions.count) * 56.sh),
        ])

        currentUserObserver = NotificationCenter.default.addObserver(
            forName: .mezonAccountCurrentUserDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncFromCurrentUser()
        }
    }

    deinit {
        if let currentUserObserver {
            NotificationCenter.default.removeObserver(currentUserObserver)
        }
    }

    private func syncFromCurrentUser() {
        guard let u = context.currentUser else {
            textView.text = ""
            updateCharacterCount()
            selectedDurationValue = -1
            durationTable.reloadData()
            return
        }
        let raw = u.customStatus ?? ""
        textView.text = String(raw.prefix(Self.maxStatusLength))
        updateCharacterCount()
        if u.customStatusTimeReset == nil && u.customStatusNoClear == nil {
            selectedDurationValue = -1
        } else {
            let tr = u.customStatusTimeReset ?? 0
            let nc = u.customStatusNoClear ?? false
            selectedDurationValue = User.customStatusDurationRowValue(timeReset: tr, noClear: nc)
        }
        durationTable.reloadData()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        let raw = textView.text ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= Self.maxStatusLength else {
            Toast.error(L(L10n.Profile.statusTooLong))
            return
        }

        let (minutes, noClear) = Self.minutesAndNoClear(forSelectedDuration: selectedDurationValue)

        Task {
            do {
                try await context.submitCustomStatus(text: trimmed, minutes: minutes, noClear: noClear)
                self.dismiss(animated: true)
            } catch {
                Toast.error(L(L10n.Profile.statusUpdateFailed))
            }
        }
    }

    private static func minutesAndNoClear(forSelectedDuration selected: Int) -> (Int32, Bool) {
        if selected == -1 {
            return (minutesUntilEndOfDay(), false)
        }
        if selected == 0 {
            return (0, true)
        }
        return (Int32(selected), false)
    }

    private static func minutesUntilEndOfDay() -> Int32 {
        let now = Date()
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = 23
        comps.minute = 59
        comps.second = 59
        let end = cal.date(from: comps) ?? now
        let mins = end.timeIntervalSince(now) / 60.0
        return Int32(max(1, ceil(mins)))
    }

    private func updateCharacterCount() {
        let n = (textView.text ?? "").count
        characterCountLabel.text = "\(n)/\(Self.maxStatusLength)"
    }
}

extension ProfileAddStatusViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let current = textView.text ?? ""
        guard let r = Range(range, in: current) else { return true }
        let newText = current.replacingCharacters(in: r, with: text)
        if newText.count <= Self.maxStatusLength { return true }
        let truncated = String(newText.prefix(Self.maxStatusLength))
        textView.text = truncated
        updateCharacterCount()
        let off = (truncated as NSString).length
        if let pos = textView.position(from: textView.beginningOfDocument, offset: off),
           let tr = textView.textRange(from: pos, to: pos) {
            textView.selectedTextRange = tr
        }
        return false
    }

    func textViewDidChange(_ textView: UITextView) {
        updateCharacterCount()
    }
}

extension ProfileAddStatusViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        durationOptions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "duration", for: indexPath)
        let opt = durationOptions[indexPath.row]
        let selected = opt.value == selectedDurationValue
        cell.backgroundColor = .mezonPrimary
        cell.textLabel?.text = L(opt.titleKey)
        cell.textLabel?.textColor = .mezonTextStrong
        cell.textLabel?.font = .systemFont(ofSize: 15.sf, weight: .regular)
        cell.selectionStyle = .none
        let iv = UIImageView(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
        iv.contentMode = .center
        iv.image = makeProfileOptionRadioImage(selected: selected)
        cell.accessoryView = iv
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedDurationValue = durationOptions[indexPath.row].value
        tableView.reloadData()
    }
}

@MainActor
final class ProfileOnlineStatusSheetController: UIViewController {

    private let context: AccountContext

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private var currentUserObserver: NSObjectProtocol?

    private enum Section: Int {
        case presence = 0
        case custom = 1
    }

    private let presenceCases: [(User.OnlineStatus, String)] = [
        (.online, L10n.Profile.userStatusOnline),
        (.idle, L10n.Profile.userStatusIdle),
        (.doNotDisturb, L10n.Profile.userStatusDoNotDisturb),
        (.invisible, L10n.Profile.userStatusInvisible),
    ]

    init(context: AccountContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .mezonSecondaryBackground

        setupPaddedNavigationTitle()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(ProfileSheetPresenceCell.self, forCellReuseIdentifier: ProfileSheetPresenceCell.reuseId)
        tableView.register(ProfileSheetCustomStatusCell.self, forCellReuseIdentifier: ProfileSheetCustomStatusCell.reuseId)
        tableView.rowHeight = 56
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 6
        }
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        currentUserObserver = NotificationCenter.default.addObserver(
            forName: .mezonAccountCurrentUserDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.tableView.reloadData()
        }
    }

    deinit {
        if let currentUserObserver {
            NotificationCenter.default.removeObserver(currentUserObserver)
        }
    }

    private func setupPaddedNavigationTitle() {
        let label = UILabel()
        label.text = L(L10n.Profile.changeOnlineStatus)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .mezonTextStrong
        label.textAlignment = .center
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        navigationItem.titleView = wrap
    }

    private func iconForPresence(_ s: User.OnlineStatus) -> UIImage? {
        let name: String
        switch s {
        case .online: name = "OnlineIcon"
        case .idle: name = "IdleIcon"
        case .doNotDisturb: name = "DisturbIcon"
        case .invisible, .offline: name = "OfflineIocn"
        }
        guard let img = UIImage(named: "Profile/\(name)", in: Bundle.main, compatibleWith: nil) else { return nil }
        let canvas: CGFloat = 20
        let drawSide: CGFloat
        switch s {
        case .online, .invisible, .offline:
            drawSide = 14
        case .idle, .doNotDisturb:
            drawSide = 20
        }
        let r = UIGraphicsImageRenderer(size: CGSize(width: canvas, height: canvas))
        return r.image { _ in
            let o = (canvas - drawSide) / 2
            img.draw(in: CGRect(x: o, y: o, width: drawSide, height: drawSide))
        }.withRenderingMode(.alwaysOriginal)
    }

    private func faceIconScaled() -> UIImage? {
        guard let img = UIImage(named: "Profile/FaceIcon", in: Bundle.main, compatibleWith: nil) else { return nil }
        let sz: CGFloat = 20
        let r = UIGraphicsImageRenderer(size: CGSize(width: sz, height: sz))
        return r.image { _ in
            img.draw(in: CGRect(x: 0, y: 0, width: sz, height: sz))
        }.withRenderingMode(.alwaysOriginal)
    }

    private func clearCustomStatus() {
        Task {
            do {
                try await context.submitCustomStatus(text: "", minutes: 0, noClear: false)
                self.tableView.reloadData()
            } catch {
                Toast.error(L(L10n.Profile.statusUpdateFailed))
            }
        }
    }

    @objc private func clearAccessoryTapped() {
        clearCustomStatus()
    }

    private func selectPresence(_ status: User.OnlineStatus) {
        Task {
            do {
                try await context.updatePresenceStatus(status)
                self.dismiss(animated: true)
            } catch {
                Toast.error(L(L10n.Profile.presenceUpdateFailed))
            }
        }
    }
}

extension ProfileOnlineStatusSheetController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch Section(rawValue: section)! {
        case .presence: return 44
        case .custom: return .leastNormalMagnitude
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch Section(rawValue: section)! {
        case .presence:
            let v = UIView()
            v.backgroundColor = .clear
            let l = UILabel()
            l.translatesAutoresizingMaskIntoConstraints = false
            l.text = L(L10n.Profile.onlineStatusSection)
            l.font = .systemFont(ofSize: 15.sf, weight: .semibold)
            l.textColor = .mezonTextStrong
            v.addSubview(l)
            NSLayoutConstraint.activate([
                l.leadingAnchor.constraint(equalTo: v.leadingAnchor),
                l.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor),
                l.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8.sh),
            ])
            return v
        case .custom:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .presence: return presenceCases.count
        case .custom: return 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .presence:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ProfileSheetPresenceCell.reuseId, for: indexPath) as? ProfileSheetPresenceCell else {
                return UITableViewCell()
            }
            let item = presenceCases[indexPath.row]
            let current = context.currentUser?.status ?? .offline
            let selected = current == item.0
            cell.configure(title: L(item.1), icon: iconForPresence(item.0), selected: selected)
            return cell
        case .custom:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ProfileSheetCustomStatusCell.reuseId, for: indexPath) as? ProfileSheetCustomStatusCell else {
                return UITableViewCell()
            }
            let text = context.currentUser?.customStatus
            let title = (text?.isEmpty == false) ? text! : L(L10n.Profile.setCustomStatus)
            cell.configure(
                title: title,
                icon: faceIconScaled(),
                showClear: text?.isEmpty == false,
                clearTarget: self,
                clearAction: #selector(clearAccessoryTapped)
            )
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .presence:
            selectPresence(presenceCases[indexPath.row].0)
        case .custom:
            let host = presentingViewController
            let ctx = context
            dismiss(animated: true) {
                let vc = ProfileAddStatusViewController(context: ctx)
                let nav = UINavigationController(rootViewController: vc)
                nav.modalPresentationStyle = .pageSheet
                host?.present(nav, animated: true)
            }
        }
    }
}
