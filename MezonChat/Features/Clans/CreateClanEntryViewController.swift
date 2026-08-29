import UIKit

final class CreateClanEntryViewController: BaseViewController {

    private let context: AccountContext

    private let introLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf)
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let sectionLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12.sf, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let scrollView: UIScrollView = {
        let s = UIScrollView()
        s.alwaysBounceVertical = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let contentStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 16.sh
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private var templateRows: [UIControl] = []
    private var ownRowControl: UIControl?

    private let headerView = UIView()
    private let backButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage.mezonSystemImage("chevron.left", withConfiguration: MezonSymbolConfiguration(pointSize: 18, weight: .medium))
        btn.setImage(img, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        l.textAlignment = .center
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let headerTrailingBalance = UIView()

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
        hidesBottomBarWhenPushed = true
    }

    required init(coder: NSCoder) { fatalError() }

    override func setupUI() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        headerView.addSubview(backButton)
        headerView.addSubview(headerTrailingBalance)
        headerView.addSubview(titleLabel)
        headerTrailingBalance.translatesAutoresizingMaskIntoConstraints = false
        headerTrailingBalance.isUserInteractionEnabled = false
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        introLabel.text = L(L10n.Clan.createClanIntroBody)
        sectionLabel.text = L(L10n.Clan.startFromTemplateSection)

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        let headerHeight: CGFloat = 96

        contentStack.addArrangedSubview(introLabel)

        let ownRow = makeSelectableRow(
            iconName: "sparkles",
            iconTint: UIColor(red: 1, green: 0.85, blue: 0.35, alpha: 1),
            title: L(L10n.Clan.createMyOwnTitle),
            tag: -1
        )
        ownRowControl = ownRow

        contentStack.addArrangedSubview(ownRow)
        contentStack.setCustomSpacing(24.sh, after: ownRow)
        contentStack.addArrangedSubview(sectionLabel)

        for t in ClanCreationTemplate.allCases {
            let row = makeSelectableRow(
                iconName: t.iconSystemName,
                iconTint: t.iconTint,
                title: templateTitle(t),
                tag: t.rawValue
            )
            templateRows.append(row)
            contentStack.addArrangedSubview(row)
        }

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: headerHeight),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16.sw),
            backButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -8.sh),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            headerTrailingBalance.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16.sw),
            headerTrailingBalance.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            headerTrailingBalance.widthAnchor.constraint(equalTo: backButton.widthAnchor),
            headerTrailingBalance.heightAnchor.constraint(equalTo: backButton.heightAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: headerTrailingBalance.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8.sh),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28.sh),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    private func templateTitle(_ t: ClanCreationTemplate) -> String {
        switch t {
        case .gaming: return L(L10n.Clan.createTemplateGaming)
        case .friends: return L(L10n.Clan.createTemplateFriends)
        case .studyGroup: return L(L10n.Clan.createTemplateStudyGroup)
        case .schoolClub: return L(L10n.Clan.createTemplateSchoolClub)
        case .localCommunity: return L(L10n.Clan.createTemplateLocalCommunity)
        case .artistsAndCreators: return L(L10n.Clan.createTemplateArtists)
        }
    }

    private func makeSelectableRow(iconName: String, iconTint: UIColor, title: String, tag: Int) -> UIControl {
        let row = UIControl()
        row.tag = tag
        row.layer.cornerRadius = 12.swh
        row.layer.borderWidth = 1
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 52.sh).isActive = true
        row.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)

        let iconView = UIImageView(image: UIImage.mezonSystemImage(iconName))
        iconView.tintColor = iconTint
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 16.sf, weight: .medium)
        titleLabel.textColor = .mezonTextStrong
        titleLabel.text = title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(iconView)
        row.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 26.swh),
            iconView.heightAnchor.constraint(equalToConstant: 26.swh),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -12),
        ])
        return row
    }

    override func applyTheme() {
        view.backgroundColor = .mezonPrimary
        headerView.backgroundColor = .mezonPrimary
        titleLabel.text = L(L10n.Clan.createYourClanTitle)
        titleLabel.textColor = .mezonTextStrong
        backButton.tintColor = .mezonTextStrong
        introLabel.textColor = .mezonTextMuted
        sectionLabel.textColor = .mezonTextMuted
        let bg = UIColor.theme.secondary.withAlphaComponent(0.35)
        let border = UIColor.theme.border.withAlphaComponent(0.55).cgColor
        for row in templateRows {
            row.backgroundColor = bg
            row.layer.borderColor = border
        }
        ownRowControl?.backgroundColor = bg
        ownRowControl?.layer.borderColor = border
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func rowTapped(_ sender: UIControl) {
        let template: ClanCreationTemplate? =
            sender.tag == -1 ? nil : ClanCreationTemplate(rawValue: sender.tag)
        guard sender.tag == -1 || template != nil else { return }
        let vc = CreateClanViewController(context: context, creationTemplate: template)
        navigationController?.pushViewController(vc, animated: true)
    }
}
