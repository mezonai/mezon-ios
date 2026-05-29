import UIKit

@MainActor
final class WebhookListViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64

    private var webhooks: [Mezon_Api_Webhook] = []
    private var members: [ClanMemberRecord] = []
    private var isCreating: Bool = false

    private let webhookNames = ["Captain hook", "Spidey bot", "Komu Knight"]
    private var webhookAvatars: [String] {
        let baseUrl = MezonEnvironment.current.baseImgURL
        return [
            "\(baseUrl)/1787707828677382144/1791037204600983552/1787691797724532700/211_0mezon_logo_white.png",
            "\(baseUrl)/1787707828677382144/1791037204600983552/1787691797724532700/211_1mezon_logo_black.png",
            "\(baseUrl)/0/1833395573034586112/1787375123666309000/955_0mezon_logo.png"
        ]
    }

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    private final class DynamicTableView: UITableView {
        override var contentSize: CGSize {
            didSet { invalidateIntrinsicContentSize() }
        }
        override var intrinsicContentSize: CGSize {
            layoutIfNeeded()
            return CGSize(width: UIView.noIntrinsicMetric, height: contentSize.height)
        }
    }

    private let scrollView = UIScrollView()
    private let containerView = UIView()
    private let tableView = DynamicTableView(frame: .zero, style: .plain)

    private let emptyView = UIView()
    private let emptyIcon = UIImageView()
    private let emptyLabel = UILabel()

    private let descriptionTextView = UITextView()
    private let addButton = UIButton(type: .system)

    private let isClanIntegration: Bool
    private let isClanSetting: Bool

    init(context: AccountContext, clanId: Int64, channelId: Int64, isClanIntegration: Bool = false, isClanSetting: Bool = false) {
        self.context = context
        self.clanId = clanId
        self.channelId = channelId
        self.isClanIntegration = isClanIntegration
        self.isClanSetting = isClanSetting
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) { fatalError() }

    override func setupUI() {
        view.backgroundColor = UIColor.theme.primary
        setupHeader()
        setupTableView()
        setupEmptyView()
        setupAddButton()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        fetchWebhooks()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        fetchWebhooks()
    }

    override func applyTheme() {
        view.backgroundColor = UIColor.theme.primary
        titleLabel.textColor = UIColor.theme.textStrong
        backButton.tintColor = UIColor.theme.textStrong
        emptyIcon.tintColor = UIColor.theme.textDisabled
        emptyLabel.textColor = UIColor.theme.textDisabled
        addButton.tintColor = .white
        addButton.backgroundColor = UIColor.theme.bgViolet
        tableView.reloadData()
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate), for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        
        if isClanIntegration {
            titleLabel.text = L(L10n.Integrations.clanWebhooks)
        } else {
            titleLabel.text = L(L10n.Webhook.title)
        }
        
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.textAlignment = .center

        [backButton, titleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50.sh),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8.sw),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44.swh),
            backButton.heightAnchor.constraint(equalToConstant: 44.swh),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    private func setupTableView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(containerView)

        descriptionTextView.translatesAutoresizingMaskIntoConstraints = false
        
        let text: String
        let linkText: String
        let urlString: String
        
        if isClanIntegration {
            text = L(L10n.Webhook.clanDescription) + L(L10n.Webhook.clanDescriptionTip)
            linkText = L(L10n.Webhook.clanDescriptionTip)
            urlString = "\(MezonConfig.chatWebAppBaseURL)/docs/en/developer/webhooks/clan-webhook"
        } else {
            text = L(L10n.Webhook.description) + " " + L(L10n.Webhook.learnMore)
            linkText = L(L10n.Webhook.learnMore)
            urlString = "\(MezonConfig.chatWebAppBaseURL)/docs/en/developer/webhooks/channel-webhook/"
        }
        
        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf, weight: .regular),
                .foregroundColor: UIColor.theme.textDisabled
            ]
        )
        
        let linkRange = (text as NSString).range(of: linkText)
        if linkRange.location != NSNotFound {
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
        
        containerView.addSubview(descriptionTextView)

        tableView.backgroundColor = UIColor.theme.secondary
        tableView.layer.cornerRadius = 12
        tableView.clipsToBounds = true
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(WebhookItemCell.self, forCellReuseIdentifier: WebhookItemCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.showsVerticalScrollIndicator = false
        tableView.isScrollEnabled = false
        containerView.addSubview(tableView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 10.sh),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            containerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            containerView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            
            descriptionTextView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 4.sh),
            descriptionTextView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16.sw),
            descriptionTextView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16.sw),

            tableView.topAnchor.constraint(equalTo: descriptionTextView.bottomAnchor, constant: 16.sh),
            tableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16.sw),
            tableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16.sw),
            tableView.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -16.sh)
        ])
    }

    private func setupEmptyView() {
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.isHidden = true
        view.addSubview(emptyView)

        emptyIcon.image = UIImage(named: "ChannelSetting/EmptyWebhook")?.withRenderingMode(.alwaysOriginal)
        emptyIcon.contentMode = .scaleAspectFit
        emptyIcon.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.text = L(L10n.Webhook.noWebhooks)
        emptyLabel.font = .systemFont(ofSize: 16.sf, weight: .medium)
        emptyLabel.textColor = UIColor.theme.textDisabled
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        emptyView.addSubview(emptyIcon)
        emptyView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            emptyIcon.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
            emptyIcon.topAnchor.constraint(equalTo: emptyView.topAnchor),
            emptyIcon.widthAnchor.constraint(equalToConstant: 200.swh),
            emptyIcon.heightAnchor.constraint(equalToConstant: 200.swh),

            emptyLabel.topAnchor.constraint(equalTo: emptyIcon.bottomAnchor, constant: -16.sh),
            emptyLabel.leadingAnchor.constraint(equalTo: emptyView.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(equalTo: emptyView.trailingAnchor),
            emptyLabel.bottomAnchor.constraint(equalTo: emptyView.bottomAnchor)
        ])
    }

    private func setupAddButton() {
        addButton.setImage(UIImage(systemName: "plus")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 22.sf, weight: .bold)
        ), for: .normal)
        addButton.tintColor = .white
        addButton.backgroundColor = UIColor.theme.bgViolet
        addButton.layer.cornerRadius = 28.swh
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addButton)

        NSLayoutConstraint.activate([
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20.sw),
            addButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20.sh),
            addButton.widthAnchor.constraint(equalToConstant: 56.swh),
            addButton.heightAnchor.constraint(equalToConstant: 56.swh)
        ])
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func addTapped() {
        handleAddWebhook()
    }

    private func fetchWebhooks() {
        Task { [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            do {
                if self.isClanIntegration {
                    let clanWebhooks = try await MezonHTTPClient.shared.listClanWebhooks(clanId: self.clanId, token: token)
                    self.webhooks = clanWebhooks.map { $0.toWebhook() }.sorted { $0.id < $1.id }
                } else {
                    let fetchChannelId = self.isClanSetting ? 0 : self.channelId
                    self.webhooks = try await MezonHTTPClient.shared.listWebhooksByChannelId(
                        channelId: fetchChannelId,
                        clanId: self.clanId,
                        token: token
                    ).sorted { $0.id < $1.id }
                }
                self.members = self.context.account.postbox.read { $0.getClanMembers(clanId: self.clanId) }
                self.reloadUI()
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func reloadUI() {
        tableView.reloadData()
        emptyView.isHidden = !webhooks.isEmpty
        tableView.isHidden = webhooks.isEmpty
    }

    private func handleAddWebhook() {
        guard !isCreating else { return }
        
        if !isClanIntegration && isClanSetting {
            let vc = WebhookSelectChannelViewController(
                context: context,
                clanId: clanId,
                currentChannelId: channelId
            ) { [weak self] selectedChannel in
                self?.performAddWebhook(for: selectedChannel.channelID)
            }
            vc.modalPresentationStyle = .pageSheet
            if #available(iOS 15.0, *) {
                vc.sheetPresentationController?.detents = [.medium(), .large()]
            }
            present(vc, animated: true)
            return
        }
        
        performAddWebhook(for: self.channelId)
    }

    private func performAddWebhook(for channelId: Int64) {
        isCreating = true
        addButton.isEnabled = false
        
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.isCreating = false
                self.addButton.isEnabled = true
            }
            
            guard let token = await self.context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            
            do {
                if self.isClanIntegration {
                    var req = Mezon_Api_GenerateClanWebhookRequest()
                    req.clanID = self.clanId
                    req.webhookName = self.webhookNames.randomElement() ?? "Captain hook"
                    req.avatar = self.webhookAvatars.randomElement() ?? ""
                    _ = try await MezonHTTPClient.shared.generateClanWebhook(request: req, token: token)
                } else {
                    var req = Mezon_Api_WebhookCreateRequest()
                    req.channelID = channelId
                    req.clanID = self.clanId
                    req.webhookName = self.webhookNames.randomElement() ?? "Captain hook"
                    req.avatar = self.webhookAvatars.randomElement() ?? ""
                    _ = try await MezonHTTPClient.shared.generateWebhook(request: req, token: token)
                }
                
                Toast.success(L(L10n.Webhook.addSuccess))
                self.fetchWebhooks()
            } catch {
                Toast.error(L(L10n.Webhook.addError))
            }
        }
    }

    private func openEditWebhook(_ webhook: Mezon_Api_Webhook) {
        let vc = WebhookEditViewController(
            context: context,
            clanId: clanId,
            channelId: webhook.channelID,
            webhook: webhook,
            isClanIntegration: isClanIntegration
        )
        vc.onWebhookUpdated = { [weak self] in
            self?.fetchWebhooks()
        }
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension WebhookListViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        UIApplication.shared.open(URL)
        return false
    }
}

extension WebhookListViewController: UITableViewDelegate, UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return webhooks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: WebhookItemCell.reuseId, for: indexPath) as! WebhookItemCell
        let webhook = webhooks[indexPath.row]
        
        var creatorName = "Unknown"
        if let member = members.first(where: { $0.userId == webhook.creatorID }), !member.username.isEmpty {
            creatorName = member.username
        }
        
        let isLast = indexPath.row == webhooks.count - 1
        cell.configure(with: webhook, creatorName: creatorName, isLast: isLast)
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72.sh
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        openEditWebhook(webhooks[indexPath.row])
    }
}

final class WebhookItemCell: UITableViewCell {

    static let reuseId = "WebhookItemCell"

    private let avatarView = TextAvatarView(username: "", size: 40)
    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let clockIconView = UIImageView()
    private let subtitleLabel = UILabel()
    private let chevronView = UIImageView()
    private let separatorView = UIView()
    private var imageTask: URLSessionDataTask?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 20
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.isHidden = true
        contentView.addSubview(avatarImageView)

        nameLabel.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        nameLabel.textColor = UIColor.theme.textStrong
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        clockIconView.image = UIImage(named: "ClanSetting/ClockIcon")?.withRenderingMode(.alwaysTemplate)
        clockIconView.tintColor = UIColor.theme.textDisabled
        clockIconView.contentMode = .scaleAspectFit
        clockIconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(clockIconView)

        subtitleLabel.font = .systemFont(ofSize: 12.sf)
        subtitleLabel.textColor = UIColor.theme.textDisabled
        subtitleLabel.numberOfLines = 1
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)

        let arrowImage = UIImage(named: "Channel/ChevronRight")?.withRenderingMode(.alwaysTemplate)
            ?? UIImage(systemName: "chevron.right")?.withRenderingMode(.alwaysTemplate)
        chevronView.image = arrowImage
        chevronView.tintColor = UIColor.theme.textStrong
        chevronView.contentMode = .scaleAspectFit
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(chevronView)

        separatorView.backgroundColor = UIColor.theme.border
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separatorView)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16.sw),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40.swh),
            avatarView.heightAnchor.constraint(equalToConstant: 40.swh),

            avatarImageView.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            avatarImageView.topAnchor.constraint(equalTo: avatarView.topAnchor),
            avatarImageView.widthAnchor.constraint(equalTo: avatarView.widthAnchor),
            avatarImageView.heightAnchor.constraint(equalTo: avatarView.heightAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12.sw),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -8.sw),
            nameLabel.topAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -18.sh),

            clockIconView.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            clockIconView.centerYAnchor.constraint(equalTo: subtitleLabel.centerYAnchor),
            clockIconView.widthAnchor.constraint(equalToConstant: 12.swh),
            clockIconView.heightAnchor.constraint(equalToConstant: 12.swh),

            subtitleLabel.leadingAnchor.constraint(equalTo: clockIconView.trailingAnchor, constant: 4.sw),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -8.sw),
            subtitleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3.sh),

            chevronView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16.sw),
            chevronView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 14.swh),
            chevronView.heightAnchor.constraint(equalToConstant: 14.swh),

            separatorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale)
        ])
    }

    func configure(with webhook: Mezon_Api_Webhook, creatorName: String, isLast: Bool) {
        nameLabel.text = webhook.webhookName
        let dateStr = formatCreatedDate(webhook.createTime)
        subtitleLabel.text = String(format: L(L10n.Webhook.createdBy), dateStr, creatorName)
        separatorView.isHidden = isLast

        avatarView.configure(username: webhook.webhookName)

        imageTask?.cancel()
        if !webhook.avatar.isEmpty, let url = URL(string: webhook.avatar) {
            if let cachedImage = WebhookAvatarCache.shared.object(forKey: webhook.avatar as NSString) {
                avatarImageView.image = cachedImage
                avatarImageView.isHidden = false
                avatarView.showImageMode()
                return
            }
            avatarView.showSkeleton()
            imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
                guard error == nil, let data = data, let image = UIImage(data: data) else {
                    DispatchQueue.main.async {
                        self?.avatarImageView.isHidden = true
                        self?.avatarView.showPlaceholder()
                    }
                    return
                }
                WebhookAvatarCache.shared.setObject(image, forKey: webhook.avatar as NSString)
                DispatchQueue.main.async {
                    self?.avatarImageView.image = image
                    self?.avatarImageView.isHidden = false
                    self?.avatarView.showImageMode()
                }
            }
            imageTask?.resume()
        } else {
            avatarImageView.isHidden = true
            avatarView.showPlaceholder()
        }
    }

    private func formatCreatedDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else {
            let fallback = ISO8601DateFormatter()
            guard let d = fallback.date(from: isoString) else { return isoString }
            return formatDisplay(d)
        }
        return formatDisplay(date)
    }

    private func formatDisplay(_ date: Date) -> String {
        let display = DateFormatter()
        display.dateFormat = "dd MMMM yyyy"
        display.locale = LanguageManager.shared.current.locale
        return display.string(from: date)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        avatarImageView.image = nil
        avatarImageView.isHidden = true
        avatarView.showPlaceholder()
    }
}

extension Mezon_Api_ClanWebhook {
    func toWebhook() -> Mezon_Api_Webhook {
        var webhook = Mezon_Api_Webhook()
        webhook.id = self.id
        webhook.webhookName = self.webhookName
        webhook.clanID = self.clanID
        webhook.active = self.active
        webhook.url = self.url
        webhook.creatorID = self.creatorID
        webhook.avatar = self.avatar
        webhook.createTime = self.createTime
        webhook.updateTime = self.updateTime
        webhook.channelID = 0
        return webhook
    }
}
