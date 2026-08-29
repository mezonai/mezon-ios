import UIKit

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
            image: UIImage.mezonSystemImage("xmark"),
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
        if #available(iOS 13.0, *) {
            let raw = textView.text ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count <= Self.maxStatusLength else {
                Toast.error(L(L10n.Profile.statusTooLong))
                return
            }

            let (minutes, noClear) = Self.minutesAndNoClear(forSelectedDuration: selectedDurationValue)

            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.context.submitCustomStatus(text: trimmed, minutes: minutes, noClear: noClear)
                    self.dismiss(animated: true)
                } catch {
                    Toast.error(L(L10n.Profile.statusUpdateFailed))
                }
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
