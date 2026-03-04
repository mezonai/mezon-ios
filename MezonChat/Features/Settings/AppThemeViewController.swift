import UIKit
import Combine

final class AppThemeViewController: BaseViewController {

    private var selectedTheme: AppTheme = ThemeManager.shared.current


    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var contentStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .center
        sv.spacing = 24.sh
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var previewCard = ConversationPreviewCard()

    private lazy var themeNameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 18.sf, weight: .semibold)
        l.textColor = .label
        l.textAlignment = .center
        return l
    }()

    private lazy var swatchScroll: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var swatchStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 12.sw
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var footerLabel: UILabel = {
        let l = UILabel()
        l.text = "You can always change this later!"
        l.font = .systemFont(ofSize: 13.sf)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        return l
    }()

    private var swatchButtons: [ThemeSwatchButton] = []


    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func setupUI() {
        title = "App Theme"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        previewCard.translatesAutoresizingMaskIntoConstraints = false
        swatchScroll.translatesAutoresizingMaskIntoConstraints = false

        swatchScroll.addSubview(swatchStack)
        NSLayoutConstraint.activate([
            swatchStack.topAnchor.constraint(equalTo: swatchScroll.topAnchor),
            swatchStack.bottomAnchor.constraint(equalTo: swatchScroll.bottomAnchor),
            swatchStack.leadingAnchor.constraint(equalTo: swatchScroll.leadingAnchor, constant: 20.sw),
            swatchStack.trailingAnchor.constraint(equalTo: swatchScroll.trailingAnchor, constant: -20.sw),
            swatchStack.heightAnchor.constraint(equalTo: swatchScroll.heightAnchor),
        ])

        buildSwatches()

        contentStack.addArrangedSubview(previewCard)
        contentStack.addArrangedSubview(themeNameLabel)
        contentStack.addArrangedSubview(swatchScroll)
        contentStack.addArrangedSubview(footerLabel)

        contentStack.setCustomSpacing(16.sh, after: previewCard)
        contentStack.setCustomSpacing(20.sh, after: themeNameLabel)
        contentStack.setCustomSpacing(32.sh, after: swatchScroll)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 32.sh),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -32.sh),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            previewCard.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor, constant: 20.sw),
            previewCard.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor, constant: -20.sw),

            swatchScroll.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            swatchScroll.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor),
            swatchScroll.heightAnchor.constraint(equalToConstant: 80.sh),
        ])

        refresh(theme: selectedTheme, animated: false)
    }


    private func buildSwatches() {
        swatchButtons = AppTheme.allCases.map { theme in
            let btn = ThemeSwatchButton(theme: theme)
            btn.addTarget(self, action: #selector(swatchTapped(_:)), for: .touchUpInside)
            swatchStack.addArrangedSubview(btn)
            return btn
        }
    }


    @objc private func swatchTapped(_ sender: ThemeSwatchButton) {
        guard sender.theme != selectedTheme else { return }
        selectedTheme = sender.theme
        ThemeManager.shared.set(sender.theme)
        refresh(theme: sender.theme, animated: true)
    }


    private func refresh(theme: AppTheme, animated: Bool) {
        let block = {
            self.themeNameLabel.text = theme.displayName
            self.previewCard.apply(theme: theme)
            self.swatchButtons.forEach { $0.setSelected($0.theme == theme) }
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: block)
        } else {
            block()
        }
    }
}


private final class ConversationPreviewCard: UIView {

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "Conversation"
        l.font = .systemFont(ofSize: 20.sf, weight: .bold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var rowStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 0
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let mockRows: [(name: String, message: String, time: String)] = [
        ("John Doe",     "Hey, are we still on for the meeting tomorrow?",    "10m"),
        ("Jane Smith",   "Don't forget to check out the new project updates!", "1h"),
        ("Alice Johnson","Can you send me the files from last week?",          "8h"),
        ("Bob Brown",    "Let's grab lunch sometime next week.",               "14h"),
    ]

    private let bgColors: [UIColor] = [
        UIColor(red: 0.36, green: 0.36, blue: 0.82, alpha: 1),
        UIColor(red: 0.23, green: 0.56, blue: 0.42, alpha: 1),
        UIColor(red: 0.72, green: 0.26, blue: 0.26, alpha: 1),
        UIColor(red: 0.75, green: 0.52, blue: 0.18, alpha: 1),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 16.sw
        layer.shadowColor  = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowOffset  = CGSize(width: 0, height: 4.sh)
        layer.shadowRadius  = 12.sw
        clipsToBounds = false

        addSubview(titleLabel)
        addSubview(rowStack)

        for (i, row) in mockRows.enumerated() {
            let rowView = MockConversationRow(
                name: row.name,
                message: row.message,
                time: row.time,
                avatarColor: bgColors[i]
            )
            rowView.translatesAutoresizingMaskIntoConstraints = false
            rowStack.addArrangedSubview(rowView)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            rowStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(theme: AppTheme) {
        let attrs = theme.attributes
        backgroundColor = attrs.secondary
        titleLabel.textColor = attrs.textStrong
        rowStack.arrangedSubviews.forEach { ($0 as? MockConversationRow)?.apply(attrs: attrs) }
    }
}

private final class MockConversationRow: UIView {
    private let avatarView: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 22.swh
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let initialsLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13.sf, weight: .semibold)
        l.textColor = .white
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let onlineDot: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(red: 0.16, green: 0.73, blue: 0.47, alpha: 1)
        v.layer.cornerRadius = 6.swh
        v.layer.borderWidth = 2
        v.layer.borderColor = UIColor.white.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let timeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12.sf)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let messageLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13.sf)
        l.numberOfLines = 2
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    init(name: String, message: String, time: String, avatarColor: UIColor) {
        super.init(frame: .zero)
        avatarView.backgroundColor = avatarColor
        nameLabel.text = name
        timeLabel.text = time
        messageLabel.text = message
        initialsLabel.text = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()

        avatarView.addSubview(initialsLabel)
        addSubview(avatarView)
        addSubview(onlineDot)
        addSubview(nameLabel)
        addSubview(timeLabel)
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16.sw),
            avatarView.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 44.swh),
            avatarView.heightAnchor.constraint(equalToConstant: 44.swh),
            avatarView.topAnchor.constraint(equalTo: topAnchor, constant: 10.sh),
            avatarView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10.sh),

            initialsLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            onlineDot.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 2.sw),
            onlineDot.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 2.sh),
            onlineDot.widthAnchor.constraint(equalToConstant: 12.swh),
            onlineDot.heightAnchor.constraint(equalToConstant: 12.swh),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12.sw),
            nameLabel.topAnchor.constraint(equalTo: avatarView.topAnchor),

            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16.sw),
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            messageLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16.sw),
            messageLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2.sh),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(attrs: ThemeAttributes) {
        nameLabel.textColor    = attrs.textStrong
        messageLabel.textColor = attrs.textNormal.withAlphaComponent(0.75)
        timeLabel.textColor    = attrs.textDisabled
        onlineDot.layer.borderColor = attrs.secondary.cgColor
    }
}


private final class ThemeSwatchButton: UIButton {

    let theme: AppTheme

    private let selectionRing: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 18.swh
        v.layer.borderWidth  = 2
        v.layer.borderColor  = UIColor.systemBlue.cgColor
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let colorSwatch: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 14.swh
        v.clipsToBounds = true
        v.isUserInteractionEnabled = false
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    init(theme: AppTheme) {
        self.theme = theme
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        colorSwatch.backgroundColor = theme.attributes.primary

        addSubview(selectionRing)
        addSubview(colorSwatch)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 60.swh),
            heightAnchor.constraint(equalToConstant: 60.swh),

            selectionRing.centerXAnchor.constraint(equalTo: centerXAnchor),
            selectionRing.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectionRing.widthAnchor.constraint(equalToConstant: 56.swh),
            selectionRing.heightAnchor.constraint(equalToConstant: 56.swh),

            colorSwatch.centerXAnchor.constraint(equalTo: centerXAnchor),
            colorSwatch.centerYAnchor.constraint(equalTo: centerYAnchor),
            colorSwatch.widthAnchor.constraint(equalToConstant: 48.swh),
            colorSwatch.heightAnchor.constraint(equalToConstant: 48.swh),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ selected: Bool) {
        selectionRing.isHidden = !selected
        UIView.animate(withDuration: 0.2) {
            self.colorSwatch.layer.cornerRadius = selected ? 10.swh : 14.swh
        }
    }
}
