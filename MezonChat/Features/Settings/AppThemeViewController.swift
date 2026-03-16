import UIKit

final class AppThemeViewController: BaseViewController {

    private var selectedTheme: AppTheme = ThemeManager.shared.current

    private let headerView = UIView()
    private let backButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        btn.setImage(img, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

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
        sv.spacing = 10.sw
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var footerLabel: UILabel = {
        let l = UILabel()
        l.text = L(L10n.Theme.canChangeLater)
        l.font = .systemFont(ofSize: 13.sf)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        return l
    }()

    private var swatchButtons: [ThemeSwatchButton] = []

    override func setupUI() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        headerView.addSubview(backButton)
        headerView.addSubview(titleLabel)

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        let headerHeight: CGFloat = 96

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: headerHeight),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16.sw),
            backButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -8.sh),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -16.sw),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

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
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 32.sh),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -32.sh),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            previewCard.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor, constant: 32.sw),
            previewCard.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor, constant: -32.sw),
            previewCard.heightAnchor.constraint(equalToConstant: 400.sh),

            swatchScroll.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            swatchScroll.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor),
            swatchScroll.heightAnchor.constraint(equalToConstant: 88.sh),
        ])

        refresh(theme: selectedTheme, animated: false)
    }

    override func applyTheme() {
        titleLabel.text = L(L10n.Theme.title)
        titleLabel.textColor = .mezonTextStrong
        backButton.tintColor = .mezonTextStrong
        headerView.backgroundColor = .mezonPrimary
        view.backgroundColor = .mezonPrimary
        scrollView.backgroundColor = .mezonPrimary
        themeNameLabel.textColor = .mezonTextStrong
        footerLabel.textColor = .mezonTextPrimary
        footerLabel.text = L(L10n.Theme.canChangeLater)
        selectedTheme = ThemeManager.shared.current
        refresh(theme: selectedTheme, animated: false)
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
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
            self.themeNameLabel.text = theme.localizedDisplayName
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

    private let gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.startPoint = CGPoint(x: 1, y: 0)
        gl.endPoint = CGPoint(x: 0, y: 0)
        return gl
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = L(L10n.Theme.conversation)
        l.font = .systemFont(ofSize: 18.sf, weight: .bold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var rowStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 6.sh
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
        layer.borderWidth = 1
        clipsToBounds = false

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 3.sh)
        layer.shadowOpacity = 0.27
        layer.shadowRadius = 4.65

        let gradientContainer = UIView()
        gradientContainer.clipsToBounds = true
        gradientContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gradientContainer)
        gradientContainer.layer.insertSublayer(gradientLayer, at: 0)

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

        let innerStack = UIStackView(arrangedSubviews: [titleLabel, rowStack])
        innerStack.axis = .vertical
        innerStack.spacing = 8.sh
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        gradientContainer.addSubview(innerStack)

        NSLayoutConstraint.activate([
            gradientContainer.topAnchor.constraint(equalTo: topAnchor),
            gradientContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            gradientContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            gradientContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            innerStack.centerYAnchor.constraint(equalTo: gradientContainer.centerYAnchor),
            innerStack.leadingAnchor.constraint(equalTo: gradientContainer.leadingAnchor),
            innerStack.trailingAnchor.constraint(equalTo: gradientContainer.trailingAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: innerStack.leadingAnchor, constant: 20.sw),
            titleLabel.trailingAnchor.constraint(equalTo: innerStack.trailingAnchor, constant: -20.sw),
        ])

        self.gradientContainerView = gradientContainer
    }

    private weak var gradientContainerView: UIView?

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = gradientContainerView?.bounds ?? bounds
    }

    func apply(theme: AppTheme) {
        let attrs = theme.attributes
        gradientLayer.colors = [attrs.primary.cgColor, attrs.primaryGradient.cgColor]
        layer.borderColor = attrs.secondary.cgColor
        titleLabel.text = L(L10n.Theme.conversation)
        titleLabel.textColor = attrs.text
        rowStack.arrangedSubviews.forEach { ($0 as? MockConversationRow)?.apply(attrs: attrs) }
    }
}

private final class MockConversationRow: UIView {
    private let avatarView: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 24.swh
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let initialsLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        l.textColor = .white
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let onlineDot: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(red: 0.16, green: 0.73, blue: 0.47, alpha: 1)
        v.layer.cornerRadius = 7.swh
        v.layer.borderWidth = 2
        v.layer.borderColor = UIColor.white.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let timeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10.sf, weight: .medium)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let messageLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12.sf)
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
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20.sw),
            avatarView.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 48.swh),
            avatarView.heightAnchor.constraint(equalToConstant: 48.swh),
            avatarView.topAnchor.constraint(equalTo: topAnchor, constant: 12.sh),
            avatarView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12.sh),

            initialsLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            onlineDot.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 2.sw),
            onlineDot.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 2.sh),
            onlineDot.widthAnchor.constraint(equalToConstant: 14.swh),
            onlineDot.heightAnchor.constraint(equalToConstant: 14.swh),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 16.sw),
            nameLabel.topAnchor.constraint(equalTo: avatarView.topAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8.sw),

            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20.sw),
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            messageLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20.sw),
            messageLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4.sh),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(attrs: ThemeAttributes) {
        nameLabel.textColor    = attrs.text
        messageLabel.textColor = attrs.textDisabled
        timeLabel.textColor    = attrs.textDisabled
        onlineDot.layer.borderColor = attrs.secondary.cgColor
    }
}

private final class ThemeSwatchButton: UIButton {

    let theme: AppTheme

    private let selectionRing: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 12.swh
        v.layer.borderWidth  = 2
        v.layer.borderColor  = UIColor.systemBlue.cgColor
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let colorSwatch: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 8.swh
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
        colorSwatch.layer.borderWidth = 1
        colorSwatch.layer.borderColor = theme.attributes.border.cgColor

        addSubview(selectionRing)
        addSubview(colorSwatch)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 60.swh),
            heightAnchor.constraint(equalToConstant: 72.swh),

            selectionRing.centerXAnchor.constraint(equalTo: centerXAnchor),
            selectionRing.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectionRing.widthAnchor.constraint(equalToConstant: 56.swh),
            selectionRing.heightAnchor.constraint(equalToConstant: 68.swh),

            colorSwatch.centerXAnchor.constraint(equalTo: centerXAnchor),
            colorSwatch.centerYAnchor.constraint(equalTo: centerYAnchor),
            colorSwatch.widthAnchor.constraint(equalToConstant: 48.swh),
            colorSwatch.heightAnchor.constraint(equalToConstant: 58.swh),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ selected: Bool) {
        selectionRing.isHidden = !selected
        UIView.animate(withDuration: 0.2) {
            self.colorSwatch.layer.cornerRadius = 8.swh
        }
    }
}
