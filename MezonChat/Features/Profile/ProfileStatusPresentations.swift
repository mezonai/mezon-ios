import UIKit

func makeProfileOptionRadioImage(selected: Bool, diameter: CGFloat = 20) -> UIImage? {
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

final class ProfileSheetPresenceCell: UITableViewCell {
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

final class ProfileSheetCustomStatusCell: UITableViewCell {
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
            clearBtn.tintColor = .mezonTextPrimary
            clearBtn.addTarget(clearTarget, action: clearAction, for: .touchUpInside)
        } else {
            clearBtn.setImage(nil, for: .normal)
        }
    }
}

final class ProfileSheetServerCell: UITableViewCell {
    static let reuseId = "ProfileSheetServerCell"

    private let titleLbl: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        l.textColor = .mezonTextStrong
        l.numberOfLines = 1
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let subtitleLbl: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13.sf, weight: .regular)
        l.textColor = .mezonTextSecondary
        l.numberOfLines = 1
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let radioView: UIImageView = {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .mezonPrimary
        selectionStyle = .none
        contentView.addSubview(titleLbl)
        contentView.addSubview(subtitleLbl)
        contentView.addSubview(radioView)
        NSLayoutConstraint.activate([
            titleLbl.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLbl.bottomAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -1),
            titleLbl.trailingAnchor.constraint(lessThanOrEqualTo: radioView.leadingAnchor, constant: -10.sw),

            subtitleLbl.leadingAnchor.constraint(equalTo: titleLbl.leadingAnchor),
            subtitleLbl.topAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 2),
            subtitleLbl.trailingAnchor.constraint(lessThanOrEqualTo: radioView.leadingAnchor, constant: -10.sw),

            radioView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            radioView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            radioView.widthAnchor.constraint(equalToConstant: 22),
            radioView.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, subtitle: String, selected: Bool) {
        titleLbl.text = title
        subtitleLbl.text = subtitle
        radioView.image = makeProfileOptionRadioImage(selected: selected)
    }
}

@MainActor
final class ProfileServerSheetController: UIViewController {

    private let choices = RealtimeServerChoice.allCases
    private let onSelect: (RealtimeServerChoice) -> Void
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var socketStatusObserver: NSObjectProtocol?

    init(onSelect: @escaping (RealtimeServerChoice) -> Void) {
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .mezonSecondaryBackground
        navigationItem.titleView = makeTitleView()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorInset = .zero
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(ProfileSheetServerCell.self, forCellReuseIdentifier: ProfileSheetServerCell.reuseId)
        tableView.rowHeight = 64
        tableView.estimatedSectionFooterHeight = 60
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        socketStatusObserver = NotificationCenter.default.addObserver(
            forName: .mezonSocketStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.tableView.reloadData()
        }
    }

    deinit {
        if let socketStatusObserver {
            NotificationCenter.default.removeObserver(socketStatusObserver)
        }
    }

    private func makeTitleView() -> UIView {
        let label = UILabel()
        label.text = L(L10n.Profile.server)
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
        return wrap
    }

    private func subtitle(for choice: RealtimeServerChoice) -> String {
        switch choice {
        case .auto:
            if RealtimeServerChoice.current == .auto, let inUse = RealtimeServerChoice.regionNameInUse {
                return L(L10n.Profile.serverInUse, inUse)
            }
            return L(L10n.Profile.serverAutoHint)
        case .vn1, .vn2:
            return L(L10n.Profile.serverVietnam)
        case .us:
            return L(L10n.Profile.serverUnitedStates)
        }
    }
}

extension ProfileServerSheetController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        choices.count
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        12
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        UIView()
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let container = UIView()
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = L(L10n.Profile.serverFooter)
        label.font = .systemFont(ofSize: 13.sf, weight: .regular)
        label.textColor = .mezonTextSecondary
        label.numberOfLines = 0
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8.sh),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8.sh),
        ])
        return container
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: ProfileSheetServerCell.reuseId, for: indexPath) as? ProfileSheetServerCell else {
            return UITableViewCell()
        }
        let choice = choices[indexPath.row]
        cell.configure(
            title: choice.regionName ?? L(L10n.Profile.serverAuto),
            subtitle: subtitle(for: choice),
            selected: choice == RealtimeServerChoice.current
        )
        cell.separatorInset = .zero
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelect(choices[indexPath.row])
        tableView.reloadData()
        dismiss(animated: true)
    }
}
