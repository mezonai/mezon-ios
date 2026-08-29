import AsyncDisplayKit
import UIKit

final class IntegrationsViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64

    private let scrollView = UIScrollView()
    private let contentView = UIStackView()
    private let descriptionTextView = UITextView()
    private let listContainer = UIView()

    init(context: AccountContext, clanId: Int64) {
        self.context = context
        self.clanId = clanId
        super.init(navigationBarPresentationData: nil)
        title = L(L10n.Integrations.title)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.theme.primary
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func applyTheme() {
        super.applyTheme()
        let t = UIColor.theme
        view.backgroundColor = t.primary
        titleLabel.textColor = t.textStrong
        backButton.tintColor = t.textStrong
        listContainer.backgroundColor = t.secondary
        
        if let attrText = descriptionTextView.attributedText?.mutableCopy() as? NSMutableAttributedString {
            attrText.addAttribute(.foregroundColor, value: t.textDisabled, range: NSRange(location: 0, length: attrText.length))
            descriptionTextView.attributedText = attrText
        }
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(UIImage.mezonSystemImage("chevron.left")?.withRenderingMode(.alwaysTemplate), for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(backButton)

        titleLabel.text = L(L10n.Integrations.title)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 44.sh),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16.sw),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 24.swh),
            backButton.heightAnchor.constraint(equalToConstant: 24.swh),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    override func setupUI() {
        setupHeader()

        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        contentView.axis = .vertical
        contentView.spacing = 24.sh
        contentView.alignment = .fill
        scrollView.addSubview(contentView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16.sh),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16.sw),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16.sw),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16.sh),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32.sw)
        ])

        setupDescription()
        setupList()
    }

    private func setupDescription() {
        let text = L(L10n.Integrations.description) + " " + L(L10n.Integrations.learnMore)
        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf, weight: .regular),
                .foregroundColor: UIColor.theme.textDisabled
            ]
        )
        
        let linkRange = (text as NSString).range(of: L(L10n.Integrations.learnMore))
        if linkRange.location != NSNotFound {
            let urlString = "\(MezonConfig.chatWebAppBaseURL)/docs/en/developer/webhooks/overview/"
            attributedString.addAttribute(.link, value: urlString, range: linkRange)
        }

        descriptionTextView.attributedText = attributedString
        descriptionTextView.isEditable = false
        descriptionTextView.isScrollEnabled = false
        descriptionTextView.backgroundColor = .clear
        descriptionTextView.textContainerInset = .zero
        descriptionTextView.textContainer.lineFragmentPadding = 0
        descriptionTextView.delegate = self
        descriptionTextView.linkTextAttributes = [
            .foregroundColor: UIColor.theme.bgViolet
        ]
        
        contentView.addArrangedSubview(descriptionTextView)
    }

    private func setupList() {
        listContainer.backgroundColor = UIColor.theme.secondary
        listContainer.layer.cornerRadius = 12.swh
        listContainer.clipsToBounds = true

        let listStack = UIStackView()
        listStack.axis = .vertical
        listContainer.addSubview(listStack)

        listStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            listStack.topAnchor.constraint(equalTo: listContainer.topAnchor),
            listStack.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
            listStack.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor)
        ])

        let webhooksRow = createRow(
            title: L(L10n.Integrations.webhooks),
            subtitle: L(L10n.Integrations.messagesUpdates),
            icon: "ClanSetting/WebhookIcon",
            action: #selector(webhooksTapped)
        )
        
        let separatorContainer = UIView()
        separatorContainer.backgroundColor = .clear
        let separator = UIView()
        separator.backgroundColor = UIColor.theme.border
        separator.translatesAutoresizingMaskIntoConstraints = false
        separatorContainer.addSubview(separator)
        
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: separatorContainer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: separatorContainer.trailingAnchor),
            separator.topAnchor.constraint(equalTo: separatorContainer.topAnchor),
            separator.bottomAnchor.constraint(equalTo: separatorContainer.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale)
        ])

        let clanWebhooksRow = createRow(
            title: L(L10n.Integrations.clanWebhooks),
            subtitle: L(L10n.Integrations.messagesUpdates),
            icon: "ClanSetting/WebhookIcon",
            action: #selector(clanWebhooksTapped)
        )

        listStack.addArrangedSubview(webhooksRow)
        listStack.addArrangedSubview(separatorContainer)
        listStack.addArrangedSubview(clanWebhooksRow)

        contentView.addArrangedSubview(listContainer)
    }

    private func createRow(title: String, subtitle: String, icon: String, action: Selector) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let iconView = UIImageView(image: UIImage(named: icon)?.withRenderingMode(.alwaysTemplate))
        iconView.tintColor = UIColor.theme.textStrong
        iconView.contentMode = .scaleAspectFit
        view.addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        titleLabel.textColor = UIColor.theme.textStrong
        view.addSubview(titleLabel)

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12.sf, weight: .regular)
        subtitleLabel.textColor = UIColor.theme.textDisabled
        view.addSubview(subtitleLabel)

        let chevron = UIImageView(image: UIImage.mezonSystemImage("chevron.right")?.withRenderingMode(.alwaysTemplate))
        chevron.tintColor = UIColor.theme.textStrong
        chevron.contentMode = .scaleAspectFit
        view.addSubview(chevron)

        let button = UIButton(type: .system)
        button.addTarget(self, action: action, for: .touchUpInside)
        view.addSubview(button)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24.swh),
            iconView.heightAnchor.constraint(equalToConstant: 24.swh),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12.sw),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16.sh),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4.sh),
            subtitleLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16.sh),

            chevron.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            chevron.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12.swh),
            chevron.heightAnchor.constraint(equalToConstant: 12.swh),
            chevron.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 16.sw),

            button.topAnchor.constraint(equalTo: view.topAnchor),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        return view
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func webhooksTapped() {
        let vc = WebhookListViewController(
            context: context,
            clanId: clanId,
            channelId: 0,
            isClanIntegration: false,
            isClanSetting: true
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func clanWebhooksTapped() {
        let vc = WebhookListViewController(
            context: context,
            clanId: clanId,
            channelId: 0,
            isClanIntegration: true,
            isClanSetting: false
        )
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension IntegrationsViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        UIApplication.shared.open(URL)
        return false
    }
}
