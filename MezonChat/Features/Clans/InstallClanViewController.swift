import UIKit

final class InstallClanViewController: UIViewController {
    private let context: AccountContext
    private let appId: Int64
    private let clans: [Mezon_Api_ClanDesc]

    private var selectedClan: Mezon_Api_ClanDesc?
    private var appName: String = ""
    private var appLogo: String = ""

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let avatarView = UIImageView()
    private let avatarPlaceholder = UILabel()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let addToClanLabel = UILabel()
    private let clanPickerButton = UIButton(type: .system)
    private let installButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private var avatarTask: URLSessionDataTask?

    init(context: AccountContext, appId: Int64, clans: [Mezon_Api_ClanDesc]) {
        self.context = context
        self.appId = appId
        self.clans = clans
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.theme.primary
        setupUI()
        updateInstallButtonState()
        if #available(iOS 13.0, *) {
            fetchAppDetail()
        }
    }

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 50
        avatarView.backgroundColor = UIColor.theme.secondary

        avatarPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        avatarPlaceholder.textAlignment = .center
        avatarPlaceholder.font = .systemFont(ofSize: 40, weight: .semibold)
        avatarPlaceholder.textColor = UIColor.theme.textStrong

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = .systemFont(ofSize: 14, weight: .regular)
        descriptionLabel.textColor = UIColor.theme.text
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.text = "This app would be able to access information in the clan you choose."

        addToClanLabel.translatesAutoresizingMaskIntoConstraints = false
        addToClanLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        addToClanLabel.textColor = UIColor.theme.textDisabled
        addToClanLabel.text = "ADD TO CLAN"

        clanPickerButton.translatesAutoresizingMaskIntoConstraints = false
        clanPickerButton.contentHorizontalAlignment = .left
        clanPickerButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 40)
        clanPickerButton.backgroundColor = UIColor.theme.secondary
        clanPickerButton.layer.cornerRadius = 8
        clanPickerButton.setTitleColor(UIColor.theme.text, for: .normal)
        clanPickerButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
        clanPickerButton.titleLabel?.lineBreakMode = .byTruncatingTail
        clanPickerButton.setTitle("Select a clan", for: .normal)
        clanPickerButton.addTarget(self, action: #selector(handleSelectClan), for: .touchUpInside)

        let chevron = UIImageView(image: UIImage.mezonSystemImage("chevron.down"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = UIColor.theme.textDisabled
        chevron.contentMode = .scaleAspectFit
        clanPickerButton.addSubview(chevron)
        NSLayoutConstraint.activate([
            chevron.trailingAnchor.constraint(equalTo: clanPickerButton.trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: clanPickerButton.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 16),
            chevron.heightAnchor.constraint(equalToConstant: 16),
        ])

        installButton.translatesAutoresizingMaskIntoConstraints = false
        installButton.backgroundColor = UIColor.mezonPrimary
        installButton.layer.cornerRadius = 8
        installButton.setTitleColor(.white, for: .normal)
        installButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        installButton.setTitle("Add", for: .normal)
        installButton.addTarget(self, action: #selector(handleInstall), for: .touchUpInside)

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.backgroundColor = UIColor.theme.secondary
        backButton.layer.cornerRadius = 8
        backButton.setTitleColor(UIColor.theme.text, for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        backButton.setTitle("Back", for: .normal)
        backButton.addTarget(self, action: #selector(handleBack), for: .touchUpInside)

        [avatarView, avatarPlaceholder, titleLabel, descriptionLabel, addToClanLabel, clanPickerButton, installButton, backButton].forEach { contentView.addSubview($0) }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 40),
            avatarView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 100),
            avatarView.heightAnchor.constraint(equalToConstant: 100),

            avatarPlaceholder.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarPlaceholder.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            addToClanLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 32),
            addToClanLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            addToClanLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            clanPickerButton.topAnchor.constraint(equalTo: addToClanLabel.bottomAnchor, constant: 10),
            clanPickerButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            clanPickerButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            clanPickerButton.heightAnchor.constraint(equalToConstant: 50),

            installButton.topAnchor.constraint(equalTo: clanPickerButton.bottomAnchor, constant: 28),
            installButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            installButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            installButton.heightAnchor.constraint(equalToConstant: 50),

            backButton.topAnchor.constraint(equalTo: installButton.bottomAnchor, constant: 12),
            backButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            backButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            backButton.heightAnchor.constraint(equalToConstant: 50),
            backButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
        ])
    }

    @available(iOS 13.0, *)
    private func fetchAppDetail() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { return }
            do {
                let app = try await self.context.account.network.getApp(appId: self.appId, token: token)
                self.appName = app.appname
                self.appLogo = app.applogo
                self.applyAppDetail()
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func applyAppDetail() {
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.text = name.isEmpty ? "App" : name
        avatarPlaceholder.text = String(name.prefix(1)).uppercased()
        loadAvatar(from: appLogo)
    }

    private func loadAvatar(from urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            avatarPlaceholder.isHidden = false
            return
        }
        avatarPlaceholder.isHidden = false
        if let cached = ImageCache.shared.memoryImage(forKey: trimmed) {
            avatarView.image = cached
            avatarPlaceholder.isHidden = true
            return
        }
        avatarTask?.cancel()
        avatarTask = ImageCache.shared.loadImage(urlString: trimmed) { [weak self] image in
            guard let image else { return }
            DispatchQueue.main.async {
                self?.avatarView.image = image
                self?.avatarPlaceholder.isHidden = true
            }
        }
    }

    private func updateInstallButtonState() {
        let enabled = selectedClan != nil
        installButton.isEnabled = enabled
        installButton.alpha = 1.0
        installButton.backgroundColor = enabled ? UIColor.mezonPrimary : UIColor.theme.secondary
        installButton.setTitleColor(enabled ? .white : UIColor.theme.textDisabled, for: .normal)
    }

    @objc private func handleSelectClan() {
        guard !clans.isEmpty else {
            Toast.error("You are not a member of any clan")
            return
        }
        let picker = ClanPickerSheetViewController(
            clans: clans,
            selectedClanId: selectedClan?.clanID,
            title: "Select a clan"
        ) { [weak self] clan in
            guard let self else { return }
            self.selectedClan = clan
            self.clanPickerButton.setTitle(clan.clanName, for: .normal)
            self.clanPickerButton.setTitleColor(UIColor.theme.textStrong, for: .normal)
            self.updateInstallButtonState()
        }
        present(picker, animated: true)
    }

    @objc private func handleInstall() {
        if #available(iOS 13.0, *) {
            guard let clan = selectedClan else { return }
            installButton.isEnabled = false
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let token = await self.context.getToken() else {
                    self.updateInstallButtonState()
                    return
                }
                do {
                    try await self.context.account.network.addAppToClan(appId: self.appId, clanId: clan.clanID, token: token)
                    Toast.success("App installed successfully")
                    self.dismiss(animated: true)
                } catch {
                    Toast.error(error.localizedDescription)
                    self.updateInstallButtonState()
                }
            }
        }
    }

    @objc private func handleBack() {
        dismiss(animated: true)
    }

    deinit { avatarTask?.cancel() }
}
